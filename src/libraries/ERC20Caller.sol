// SPDX-License-Identifier: MIT
// User defined value types are introduced in Solidity v0.8.8.
// https://blog.soliditylang.org/2021/09/27/user-defined-value-types/
pragma solidity ^0.8.8;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

type ERC20Callee is address;
using ERC20Caller for ERC20Callee global;

/// @title ERC20 Caller
/// @author Aperture Finance
/// @notice Gas efficient library to call ERC20 token assuming the token exists
library ERC20Caller {
    /// @dev Equivalent to `IERC20.totalSupply`
    /// @param token ERC20 token
    function totalSupply(ERC20Callee token) internal view returns (uint256 amount) {
        bytes4 selector = IERC20.totalSupply.selector;
        assembly ("memory-safe") {
            // Write the function selector into memory.
            mstore(0, selector)
            // We use 4 because of the length of our calldata.
            // We use 0 and 32 to copy up to 32 bytes of return data into the scratch space.
            // `totalSupply` should never revert according to the ERC20 standard.
            if iszero(staticcall(gas(), token, 0, 4, 0, 0x20)) {
                revert(0, 0)
            }
            amount := mload(0)
        }
    }

    /// @dev Equivalent to `IERC20.balanceOf`
    /// @param token ERC20 token
    /// @param account Account to check balance of
    function balanceOf(ERC20Callee token, address account) internal view returns (uint256 amount) {
        bytes4 selector = IERC20.balanceOf.selector;
        assembly ("memory-safe") {
            // Write the abi-encoded calldata into memory.
            mstore(0, selector)
            mstore(4, account)
            // We use 36 because of the length of our calldata.
            // We use 0 and 32 to copy up to 32 bytes of return data into the scratch space.
            // `balanceOf` should never revert according to the ERC20 standard.
            if iszero(staticcall(gas(), token, 0, 0x24, 0, 0x20)) {
                revert(0, 0)
            }
            amount := mload(0)
        }
    }

    /// @dev Equivalent to `IERC20.allowance`
    /// @param token ERC20 token
    /// @param owner Owner of the tokens
    /// @param spender Spender of the tokens
    function allowance(ERC20Callee token, address owner, address spender) internal view returns (uint256 amount) {
        bytes4 selector = IERC20.allowance.selector;
        assembly ("memory-safe") {
            // Write the abi-encoded calldata into memory.
            mstore(0, selector)
            mstore(4, owner)
            mstore(0x24, spender)
            // We use 68 because of the length of our calldata.
            // We use 0 and 32 to copy up to 32 bytes of return data into the scratch space.
            // `allowance` should never revert according to the ERC20 standard.
            if iszero(staticcall(gas(), token, 0, 0x44, 0, 0x20)) {
                revert(0, 0)
            }
            amount := mload(0)
            // Clear first 4 bytes of the free memory pointer.
            mstore(0x24, 0)
        }
    }

    /// @dev Equivalent to `IERC20Metadata.decimals` with 18 as fallback
    /// @param token ERC20 token
    function decimals(ERC20Callee token) internal view returns (uint8 d) {
        bytes4 selector = IERC20Metadata.decimals.selector;
        assembly ("memory-safe") {
            // Store 18 to memory to use as fallback.
            mstore(0, 18)
            // Write the function selector into memory.
            mstore(0x20, selector)
            let success := staticcall(gas(), token, 0x20, 4, 0x20, 0x20)
            // Read from 0x20 if the call was successful, otherwise read from 0.
            d := mload(shl(5, success))
        }
    }
}
