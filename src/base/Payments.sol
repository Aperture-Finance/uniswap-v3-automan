// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.18;

import "solady/src/utils/SafeTransferLib.sol";
import {ERC20Callee} from "../libraries/ERC20Caller.sol";
import {WETHCallee} from "../libraries/WETHCaller.sol";
import {Immutables} from "./Immutables.sol";

abstract contract Payments is Immutables {
    using SafeTransferLib for address;

    error NotWETH9();
    error MismatchETH();

    receive() external payable {
        if (msg.sender != WETH9) revert NotWETH9();
    }

    /// @notice Pays an amount of ETH or ERC20 to a recipient
    /// @param token The token to pay
    /// @param payer The entity that must pay
    /// @param recipient The address that will receive the payment
    /// @param value The amount to pay
    function pay(address token, address payer, address recipient, uint256 value) internal {
        // Receive native ETH
        if (token == WETH9 && msg.value != 0) {
            if (value != msg.value) revert MismatchETH();
            // Wrap it
            WETHCallee.wrap(WETH9).deposit(value);
            // Already received native ETH so return
            if (recipient == address(this)) return;
        }
        if (payer == address(this)) {
            // Send token to recipient
            token.safeTransfer(recipient, value);
        } else {
            // pull payment
            token.safeTransferFrom(payer, recipient, value);
        }
    }

    /// @dev Refunds an amount of ETH or ERC20 to a recipient, only called with balance the contract already has
    /// @param token The token to pay
    /// @param recipient The address that will receive the payment
    /// @param value The amount to pay
    function refund(address token, address recipient, uint256 value) internal {
        if (token == WETH9) {
            // Unwrap WETH
            WETHCallee.wrap(WETH9).withdraw(value);
            // Send native ETH to recipient
            recipient.safeTransferETH(value);
        } else {
            token.safeTransfer(recipient, value);
        }
    }

    /// @dev Pulls tokens from caller and approves NonfungiblePositionManager to spend
    function pullAndApprove(address token0, address token1, uint256 amount0Desired, uint256 amount1Desired) internal {
        if (amount0Desired != 0) {
            pay(token0, msg.sender, address(this), amount0Desired);
            token0.safeApprove(address(npm), amount0Desired);
        }
        if (amount1Desired != 0) {
            pay(token1, msg.sender, address(this), amount1Desired);
            token1.safeApprove(address(npm), amount1Desired);
        }
    }
}
