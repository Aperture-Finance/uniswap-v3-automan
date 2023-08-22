// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "src/lens/EphemeralGetPopulatedTicksInRange.sol";
import "src/lens/EphemeralGetPopulatedTicksInWord.sol";
import "./uniswap/UniBase.sol";

contract TickLensTest is UniBase {
    function verifyTicks(TickLens.PopulatedTick[] memory populatedTicks) internal {
        for (uint256 i; i < populatedTicks.length; ++i) {
            TickLens.PopulatedTick memory populatedTick = populatedTicks[i];
            (
                uint128 liquidityGross,
                int128 liquidityNet,
                uint256 feeGrowthOutside0X128,
                uint256 feeGrowthOutside1X128,
                ,
                ,
                ,

            ) = IUniswapV3Pool(pool).ticks(populatedTick.tick);
            assertEq(liquidityGross, populatedTick.liquidityGross, "liquidityGross");
            assertEq(liquidityNet, populatedTick.liquidityNet, "liquidityNet");
            assertEq(feeGrowthOutside0X128, populatedTick.feeGrowthOutside0X128, "feeGrowthOutside0X128");
            assertEq(feeGrowthOutside1X128, populatedTick.feeGrowthOutside1X128, "feeGrowthOutside1X128");
        }
    }

    function test_GetPopulatedTicksInWord() public {
        int24 compressed = TickBitmap.compress(currentTick(), tickSpacing);
        EphemeralGetPopulatedTicksInWord lens = new EphemeralGetPopulatedTicksInWord(
            V3PoolCallee.wrap(pool),
            int16(compressed >> 8)
        );
        TickLens.PopulatedTick[] memory populatedTicks = abi.decode(address(lens).code, (TickLens.PopulatedTick[]));
        console2.log("length", populatedTicks.length);
        verifyTicks(populatedTicks);
    }

    function testFuzz_GetPopulatedTicksInWord(int16 tickBitmapIndex) public {
        int24 compressed = TickBitmap.compress(currentTick(), tickSpacing);
        int16 wordPos = int16(compressed >> 8);
        tickBitmapIndex = int16(bound(tickBitmapIndex, wordPos - 128, wordPos + 128));
        EphemeralGetPopulatedTicksInWord lens = new EphemeralGetPopulatedTicksInWord(
            V3PoolCallee.wrap(pool),
            tickBitmapIndex
        );
        TickLens.PopulatedTick[] memory populatedTicks = abi.decode(address(lens).code, (TickLens.PopulatedTick[]));
        verifyTicks(populatedTicks);
    }

    function test_GetPopulatedTicksInRange() public {
        int24 tick = currentTick();
        try
            new EphemeralGetPopulatedTicksInRange(
                V3PoolCallee.wrap(pool),
                tick - 128 * tickSpacing,
                tick + 128 * tickSpacing
            )
        {} catch (bytes memory returnData) {
            TickLens.PopulatedTick[] memory populatedTicks = abi.decode(returnData, (TickLens.PopulatedTick[]));
            console2.log("length", populatedTicks.length);
            verifyTicks(populatedTicks);
        }
    }
}
