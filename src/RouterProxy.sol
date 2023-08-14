// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "solady/src/utils/SafeTransferLib.sol";
import {ERC20Callee} from "./libraries/ERC20Caller.sol";

/// @title Router Proxy
/// @author Aperture Finance
/// @dev This is a proxy contract that handles token approval/transfer and calls the router. The sigless `fallback` uses
/// manual decoding of arguments in assembly to save gas.
contract RouterProxy {
    using SafeTransferLib for address;

    fallback() external {
        /**
            `msg.data` is encoded as `abi.encodePacked(router, approvalTarget, tokenIn, tokenOut, amountIn, data)`.
            | Arg            | Offset   |
            |----------------|----------|
            | router         | [0, 20)  |
            | approvalTarget | [20, 40) |
            | tokenIn        | [40, 60) |
            | tokenOut       | [60, 80) |
            | amountIn       | [80, 112)|
            | data.offset    | [112, )  |
         */
        address router;
        address approvalTarget;
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        assembly {
            router := shr(96, calldataload(0))
            approvalTarget := shr(96, calldataload(20))
            tokenIn := shr(96, calldataload(40))
            tokenOut := shr(96, calldataload(60))
            amountIn := calldataload(80)
        }
        tokenIn.safeTransferFrom(msg.sender, address(this), amountIn);
        tokenIn.safeApprove(approvalTarget, type(uint256).max);
        assembly ("memory-safe") {
            let fmp := mload(0x40)
            let dataLength := sub(calldatasize(), 112)
            calldatacopy(fmp, 112, dataLength)
            // Ignore the return data unless an error occurs
            if iszero(call(gas(), router, 0, fmp, dataLength, 0, 0)) {
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
