// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "solady/src/utils/SafeTransferLib.sol";
import {ERC20Callee} from "../libraries/ERC20Caller.sol";
import "../libraries/SlipStreamPoolAddress.sol";
import {PoolAddressPancakeSwapV3} from "@aperture_finance/uni-v3-lib/src/PoolAddressPancakeSwapV3.sol";
import {TernaryLib} from "@aperture_finance/uni-v3-lib/src/TernaryLib.sol";
import {OptimalSwap, TickMath, V3PoolCallee} from "../libraries/OptimalSwap.sol";
import {PCSV3Immutables, UniV3Immutables} from "./Immutables.sol";
import {Payments} from "./Payments.sol";
import "./Callback.sol";

/// @title Optimal Swap Router
/// @author Aperture Finance
/// @dev This router swaps through an aggregator to get to approximately the optimal ratio to add liquidity in a UniV3-style
/// pool, then swaps the tokens to the optimal ratio to add liquidity in the same pool.
abstract contract SlipStreamSwapRouter is Payments, UniswapV3Callback {
    using SafeTransferLib for address;
    using TernaryLib for bool;
    using TickMath for int24;

    /// @dev Literal numbers used in sqrtPriceLimitX96 = zeroForOne ? MIN_SQRT_RATIO + 1 : MAX_SQRT_RATIO - 1
    /// = (MAX_SQRT_RATIO - 1) ^ ((MIN_SQRT_RATIO + 1 ^ MAX_SQRT_RATIO - 1) * zeroForOne)
    uint160 internal constant MAX_SQRT_RATIO_LESS_ONE = 1461446703485210103287273052203988822378723970342 - 1;
    /// @dev MIN_SQRT_RATIO + 1 ^ MAX_SQRT_RATIO - 1
    uint160 internal constant XOR_SQRT_RATIO =
        (4295128739 + 1) ^ (1461446703485210103287273052203988822378723970342 - 1);

    /// @notice Deterministically computes the pool address given the pool key
    /// @param poolKey The pool key
    /// @return pool The contract address of the pool
    function computeAddressSorted(SlipStreamPoolAddress.PoolKey memory poolKey) internal view returns (address pool) {
        pool = SlipStreamPoolAddress.computeAddressSorted(factory, poolKey);
    }

    /// @dev Make a direct `exactIn` pool swap
    /// @param poolKey The pool key containing the token addresses and fee tier
    /// @param pool The address of the pool
    /// @param amountIn The amount of token to be swapped
    /// @param zeroForOne The direction of the swap, true for token0 to token1, false for token1 to token0
    /// @return amountOut The amount of token received after swap
    function _poolSwap(
        SlipStreamPoolAddress.PoolKey memory poolKey,
        address pool,
        uint256 amountIn,
        bool zeroForOne
    ) internal returns (uint256 amountOut) {
        if (amountIn != 0) {
            uint256 wordBeforePoolKey;
            bytes memory data;
            assembly ("memory-safe") {
                // Equivalent to `data = abi.encode(poolKey)`
                data := sub(poolKey, 0x20)
                wordBeforePoolKey := mload(data)
                mstore(data, 0x60)
            }
            uint160 sqrtPriceLimitX96;
            // Equivalent to `sqrtPriceLimitX96 = zeroForOne ? MIN_SQRT_RATIO + 1 : MAX_SQRT_RATIO - 1`
            assembly {
                sqrtPriceLimitX96 := xor(MAX_SQRT_RATIO_LESS_ONE, mul(XOR_SQRT_RATIO, zeroForOne))
            }
            (int256 amount0Delta, int256 amount1Delta) = V3PoolCallee.wrap(pool).swap(
                address(this),
                zeroForOne,
                int256(amountIn),
                sqrtPriceLimitX96,
                data
            );
            unchecked {
                amountOut = 0 - zeroForOne.ternary(uint256(amount1Delta), uint256(amount0Delta));
            }
            assembly ("memory-safe") {
                // Restore the memory word before `poolKey`
                mstore(data, wordBeforePoolKey)
            }
        }
    }

    /// @dev Make an `exactIn` swap through a whitelisted external router
    /// @param poolKey The pool key containing the token addresses and fee tier
    /// @param router The address of the external router
    /// @param zeroForOne The direction of the swap, true for token0 to token1, false for token1 to token0
    /// @param swapData The address of the external router and call data, not abi-encoded
    /// @return amountOut The amount of token received after swap
    function _routerSwap(
        SlipStreamPoolAddress.PoolKey memory poolKey,
        address router,
        bool zeroForOne,
        bytes calldata swapData
    ) internal returns (uint256 amountOut) {
        (address tokenIn, address tokenOut) = zeroForOne.switchIf(poolKey.token1, poolKey.token0);
        uint256 balanceBefore = ERC20Callee.wrap(tokenOut).balanceOf(address(this));
        // Approve `router` to spend `tokenIn`
        tokenIn.safeApprove(router, type(uint256).max);
        /*
            If `swapData` is encoded as `abi.encode(router, data)`, the memory layout will be:
            0x00         : 0x20         : 0x40         : 0x60         : 0x80
            total length : router       : 0x40 (offset): data length  : data
            Instead, we encode it as:
            ```
            bytes memory swapData = abi.encodePacked(router, data);
            ```
            So the memory layout will be:
            0x00         : 0x20         : 0x34
            total length : router       : data
            To decode it in memory, one can use:
            ```
            bytes memory data;
            assembly {
                router := shr(96, mload(add(swapData, 0x20)))
                data := add(swapData, 0x14)
                mstore(data, sub(mload(swapData), 0x14))
            }
            ```
            knowing that `data.length == swapData.length - 20`.
        */
        assembly ("memory-safe") {
            let fmp := mload(0x40)
            // Strip the first 20 bytes of `swapData` which is the router address.
            let calldataLength := sub(swapData.length, 20)
            calldatacopy(fmp, add(swapData.offset, 20), calldataLength)
            // Ignore the return data unless an error occurs
            if iszero(call(gas(), router, 0, fmp, calldataLength, 0, 0)) {
                returndatacopy(0, 0, returndatasize())
                // Bubble up the revert reason.
                revert(0, returndatasize())
            }
        }
        // Reset approval
        tokenIn.safeApprove(router, 0);
        uint256 balanceAfter = ERC20Callee.wrap(tokenOut).balanceOf(address(this));
        unchecked {
            amountOut = balanceAfter - balanceBefore;
        }
    }

    /// @dev Swap tokens to the optimal ratio to add liquidity in the same pool
    /// @param poolKey The pool key containing the token addresses and fee tier
    /// @param tickLower The lower tick of the position in which to add liquidity
    /// @param tickUpper The upper tick of the position in which to add liquidity
    /// @param amount0Desired The desired amount of token0 to be spent
    /// @param amount1Desired The desired amount of token1 to be spent
    /// @return amount0 The amount of token0 after swap
    /// @return amount1 The amount of token1 after swap
    function _optimalSwapWithPool(
        SlipStreamPoolAddress.PoolKey memory poolKey,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) internal returns (uint256 amount0, uint256 amount1) {
        address pool = computeAddressSorted(poolKey);
        (uint256 amountIn, , bool zeroForOne, ) = OptimalSwap.getOptimalSwap(
            V3PoolCallee.wrap(pool),
            tickLower,
            tickUpper,
            amount0Desired,
            amount1Desired
        );
        uint256 amountOut = _poolSwap(poolKey, pool, amountIn, zeroForOne);
        unchecked {
            // amount0 = amount0Desired + zeroForOne ? - amountIn : amountOut
            // amount1 = amount1Desired + zeroForOne ? amountOut : - amountIn
            (amount0, amount1) = zeroForOne.switchIf(amountOut, 0 - amountIn);
            amount0 += amount0Desired;
            amount1 += amount1Desired;
        }
    }

    /// @dev Swap tokens to the optimal ratio to add liquidity with an external router
    /// @param poolKey The pool key containing the token addresses and fee tier
    /// @param router The address of the external router
    /// @param tickLower The lower tick of the position in which to add liquidity
    /// @param tickUpper The upper tick of the position in which to add liquidity
    /// @param amount0Desired The desired amount of token0 to be spent
    /// @param amount1Desired The desired amount of token1 to be spent
    /// @return amount0 The amount of token0 after swap
    /// @return amount1 The amount of token1 after swap
    function _optimalSwapWithRouter(
        SlipStreamPoolAddress.PoolKey memory poolKey,
        address router,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Desired,
        uint256 amount1Desired,
        bytes calldata swapData
    ) internal returns (uint256 amount0, uint256 amount1) {
        (uint160 sqrtPriceX96, ) = V3PoolCallee.wrap(computeAddressSorted(poolKey)).sqrtPriceX96AndTick();
        bool zeroForOne = OptimalSwap.isZeroForOne(
            amount0Desired,
            amount1Desired,
            sqrtPriceX96,
            tickLower.getSqrtRatioAtTick(),
            tickUpper.getSqrtRatioAtTick()
        );
        _routerSwap(poolKey, router, zeroForOne, swapData);
        amount0 = ERC20Callee.wrap(poolKey.token0).balanceOf(address(this));
        amount1 = ERC20Callee.wrap(poolKey.token1).balanceOf(address(this));
    }
}
