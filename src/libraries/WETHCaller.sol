// SPDX-License-Identifier: MIT
// User defined value types are introduced in Solidity v0.8.8.
// https://blog.soliditylang.org/2021/09/27/user-defined-value-types/
pragma solidity ^0.8.8;

import "solmate/src/tokens/WETH.sol";

type WETHCallee is address;
using WETHCaller for WETHCallee global;

/// @title WETH Caller
/// @author Aperture Finance
/// @notice Gas efficient library to call WETH assuming the contract exists.
library WETHCaller {
    /// @dev Equivalent to `WETH.deposit`
    /// @param weth WETH contract
    /// @param value Amount of ETH to deposit
    function deposit(WETHCallee weth, uint256 value) internal {
        bytes4 selector = WETH.deposit.selector;
        assembly ("memory-safe") {
            // Write the function selector into memory.
            mstore(0, selector)
            // We use 4 because of the length of our calldata.
            if iszero(call(gas(), weth, value, 0, 4, 0, 0)) {
                revert(0, 0)
            }
        }
    }

    /// @dev Equivalent to `WETH.withdraw`
    /// @param weth WETH contract
    /// @param amount Amount of WETH to withdraw
    function withdraw(WETHCallee weth, uint256 amount) internal {
        bytes4 selector = WETH.withdraw.selector;
        assembly ("memory-safe") {
            // Write the function selector into memory.
            mstore(0, selector)
            mstore(4, amount)
            // We use 36 because of the length of our calldata.
            if iszero(call(gas(), weth, 0, 0, 0x24, 0, 0)) {
                revert(0, 0)
            }
        }
    }
}
