// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "src/UniV3OptimalSwapRouter.sol";
import "src/UniV3Automan.sol";
import "./uniswap/UniHandler.sol";

contract OptimalSwapRouterTest is UniHandler {
    using SafeTransferLib for address;

    UniV3OptimalSwapRouter internal optimalSwapRouter;
    address internal constant v3SwapRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    function setUp() public override {
        super.setUp();

        automan = new UniV3Automan(npm, address(this));
        optimalSwapRouter = new UniV3OptimalSwapRouter(npm);

        address[] memory routers = new address[](1);
        routers[0] = address(optimalSwapRouter);
        bool[] memory statuses = new bool[](1);
        statuses[0] = true;
        automan.setSwapRouters(routers, statuses);

        vm.label(address(automan), "UniV3Automan");
        vm.label(address(optimalSwapRouter), "OptimalSwapRouter");
        vm.label(v3SwapRouter, "v3Router");
        deal(address(this), 0);
    }

    function testRevert_OnReceiveETH() public {
        vm.expectRevert();
        payable(address(optimalSwapRouter)).transfer(1);
    }

    function test_MintOptimal() public {
        int24 multiplier = 100;
        int24 tick = currentTick();
        testFuzz_MintOptimal(
            0 * token0Unit,
            10000 * token1Unit,
            tick - multiplier * tickSpacing,
            tick + multiplier * tickSpacing,
            1000 * token1Unit
        );
    }

    function testFuzz_MintOptimal(
        uint256 amount0Desired,
        uint256 amount1Desired,
        int24 tickLower,
        int24 tickUpper,
        uint256 amtSwap
    ) public {
        bool zeroForOne;
        {
            uint256 _amtSwap;
            (tickLower, tickUpper, amount0Desired, amount1Desired, _amtSwap, , zeroForOne) = prepOptimalSwap(
                tickLower,
                tickUpper,
                amount0Desired,
                amount1Desired
            );
            amtSwap = bound(amtSwap, 0, _amtSwap);
        }
        vm.assume(amtSwap != 0);
        uint256 snapshotId = vm.snapshot();

        (, uint128 liquidity) = _mintOptimal(
            address(this),
            tickLower,
            tickUpper,
            amount0Desired,
            amount1Desired,
            encodeRouterData(tickLower, tickUpper, zeroForOne, amtSwap)
        );
        vm.assume(liquidity != 0);
        assertLittleLeftover();
        assertZeroBalance(address(optimalSwapRouter));

        vm.revertTo(snapshotId);
        (, uint128 _liquidity) = _mintOptimal(
            address(this),
            tickLower,
            tickUpper,
            amount0Desired,
            amount1Desired,
            new bytes(0)
        );
        uint256 maxDelta = liquidity / 1e3;
        assertApproxEqAbs(liquidity, _liquidity, ternary(maxDelta > 1e6, maxDelta, 1e6));
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
