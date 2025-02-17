// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "solady/src/utils/SafeTransferLib.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Callee} from "../libraries/ERC20Caller.sol";
import {ISwapRouterCommon} from "../interfaces/ISwapRouter.sol";
import {PoolKey} from "@aperture_finance/uni-v3-lib/src/PoolKey.sol";
import {PoolAddress} from "@aperture_finance/uni-v3-lib/src/PoolAddress.sol";
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
abstract contract SwapRouter is Ownable, Payments, ISwapRouterCommon {
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

    /// @notice The list of allowlisted routers
    mapping(address => bool) public isAllowListedRouter;

    /// @notice Set allowlisted routers
    /// @dev If `NonfungiblePositionManager` is an allowlisted router, this contract may approve arbitrary address to
    /// spend NFTs it has been approved of.
    /// @dev If an ERC20 token is allowlisted as a router, `transferFrom` may be called to drain tokens approved
    /// to this contract during `mintOptimal` or `increaseLiquidityOptimal`.
    /// @dev If a malicious router is allowlisted and called without slippage control, the caller may lose tokens in an
    /// external swap. The router can't, however, drain ERC20 or ERC721 tokens which have been approved by other users
    /// to this contract. Because this contract doesn't contain `transferFrom` with random `from` address like that in
    /// SushiSwap's [`RouteProcessor2`](https://rekt.news/sushi-yoink-rekt/).
    function setAllowlistedRouters(address[] calldata routers, bool[] calldata statuses) external payable onlyOwner {
        uint256 len = routers.length;
        require(len == statuses.length);
        unchecked {
            for (uint256 i; i < len; ++i) {
                address router = routers[i];
                if (statuses[i]) {
                    // revert if `router` is `NonfungiblePositionManager`
                    if (router == address(npm)) revert InvalidRouter();
                    // revert if `router` is an ERC20 or not a contract
                    //slither-disable-next-line reentrancy-no-eth
                    (bool success, ) = router.call(abi.encodeCall(IERC20.approve, (address(npm), 0)));
                    if (success) revert InvalidRouter();
                    isAllowListedRouter[router] = true;
                } else {
                    delete isAllowListedRouter[router];
                }
            }
        }
        emit SetAllowlistedRouters(routers, statuses);
    }

    /// @notice Deterministically computes the pool address given the pool key
    /// @param poolKey The pool key
    /// @return pool The contract address of the pool
    function computeAddressSorted(PoolKey memory poolKey) internal view virtual returns (address pool);

    /// @dev Make a direct `exactIn` pool swap
    /// @param poolKey The pool key containing the token addresses and fee tier
    /// @param pool The address of the pool
    /// @param amountIn The amount of token to be swapped
    /// @param zeroForOne The direction of the swap, true for token0 to token1, false for token1 to token0
    /// @return amountOut The amount of token received after swap
    function _poolSwap(
        PoolKey memory poolKey,
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

    /// @dev Make an swap through an allowlisted external router from token in to token out
    /// @param tokenIn The address of the token to be swapped
    /// @param swapData The address of the external router and call data, not abi-encoded
    function _routerSwapFromTokenInToTokenOutHelper(address tokenIn, bytes calldata swapData) internal {
        address approvalTarget;
        address router;
        bytes calldata data;
        assembly {
            /*
            `swapData` is encoded as `abi.encodePacked(token0, token1, fee, tickLower, tickUpper, zeroForOne, approvalTarget, router, data)`
            | Arg               | Offset     |
            |-------------------|------------|
            | optimalSwapRouter | [  0,  20) |
            | token0            | [ 20,  40) |
            | token1            | [ 40,  60) |
            | feeOrTickSpacing  | [ 60,  63) |
            | tickLower         | [ 63,  66) |
            | tickUpper         | [ 66,  69) |
            | zeroForOne        | [ 69,  70) |
            | approvalTarget    | [ 70,  90) |
            | router            | [ 90, 110) |
            | data              | [110,    ) |

            Word sizes are 32 bytes, and addresses are 20 bytes, so need to shift right 12 bytes = 96 bits
            Although shr(96, calldataload(add(swapData.offset, 20))) is similiar to calldataload(add(swapData.offset, 8))
            because 20 bytes offset then shifting right 96 bits is the same as 20-96/8 = 8 bytes offset,
            doing method with shift is safer to clear the 1st 12 bytes of an address.
            Therefore,
                optimalSwapRouter := shr(96, calldataload(add(swapData.offset, 0)))
                token0 := shr(96, calldataload(add(swapData.offset, 20)))
                token1 := shr(96, calldataload(add(swapData.offset, 40)))
                feeOrTickSpacing := shr(232, calldataload(add(swapData.offset, 60)))
                tickLower := sar(232, calldataload(add(swapData.offset, 63)))
                tickUpper := sar(232, calldataload(add(swapData.offset, 66)))
                zeroForOne := shr(248, calldataload(add(swapData.offset, 69)))
                approvalTarget := shr(96, calldataload(add(swapData.offset, 70)))
                router := shr(96, calldataload(add(swapData.offset, 90)))
                data.length := sub(swapData.length, 110)
                data.offset := add(swapData.offset, 110)
            */
            approvalTarget := shr(96, calldataload(add(swapData.offset, 70)))
            router := shr(96, calldataload(add(swapData.offset, 90)))
            data.length := sub(swapData.length, 110)
            data.offset := add(swapData.offset, 110)
        }
        if (!isAllowListedRouter[router]) revert NotAllowlistedRouter();
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

    /// @dev Make an swap through an allowlisted external router from token in to token out
    /// @param poolKey The pool key containing the token addresses and fee tier
    /// @param zeroForOne The direction of the swap, true for token0 to token1, false for token1 to token0
    /// @param swapData The address of the external router and call data, not abi-encoded
    /// @return amountOut The amount of token received after swap
    function _routerSwapFromTokenInToTokenOut(
        PoolKey memory poolKey,
        bool zeroForOne,
        bytes calldata swapData
    ) internal returns (uint256 amountOut) {
        (address tokenIn, address tokenOut) = zeroForOne.switchIf(poolKey.token1, poolKey.token0);
        uint256 balanceBefore = ERC20Callee.wrap(tokenOut).balanceOf(address(this));
        _routerSwapFromTokenInToTokenOutHelper(tokenIn, swapData);
        uint256 balanceAfter = ERC20Callee.wrap(tokenOut).balanceOf(address(this));
        unchecked {
            amountOut = balanceAfter - balanceBefore;
        }
    }

    /// @dev Make an swap through an allowlisted external router to optimal ratio.
    /// @param poolKey The pool key containing the token addresses and fee tier
    /// @param swapData The address of the external router and call data, not abi-encoded
    function _routerSwapToOptimalRatioHelper(PoolKey memory poolKey, bytes calldata swapData) internal {
        // swap tokens to the optimal ratio to add liquidity in the same pool
        unchecked {
            uint256 balance0 = ERC20Callee.wrap(poolKey.token0).balanceOf(address(this));
            uint256 balance1 = ERC20Callee.wrap(poolKey.token1).balanceOf(address(this));
            address pool = computeAddressSorted(poolKey);
            int24 tickLower;
            int24 tickUpper;
            uint256 amountIn;
            bool zeroForOne;
            assembly {
                // Refer to around line 125 for explanation.
                tickLower := sar(232, calldataload(add(swapData.offset, 63)))
                tickUpper := sar(232, calldataload(add(swapData.offset, 66)))
            }
            (amountIn, , zeroForOne, ) = OptimalSwap.getOptimalSwap(
                V3PoolCallee.wrap(computeAddressSorted(poolKey)),
                tickLower,
                tickUpper,
                balance0,
                balance1
            );
            _poolSwap(poolKey, pool, amountIn, zeroForOne);
        }
    }

    /// @dev Make a swap through an allowlisted external router to optimal ratio.
    /// @param poolKey The pool key containing the token addresses and fee tier
    /// @param zeroForOne The direction of the swap, true for token0 to token1, false for token1 to token0
    /// @param swapData The address of the external router and call data, not abi-encoded
    /// @return amountOut The amount of token received after swap
    function _routerSwapToOptimalRatio(
        PoolKey memory poolKey,
        bool zeroForOne,
        bytes calldata swapData
    ) internal returns (uint256 amountOut) {
        (address tokenIn, address tokenOut) = zeroForOne.switchIf(poolKey.token1, poolKey.token0);
        uint256 balanceBefore = ERC20Callee.wrap(tokenOut).balanceOf(address(this));
        _routerSwapFromTokenInToTokenOutHelper(tokenIn, swapData);
        _routerSwapToOptimalRatioHelper(poolKey, swapData);
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
        PoolKey memory poolKey,
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
    /// @param amount0Desired The desired amount of token0 to be spent
    /// @param amount1Desired The desired amount of token1 to be spent
    /// @param swapData The call data for the external router, not abi-encoded
    /// @return amount0 The amount of token0 after swap
    /// @return amount1 The amount of token1 after swap
    function _optimalSwapWithRouter(
        PoolKey memory poolKey,
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
        _routerSwapToOptimalRatio(poolKey, zeroForOne, swapData);
        amount0 = ERC20Callee.wrap(poolKey.token0).balanceOf(address(this));
        amount1 = ERC20Callee.wrap(poolKey.token1).balanceOf(address(this));
    }
}

abstract contract UniV3SwapRouter is SwapRouter, UniswapV3Callback {
    function computeAddressSorted(PoolKey memory poolKey) internal view override returns (address pool) {
        pool = PoolAddress.computeAddressSorted(factory, poolKey);
    }
}

abstract contract PCSV3SwapRouter is SwapRouter, PancakeV3Callback {
    function computeAddressSorted(PoolKey memory poolKey) internal view override returns (address pool) {
        pool = PoolAddressPancakeSwapV3.computeAddressSorted(deployer, poolKey);
    }
}
