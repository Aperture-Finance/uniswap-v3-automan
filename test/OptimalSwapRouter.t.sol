// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "src/OptimalSwapRouter.sol";
import "src/UniV3Automan.sol";
import "./uniswap/UniHandler.sol";

contract OptimalSwapRouterTest is UniHandler {
    using SafeTransferLib for address;

    OptimalSwapRouter internal optimalSwapRouter;
    address internal constant v3SwapRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    function setUp() public override {
        super.setUp();

        automan = new UniV3Automan(npm, address(this));
        optimalSwapRouter = new OptimalSwapRouter(npm);

        address[] memory routers = new address[](1);
        routers[0] = address(optimalSwapRouter);
        bool[] memory statuses = new bool[](1);
        statuses[0] = true;
        automan.setSwapRouters(routers, statuses);

        vm.label(address(automan), "UniV3Automan");
        vm.label(address(optimalSwapRouter), "OptimalSwapRouter");
        vm.label(v3SwapRouter, "v3Router");
    }

    function testRevert_OnReceiveETH() public {
        vm.expectRevert();
        payable(address(optimalSwapRouter)).transfer(1);
    }

    function test_MintOptimal() public {
        uint256 amount0Desired = 0 * token0Unit;
        uint256 amount1Desired = 10000 * token1Unit;
        int24 tickLower;
        int24 tickUpper;
        uint256 amtSwap;
        bool zeroForOne;
        {
            int24 multiplier = 100;
            int24 tick = currentTick();
            (tickLower, tickUpper, amount0Desired, amount1Desired, amtSwap, , zeroForOne) = prepOptimalSwap(
                tick - multiplier * tickSpacing,
                tick + multiplier * tickSpacing,
                amount0Desired,
                amount1Desired
            );
        }
        uint256 snapshotId = vm.snapshot();

        // swap half of the optimal amount
        bytes memory swapData = encodeRouterData(tickLower, tickUpper, zeroForOne, amtSwap / 2);
        _mintOptimal(address(this), tickLower, tickUpper, amount0Desired, amount1Desired, swapData);
        assertLittleLeftover();
        emit log_named_decimal_uint("balance0Left", IERC20(token0).balanceOf(address(this)), token0Decimals);
        emit log_named_decimal_uint("balance1Left", IERC20(token1).balanceOf(address(this)), token1Decimals);
        assertZeroBalance(address(optimalSwapRouter));
    }

    function encodeRouterData(
        int24 tickLower,
        int24 tickUpper,
        bool zeroForOne,
        uint256 amountIn
    ) internal view returns (bytes memory) {
        (address tokenIn, address tokenOut) = switchIf(zeroForOne, token1, token0);
        bytes memory data = abi.encodeWithSelector(
            ISwapRouter.exactInputSingle.selector,
            ISwapRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: fee,
                recipient: address(optimalSwapRouter),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );
        return
            abi.encodePacked(
                optimalSwapRouter,
                abi.encodePacked(
                    token0,
                    token1,
                    fee,
                    tickLower,
                    tickUpper,
                    zeroForOne,
                    v3SwapRouter,
                    v3SwapRouter,
                    data
                )
            );
    }
}
