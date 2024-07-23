// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/interfaces/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@aperture_finance/uni-v3-lib/src/NPMCaller.sol";
import "@aperture_finance/uni-v3-lib/src/PoolAddress.sol";
import {TickBitmap, TickMath, UniBase, V3PoolCallee} from "./UniBase.sol";
import {OptimalSwap} from "src/libraries/OptimalSwap.sol";

contract OptimalSwapTest is UniBase {
    function setUp() public override {
        super.setUp();
        deal(address(this), 0);
    }

    function test_LiquidityDelta(bool zeroForOne) public view {
        (int24 tick, , , ) = TickBitmap.nextInitializedTickWithinOneWord(
            V3PoolCallee.wrap(pool),
            currentTick(),
            tickSpacing,
            zeroForOne,
            type(int16).min,
            0
        );
        uint128 liquidity = V3PoolCallee.wrap(pool).liquidity();
        int128 liquidityNet = V3PoolCallee.wrap(pool).liquidityNet(tick);
        console2.log("liquidity %d", liquidity);
        console2.log("liquidityNet %d", liquidityNet);
        if (zeroForOne) liquidityNet = -liquidityNet;
        if (liquidityNet < 0) liquidity -= uint128(-liquidityNet);
        else liquidity += uint128(liquidityNet);
        uint128 liquidityAsm = V3PoolCallee.wrap(pool).liquidity();
        liquidityNet = V3PoolCallee.wrap(pool).liquidityNet(tick);
        assembly {
            // If we're moving leftward, we interpret `liquidityNet` as the opposite sign.
            liquidityNet := add(zeroForOne, xor(sub(0, zeroForOne), liquidityNet))
            liquidityAsm := add(liquidityAsm, liquidityNet)
        }
        // ensure liquidityAsm < 2**127 and there are no dirty bits
        assertLt(uint256(liquidityAsm), 1 << 127, "liquidity overflow");
        assertEq(liquidity, liquidityAsm, "liquidity delta");
    }

    function prepTicks() internal view returns (int24 tickLower, int24 tickUpper) {
        int24 multiplier = 100;
        int24 tick = currentTick();
        console2.log("tickSpacing %d", int256(tickSpacing));
        console2.log("currentTick %d", int256(tick));
        tick = matchSpacing(tick);
        tickLower = tick - multiplier * tickSpacing;
        tickUpper = tick + multiplier * tickSpacing;
    }

    function test_OptimalSwap() public {
        (int24 tickLower, int24 tickUpper) = prepTicks();
        uint256 amt0User = 0 * token0Unit;
        uint256 amt1User = 100000 * token1Unit;
        deal(token0, address(this), amt0User);
        deal(token1, address(this), amt1User);
        uint256 gasBefore = gasleft();
        (uint256 amtSwap, uint256 amtOut, bool zeroForOne, ) = OptimalSwap.getOptimalSwap(
            V3PoolCallee.wrap(pool),
            tickLower,
            tickUpper,
            amt0User,
            amt1User
        );
        console2.log("Gas used %d", gasBefore - gasleft());
        console2.log("tickUpper %d", int256(tickUpper));
        console2.log("tickLower %d", int256(tickLower));
        console2.log("zeroForOne %s", zeroForOne);
        emit log_named_decimal_uint("amtSwap", amtSwap, ternary(zeroForOne, token0Decimals, token1Decimals));
        emit log_named_decimal_uint("amtOut", amtOut, ternary(zeroForOne, token1Decimals, token0Decimals));

        swapAndMint(address(this), amtSwap, zeroForOne, tickLower, tickUpper);
        console2.log("Tick after swap %d", int256(currentTick()));
        emit log_named_decimal_uint("Token0 left", IERC20(token0).balanceOf(address(this)), token0Decimals);
        emit log_named_decimal_uint("Token1 left", IERC20(token1).balanceOf(address(this)), token1Decimals);
    }

    function test_AlreadyOptimal() public view {
        (int24 tickLower, int24 tickUpper) = prepTicks();
        testFuzz_AlreadyOptimal(V3PoolCallee.wrap(pool).liquidity() / 10000, tickLower, tickUpper);
    }

    function testFuzz_AlreadyOptimal(uint128 liquidity, int24 tickLower, int24 tickUpper) public view {
        (tickLower, tickUpper) = prepTicks(tickLower, tickUpper);
        (uint256 amount0, uint256 amount1) = prepAmountsForLiquidity(liquidity, tickLower, tickUpper);
        OptimalSwap.getOptimalSwap(V3PoolCallee.wrap(pool), tickLower, tickUpper, amount0, amount1);
    }

    function test_OptimalSwapOutOfRange() public {
        int24 tick = currentTick();
        console2.log("tick %d", int256(tick));
        tick = matchSpacing(tick);
        int24 tickLower = tick - tickSpacing;
        int24 tickUpper = tick;
        console2.log("tickUpper %d", int256(tickUpper));
        console2.log("tickLower %d", int256(tickLower));
        uint256 amount0Desired = 10 * token0Unit;
        uint256 amount1Desired = 0 * token1Unit;
        (uint256 amtSwap, uint256 amtOut, bool zeroForOne, uint160 sqrtPriceX96) = OptimalSwap.getOptimalSwap(
            V3PoolCallee.wrap(pool),
            tickLower,
            tickUpper,
            amount0Desired,
            amount1Desired
        );
        console2.log("zeroForOne %s", zeroForOne);
        emit log_named_decimal_uint("amtSwap", amtSwap, ternary(zeroForOne, token0Decimals, token1Decimals));
        emit log_named_decimal_uint("amtOut", amtOut, ternary(zeroForOne, token1Decimals, token0Decimals));
        console2.log("tick after %d", int256(TickMath.getTickAtSqrtRatio(sqrtPriceX96)));
    }

    function testFuzz_OptimalSwapOutOfRange(
        uint256 amount0Desired,
        uint256 amount1Desired,
        bool zeroForOne,
        int24 tickLower,
        int24 tickUpper
    ) public {
        int24 tick = currentTick();
        tick = matchSpacing(tick);
        if (zeroForOne) {
            tickUpper = matchSpacing(int24(bound(tickUpper, TickMath.MIN_TICK, tick)));
            tickLower = matchSpacing(int24(bound(tickLower, TickMath.MIN_TICK, tick)));
        } else {
            tickUpper = matchSpacing(int24(bound(tickUpper, tick + tickSpacing, TickMath.MAX_TICK)));
            tickLower = matchSpacing(int24(bound(tickLower, tick + tickSpacing, TickMath.MAX_TICK)));
        }
        testFuzz_OptimalSwap(amount0Desired, amount1Desired, tickLower, tickUpper);
    }

    function testFuzz_OptimalSwap(
        uint256 amount0Desired,
        uint256 amount1Desired,
        int24 tickLower,
        int24 tickUpper
    ) public {
        uint256 amtSwap;
        bool zeroForOne;
        (tickLower, tickUpper, amount0Desired, amount1Desired, amtSwap, , zeroForOne) = prepOptimalSwap(
            tickLower,
            tickUpper,
            amount0Desired,
            amount1Desired
        );
        deal(token0, address(this), amount0Desired);
        deal(token1, address(this), amount1Desired);
        bool success = swapAndMint(address(this), amtSwap, zeroForOne, tickLower, tickUpper);
        if (success) assertLittleLeftover();
    }

    function test_OptimalSwapSparse() public {
        vm.createSelectFork("mainnet", 18619101);
        pool = 0xB17015D33C97A2cacA73be2a8669076a333FD43d;
        uint256 tokenId = 608611;
        int24 tickLower = -121440;
        int24 tickUpper = -121380;
        address owner = NPMCaller.ownerOf(npm, tokenId);
        Position memory position = NPMCaller.positions(npm, tokenId);
        token0 = position.token0;
        token1 = position.token1;
        token0Decimals = IERC20Metadata(token0).decimals();
        token0Unit = 10 ** token0Decimals;
        token1Decimals = IERC20Metadata(token1).decimals();
        token1Unit = 10 ** token1Decimals;
        vm.startPrank(owner);
        NPMCaller.decreaseLiquidity(
            npm,
            INPM.DecreaseLiquidityParams(tokenId, position.liquidity, 0, 0, block.timestamp)
        );
        (uint256 amount0, uint256 amount1) = NPMCaller.collect(npm, tokenId, address(this));
        (uint256 amountIn, , bool zeroForOne, uint160 sqrtPriceX96) = OptimalSwap.getOptimalSwap(
            V3PoolCallee.wrap(pool),
            tickLower,
            tickUpper,
            amount0,
            amount1
        );
        int24 tick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);
        console2.log("final tick", tick);
        vm.startPrank(address(this));
        bool success = swapAndMint(address(this), amountIn, zeroForOne, tickLower, tickUpper);
        assertTrue(success);
        assertEq(currentTick(), tick);
        assertLittleLeftover();
    }
}
