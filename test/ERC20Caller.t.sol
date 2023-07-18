// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/libraries/ERC20Caller.sol";

/// @dev Test the ERC20Caller library.
contract ERC20CallerTest is Test {
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    function setUp() public {
        vm.createSelectFork("mainnet", 17000000);
    }

    function test_TotalSupply() public {
        address token = USDC;
        assertEq(IERC20(token).totalSupply(), ERC20Callee.wrap(token).totalSupply(), "totalSupply mismatch");
    }

    function testFuzz_TotalSupply(address token) public {
        (bool success, bytes memory data) = token.staticcall(abi.encodeWithSelector(IERC20.totalSupply.selector));
        if (success && data.length == 32) {
            assertEq(abi.decode(data, (uint256)), ERC20Callee.wrap(token).totalSupply(), "totalSupply mismatch");
        }
    }

    function test_BalanceOf(address account) public {
        address token = USDC;
        assertEq(IERC20(token).balanceOf(account), ERC20Callee.wrap(token).balanceOf(account), "balanceOf mismatch");
    }

    function testFuzz_BalanceOf(address token, address account) public {
        (bool success, bytes memory data) = token.staticcall(
            abi.encodeWithSelector(IERC20.balanceOf.selector, account)
        );
        if (success && data.length == 32) {
            assertEq(abi.decode(data, (uint256)), ERC20Callee.wrap(token).balanceOf(account), "balanceOf mismatch");
        }
    }

    function test_Allowance(address owner, address spender) public {
        address token = USDC;
        assertEq(
            IERC20(token).allowance(owner, spender),
            ERC20Callee.wrap(token).allowance(owner, spender),
            "allowance mismatch"
        );
    }

    function testFuzz_Allowance(address token, address owner, address spender) public {
        (bool success, bytes memory data) = token.staticcall(
            abi.encodeWithSelector(IERC20.allowance.selector, owner, spender)
        );
        if (success && data.length == 32) {
            assertEq(
                abi.decode(data, (uint256)),
                ERC20Callee.wrap(token).allowance(owner, spender),
                "allowance mismatch"
            );
        }
    }

    function test_Decimals() public {
        address token = USDC;
        assertEq(IERC20Metadata(token).decimals(), ERC20Callee.wrap(token).decimals(), "decimals mismatch");
    }
}
