// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {ICommonNonfungiblePositionManager} from "@aperture_finance/uni-v3-lib/src/interfaces/ICommonNonfungiblePositionManager.sol";
import "./base/SlipStreamSwapRouter.sol";

contract SlipStreamOptimalSwapRouter is SlipStreamSwapRouter {
    using SafeTransferLib for address;
    using TernaryLib for bool;

    constructor(ICommonNonfungiblePositionManager npm) payable UniV3Immutables(npm) {}

    fallback() external {
        /**
            `msg.data` is encoded as `abi.encodePacked(token0, token1, tickSpacing, tickLower, tickUpper, zeroForOne,
            approvalTarget, router, data)`
            | Arg            | Offset   |
            |----------------|----------|
            | token0         | [0, 20)  |
            | token1         | [20, 40) |
            | tickSpacing    | [40, 43) |
            | tickLower      | [43, 46) |
            | tickUpper      | [46, 49) |
            | zeroForOne     | [49, 50) |
            | approvalTarget | [50, 70) |
            | router         | [70, 90) |
            | data.offset    | [90, )   |
         */
        address token0;
        address token1;
        bool zeroForOne;
        assembly {
            token0 := shr(96, calldataload(0))
            token1 := shr(96, calldataload(20))
            zeroForOne := shr(248, calldataload(49))
        }

        // swap `tokenIn` for `tokenOut` using the router
        {
            address approvalTarget;
            address router;
            bytes calldata data;
            assembly {
                approvalTarget := shr(96, calldataload(50))
                router := shr(96, calldataload(70))
                data.length := sub(calldatasize(), 90)
                data.offset := 90
            }
            address tokenIn = zeroForOne.ternary(token0, token1);
            // pull the balance of `tokenIn` from the sender
            tokenIn.safeTransferFrom(msg.sender, address(this), ERC20Callee.wrap(tokenIn).balanceOf(msg.sender));
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

        // swap tokens to the optimal ratio to add liquidity in the same pool
        unchecked {
            uint256 balance0 = ERC20Callee.wrap(token0).balanceOf(address(this));
            uint256 balance1 = ERC20Callee.wrap(token1).balanceOf(address(this));
            uint256 amountIn;
            uint256 amountOut;
            {
                int24 tickSpacing;
                int24 tickLower;
                int24 tickUpper;
                assembly {
                    tickSpacing := sar(232, calldataload(40))
                    tickLower := sar(232, calldataload(43))
                    tickUpper := sar(232, calldataload(46))
                }
                SlipStreamPoolAddress.PoolKey memory poolKey = SlipStreamPoolAddress.PoolKey(
                    token0,
                    token1,
                    tickSpacing
                );
                address pool = computeAddressSorted(poolKey);
                uint256 amount0Desired;
                uint256 amount1Desired;
                // take into account the balance not pulled from the sender
                if (zeroForOne) {
                    amount0Desired = balance0;
                    amount1Desired = balance1 + ERC20Callee.wrap(token1).balanceOf(msg.sender);
                } else {
                    amount0Desired = balance0 + ERC20Callee.wrap(token0).balanceOf(msg.sender);
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
            if (balance0 != 0) token0.safeTransfer(msg.sender, balance0);
            if (balance1 != 0) token1.safeTransfer(msg.sender, balance1);
        }
    }
}
