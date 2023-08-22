// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IUniswapV3Pool, PoolCaller, V3PoolCallee} from "@aperture_finance/uni-v3-lib/src/PoolCaller.sol";
import {TickBitmap} from "@aperture_finance/uni-v3-lib/src/TickBitmap.sol";

/// @title Tick Lens contract
/// @author Aperture Finance
/// @author Modified from Uniswap (https://github.com/uniswap/v3-periphery/blob/main/contracts/lens/TickLens.sol)
/// @notice Provides functions for fetching chunks of tick data for a pool
/// @dev This avoids the waterfall of fetching the tick bitmap, parsing the bitmap to know which ticks to fetch, and
/// then sending additional multicalls to fetch the tick data
abstract contract TickLens {
    struct PopulatedTick {
        int24 tick;
        int128 liquidityNet;
        uint128 liquidityGross;
        uint256 feeGrowthOutside0X128;
        uint256 feeGrowthOutside1X128;
    }

    /// @notice Get the number of populated ticks in a word of the tick bitmap of a pool
    function getNumberOfInitializedTicks(
        V3PoolCallee pool,
        int16 tickBitmapIndex
    ) internal view returns (uint256 numberOfInitializedTicks) {
        // fetch bitmap
        uint256 bitmap = pool.tickBitmap(tickBitmapIndex);

        // calculate the number of populated ticks
        for (uint256 mask = 1; mask != 0; mask <<= 1) {
            if (bitmap & mask != 0) ++numberOfInitializedTicks;
        }
    }

    function populateTick(V3PoolCallee pool, int24 tick, PopulatedTick memory populatedTick) internal view {
        PoolCaller.Info memory info = pool.ticks(tick);
        populatedTick.tick = tick;
        populatedTick.liquidityNet = info.liquidityNet;
        populatedTick.liquidityGross = info.liquidityGross;
        populatedTick.feeGrowthOutside0X128 = info.feeGrowthOutside0X128;
        populatedTick.feeGrowthOutside1X128 = info.feeGrowthOutside1X128;
    }

    function populateTicksInWord(
        V3PoolCallee pool,
        int16 tickBitmapIndex,
        int24 tickSpacing,
        PopulatedTick[] memory populatedTicks,
        uint256 startIdx
    ) internal view returns (uint256) {
        // fetch bitmap
        uint256 bitmap = pool.tickBitmap(tickBitmapIndex);
        for (uint256 bitPos; bitPos < 256; ++bitPos) {
            //slither-disable-next-line incorrect-shift
            if (bitmap & (1 << bitPos) != 0) {
                int24 tick;
                assembly {
                    tick := mul(tickSpacing, add(shl(8, tickBitmapIndex), bitPos))
                }
                populateTick(pool, tick, populatedTicks[startIdx++]);
            }
        }
        return startIdx;
    }
}
