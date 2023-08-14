// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../src/libraries/ERC20Caller.sol";

/// @dev Test the ERC20Caller library.
contract ERC20CallerTest is Test {
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    ERC20 internal testToken;

    function setUp() public {
        vm.createSelectFork("mainnet", 17000000);
        testToken = new ERC20("TestToken", "TEST");
    }

    function test_TotalSupply() public {
        address token = USDC;
        assertEq(IERC20(token).totalSupply(), ERC20Callee.wrap(token).totalSupply(), "totalSupply mismatch");
    }

    function testFuzz_TotalSupply(uint256 amount) public {
        address token = address(testToken);
        deal(token, address(this), amount, true);
        assertEq(IERC20(token).totalSupply(), ERC20Callee.wrap(token).totalSupply(), "totalSupply mismatch");
    }

    function test_BalanceOf() public {
        address token = USDC;
        deal(token, address(this), 1000);
        assertEq(
            IERC20(token).balanceOf(address(this)),
            ERC20Callee.wrap(token).balanceOf(address(this)),
            "balanceOf mismatch"
        );
    }

    function testFuzz_BalanceOf(uint256 amount) public {
        address token = address(testToken);
        deal(token, address(this), amount);
        assertEq(
            IERC20(token).balanceOf(address(this)),
            ERC20Callee.wrap(token).balanceOf(address(this)),
            "balanceOf mismatch"
        );
    }

    function test_Allowance() public {
        address token = USDC;
        address spender = address(1);
        IERC20(token).approve(spender, type(uint256).max);
        assertEq(
            IERC20(token).allowance(address(this), spender),
            ERC20Callee.wrap(token).allowance(address(this), spender),
            "allowance mismatch"
        );
    }

    function testFuzz_Allowance(address spender, uint256 amount) public {
        vm.assume(spender != address(0) && spender != address(this));
        address token = address(testToken);
        IERC20(token).approve(spender, amount);
        assertEq(
            IERC20(token).allowance(address(this), spender),
            ERC20Callee.wrap(token).allowance(address(this), spender),
            "allowance mismatch"
        );
    }

    function test_Decimals() public {
        address token = USDC;
        assertEq(IERC20Metadata(token).decimals(), ERC20Callee.wrap(token).decimals(), "decimals mismatch");
    }
}
