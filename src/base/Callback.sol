// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";
import "@pancakeswap/v3-core/contracts/interfaces/callback/IPancakeV3SwapCallback.sol";
import {CallbackValidation} from "@aperture_finance/uni-v3-lib/src/CallbackValidation.sol";
import {CallbackValidationPancakeSwapV3} from "@aperture_finance/uni-v3-lib/src/CallbackValidationPancakeSwapV3.sol";
import "./Immutables.sol";
import "./Payments.sol";

abstract contract UniswapV3Callback is Payments, UniV3Immutables, IUniswapV3SwapCallback {
    /// @inheritdoc IUniswapV3SwapCallback
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external {
        // Only accept callbacks from an official Uniswap V3 pool
        address pool = CallbackValidation.verifyCallbackCalldata(factory, data);
        if (amount0Delta > 0) {
            address token0;
            assembly {
                token0 := calldataload(data.offset)
            }
            pay(token0, address(this), pool, uint256(amount0Delta));
        } else {
            address token1;
            assembly {
                token1 := calldataload(add(data.offset, 0x20))
            }
            pay(token1, address(this), pool, uint256(amount1Delta));
        }
    }
}

abstract contract PancakeV3Callback is Payments, PCSV3Immutables, IPancakeV3SwapCallback {
    /// @inheritdoc IPancakeV3SwapCallback
    function pancakeV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external {
        // Only accept callbacks from an official PCS V3 pool
        address pool = CallbackValidationPancakeSwapV3.verifyCallbackCalldata(deployer, data);
        if (amount0Delta > 0) {
            address token0;
            assembly {
                token0 := calldataload(data.offset)
            }
            pay(token0, address(this), pool, uint256(amount0Delta));
        } else {
            address token1;
            assembly {
                token1 := calldataload(add(data.offset, 0x20))
            }
            pay(token1, address(this), pool, uint256(amount1Delta));
        }
    }
}
