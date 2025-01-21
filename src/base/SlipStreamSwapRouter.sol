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
abstract contract SlipStreamSwapRouter is Payments, SlipStreamCallback {
    using SafeTransferLib for address;
    using TernaryLib for bool;
    using TickMath for int24;

    /// @dev Literal numbers used in sqrtPriceLimitX96 = zeroForOne ? MIN_SQRT_RATIO + 1 : MAX_SQRT_RATIO - 1
    /// = (MAX_SQRT_RATIO - 1) ^ ((MIN_SQRT_RATIO + 1 ^ MAX_SQRT_RATIO - 1) * zeroForOne)
    uint160 internal constant MAX_SQRT_RATIO_LESS_ONE = 1461446703485210103287273052203988822378723970342 - 1;
    /// @dev MIN_SQRT_RATIO + 1 ^ MAX_SQRT_RATIO - 1
    /// @dev Can't refer to `MAX_SQRT_RATIO_LESS_ONE` in the expression since we want to use `XOR_SQRT_RATIO` in assembly.
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

    function _routerSwapFromTokenInToTokenOutHelper(
        address tokenIn,
        address approvalTarget,
        address router,
        bytes calldata data
    ) internal {
        tokenIn.safeApprove(approvalTarget, type(uint256).max);
        assembly ("memory-safe") {
            let fmp := mload(0x40)
            calldatacopy(fmp, data.offset, data.length)
            // Ignore the return data unless an error occurs
            if iszero(call(gas(), router, 0, fmp, data.length, 0, 0)) {
                returndatacopy(0, 0, returndatasize())
                // Bubble up the revert reason.
                revert(0, returndatasize())
            }
        }
        tokenIn.safeApprove(approvalTarget, 0);
    }

    /// @dev Make an `exactIn` swap through a whitelisted external router
    /// @param poolKey The pool key containing the token addresses and fee tier
    /// @param swapData The address of the external router and call data, not abi-encoded
    /// @return amountOut The amount of token received after swap
    function _routerSwapFromTokenInToTokenOut(
        SlipStreamPoolAddress.PoolKey memory poolKey,
        bytes calldata swapData
    ) internal returns (uint256 amountOut) {
        bool zeroForOne;
        address approvalTarget;
        address router;
        assembly {
            // For explanation, see around line 125 of src/base/SwapRouter.sol
            zeroForOne := calldataload(add(swapData.offset, 38))
            approvalTarget := calldataload(add(swapData.offset, 58))
            router := calldataload(add(swapData.offset, 78))
        }
        (address tokenIn, address tokenOut) = zeroForOne.switchIf(poolKey.token1, poolKey.token0);
        uint256 balanceBefore = ERC20Callee.wrap(tokenOut).balanceOf(address(this));
        _routerSwapFromTokenInToTokenOutHelper(tokenIn, approvalTarget, router, swapData);
        uint256 balanceAfter = ERC20Callee.wrap(tokenOut).balanceOf(address(this));
        unchecked {
            amountOut = balanceAfter - balanceBefore;
        }
    }

    function _routerSwapToOptimalRatio(
        SlipStreamPoolAddress.PoolKey memory poolKey,
        int24 tickLower,
        int24 tickUpper,
        bytes calldata swapData
    ) internal {
        _routerSwapFromTokenInToTokenOut(poolKey, swapData);
        bool zeroForOne;
        assembly {
            // For explanation, see around line 125 of src/base/SwapRouter.sol
            zeroForOne := calldataload(add(swapData.offset, 38))
        }
        uint256 balance0 = ERC20Callee.wrap(poolKey.token0).balanceOf(address(this));
        uint256 balance1 = ERC20Callee.wrap(poolKey.token1).balanceOf(address(this));
        uint256 amountIn;
        uint256 amountOut;
        {
            address pool = computeAddressSorted(poolKey);
            uint256 amount0Desired;
            uint256 amount1Desired;
            // take into account the balance not pulled from the sender
            if (zeroForOne) {
                amount0Desired = balance0;
                amount1Desired = balance1 + ERC20Callee.wrap(poolKey.token1).balanceOf(msg.sender);
            } else {
                amount0Desired = balance0 + ERC20Callee.wrap(poolKey.token0).balanceOf(msg.sender);
                amount1Desired = balance1;
            }
            (amountIn, , zeroForOne, ) = OptimalSwap.getOptimalSwap(
                V3PoolCallee.wrap(pool),
                tickLower,
                tickUpper,
                amount0Desired,
                amount1Desired
            );
            amountOut = _poolSwap(poolKey, pool, amountIn, zeroForOne);
        }
        // balance0 = balance0 + zeroForOne ? - amountIn : amountOut
        // balance1 = balance1 + zeroForOne ? amountOut : - amountIn
        assembly {
            let minusAmountIn := sub(0, amountIn)
            let diff := mul(xor(amountOut, minusAmountIn), zeroForOne)
            balance0 := add(balance0, xor(amountOut, diff))
            balance1 := add(balance1, xor(minusAmountIn, diff))
        }
        if (balance0 != 0) poolKey.token0.safeTransfer(msg.sender, balance0);
        if (balance1 != 0) poolKey.token1.safeTransfer(msg.sender, balance1);
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
    /// @param tickLower The lower tick of the position in which to add liquidity
    /// @param tickUpper The upper tick of the position in which to add liquidity
    /// @return amount0 The amount of token0 after swap
    /// @return amount1 The amount of token1 after swap
    function _optimalSwapWithRouter(
        SlipStreamPoolAddress.PoolKey memory poolKey,
        int24 tickLower,
        int24 tickUpper,
        bytes calldata swapData
    ) internal returns (uint256 amount0, uint256 amount1) {
        _routerSwapToOptimalRatio(poolKey, tickLower, tickUpper, swapData);
        amount0 = ERC20Callee.wrap(poolKey.token0).balanceOf(address(this));
        amount1 = ERC20Callee.wrap(poolKey.token1).balanceOf(address(this));
    }
}
