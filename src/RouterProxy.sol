// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "solady/src/utils/SafeTransferLib.sol";
import {ERC20Callee} from "./libraries/ERC20Caller.sol";

/// @dev This is a proxy contract that handles token approval/transfer and calls the router.
contract RouterProxy {
    using SafeTransferLib for address;

    fallback() external {
        // `msg.data` is encoded as `abi.encodePacked(router, approvalTarget, tokenIn, tokenOut, amountIn, data)`.
        address router;
        address approvalTarget;
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        bytes calldata data;
        assembly ("memory-safe") {
            router := shr(96, calldataload(0))
            approvalTarget := shr(96, calldataload(20))
            tokenIn := shr(96, calldataload(40))
            tokenOut := shr(96, calldataload(60))
            amountIn := calldataload(80)
            data.length := sub(calldatasize(), 112)
            data.offset := 112
        }
        swapExactTokensForTokens(router, approvalTarget, tokenIn, tokenOut, amountIn, data);
    }

    function swapExactTokensForTokens(
        address router,
        address approvalTarget,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        bytes calldata data
    ) internal {
        tokenIn.safeTransferFrom(msg.sender, address(this), amountIn);
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
        tokenOut.safeTransfer(msg.sender, ERC20Callee.wrap(tokenOut).balanceOf(address(this)));
        uint256 tokenInBalance = ERC20Callee.wrap(tokenIn).balanceOf(address(this));
        if (tokenInBalance != 0) {
            tokenIn.safeTransfer(msg.sender, tokenInBalance);
        }
    }
}
