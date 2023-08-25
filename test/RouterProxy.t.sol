// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "src/RouterProxy.sol";
import "./uniswap/UniBase.sol";

contract RouterProxyTest is UniBase {
    using SafeTransferLib for address;

    RouterProxy internal routerProxy;
    address internal constant v3SwapRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    function setUp() public override {
        super.setUp();
        routerProxy = new RouterProxy();
        vm.label(address(routerProxy), "RouterProxy");
        vm.label(v3SwapRouter, "v3Router");
    }

    function testRevert_OnReceiveETH() public {
        vm.expectRevert();
        payable(address(routerProxy)).transfer(1);
    }

    function test_Swap() public {
        testFuzz_Swap(true, token0Unit);
    }

    function testFuzz_Swap(bool zeroForOne, uint256 amountSpecified) public {
        amountSpecified = prepSwap(zeroForOne, amountSpecified);
        (address tokenIn, address tokenOut) = switchIf(zeroForOne, token1, token0);
        uint256 balanceBefore = IERC20(tokenOut).balanceOf(address(pool));
        tokenIn.safeApprove(address(routerProxy), amountSpecified);
        bytes memory data = abi.encodeWithSelector(
            ISwapRouter.exactInputSingle.selector,
            ISwapRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: fee,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountSpecified,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );
        (bool success, ) = address(routerProxy).call(
            abi.encodePacked(address(v3SwapRouter), address(v3SwapRouter), tokenIn, tokenOut, amountSpecified, data)
        );
        assertTrue(success, "swap failed");
        assertSwapSuccess(zeroForOne, balanceBefore - IERC20(tokenOut).balanceOf(address(pool)));
        assertZeroBalance(address(routerProxy));
    }
}
