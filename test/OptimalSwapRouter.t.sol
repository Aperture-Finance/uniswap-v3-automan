// SPDX-License-Identifier: MIT
// FOUNDRY_PROFILE=lite forge test --match-path=test/OptimalSwapRouter.t.sol -vvvvv
pragma solidity ^0.8.0;

import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "src/PCSV3Automan.sol";
import "src/UniV3Automan.sol";
import "src/SlipStreamAutoman.sol";
import {PCSV3OptimalSwapRouter} from "src/PCSV3OptimalSwapRouter.sol";
import {UniV3OptimalSwapRouter} from "src/UniV3OptimalSwapRouter.sol";
import {SlipStreamOptimalSwapRouter} from "src/SlipStreamOptimalSwapRouter.sol";
import "./uniswap/UniHandler.sol";

contract OptimalSwapRouterTest is UniHandler {
    using SafeTransferLib for address;

    address internal optimalSwapRouter;
    address internal v3SwapRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    function setUp() public virtual override {
        super.setUp();
        automan = new UniV3Automan(npm, address(this));
        optimalSwapRouter = address(new UniV3OptimalSwapRouter(npm, address(this)));
        setUpCommon();
    }

    function setUpCommon() internal {
        address[] memory routers = new address[](1);
        routers[0] = v3SwapRouter;
        bool[] memory statuses = new bool[](1);
        statuses[0] = true;
        automan.setAllowlistedRouters(routers, statuses);

        vm.label(address(automan), "UniV3Automan");
        vm.label(optimalSwapRouter, "OptimalSwapRouter");
        vm.label(v3SwapRouter, "v3Router");
        deal(address(this), 0);
    }

    function testRevert_OnReceiveETH() public {
        vm.expectRevert();
        payable(optimalSwapRouter).transfer(1);
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
            /* recipient= */ address(this),
            tickLower,
            tickUpper,
            amount0Desired,
            amount1Desired,
            encodeRouterData(address(automan), tickLower, tickUpper, zeroForOne, amtSwap)
        );
        vm.assume(liquidity != 0);
        assertLittleLeftover();
        assertZeroBalance(address(automan));

        // Skip comparison with same-pool swap for SlipStream on Base because the swap router is set to PCSV3 on Base which doesn't have good liquidity.
        // There is no deployed SwapRouter contract for UniV3 or SlipStream on Base.
        if (dex == DEX.SlipStream) return;

        vm.revertTo(snapshotId);
        (, uint128 _liquidity) = _mintOptimal(
            /* recipient= */ address(this),
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
        address recipient,
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
                recipient: recipient,
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );
        return
            abi.encodePacked(
                optimalSwapRouter,
                dex == DEX.SlipStream
                    ? abi.encodePacked(
                        token0,
                        token1,
                        tickSpacingSlipStream,
                        tickLower,
                        tickUpper,
                        zeroForOne,
                        v3SwapRouter,
                        v3SwapRouter,
                        data
                    )
                    : abi.encodePacked(
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

contract PCSV3OptimalSwapRouterTest is OptimalSwapRouterTest {
    function setUp() public override {
        v3SwapRouter = 0x1b81D678ffb9C0263b24A97847620C99d213eB14;
        dex = DEX.PCSV3;
        UniBase.setUp();
        IPCSV3NonfungiblePositionManager pcsnpm = IPCSV3NonfungiblePositionManager(address(npm));
        automan = new PCSV3Automan(pcsnpm, address(this));
        optimalSwapRouter = address(new PCSV3OptimalSwapRouter(pcsnpm, address(this)));
        setUpCommon();
    }
}

contract SlipStreamOptimalSwapRouterTest is OptimalSwapRouterTest {
    function setUp() public override {
        v3SwapRouter = 0x1b81D678ffb9C0263b24A97847620C99d213eB14;
        dex = DEX.SlipStream;
        UniBase.setUp();
        automan = new SlipStreamAutoman(npm, address(this));
        optimalSwapRouter = address(new SlipStreamOptimalSwapRouter(npm, address(this)));
        setUpCommon();
    }
}
