// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./TickLens.sol";

/// @notice A lens that fetches chunks of tick data in a single bitmap for a Uniswap v3 pool without deployment
/// @author Aperture Finance
/// @dev The return data can be accessed externally by `eth_call` without a `to` address or internally by
/// `address(new EphemeralGetPopulatedTicksInWord(pool, tickBitmapIndex)).code`, and decoded by
/// `abi.decode(data, (PopulatedTick[]))`
contract EphemeralGetPopulatedTicksInWord is TickLens {
    constructor(V3PoolCallee pool, int16 tickBitmapIndex) payable {
        PopulatedTick[] memory populatedTicks = getPopulatedTicksInWord(pool, tickBitmapIndex);
        bytes memory returnData = abi.encode(populatedTicks);
        assembly ("memory-safe") {
            return(add(returnData, 0x20), mload(returnData))
        }
    }

    /// @notice Get all the tick data for the populated ticks from a word of the tick bitmap of a pool
    /// @param pool The address of the pool for which to fetch populated tick data
    /// @param tickBitmapIndex The index of the word in the tick bitmap for which to parse the bitmap and
    /// fetch all the populated ticks
    /// @return populatedTicks An array of tick data for the given word in the tick bitmap
    function getPopulatedTicksInWord(
        V3PoolCallee pool,
        int16 tickBitmapIndex
    ) public payable returns (PopulatedTick[] memory populatedTicks) {
        // calculate the number of populated ticks
        uint256 numTicks = getNumberOfInitializedTicks(pool, tickBitmapIndex);
        // fetch populated tick data
        int24 tickSpacing = pool.tickSpacing();
        populatedTicks = new PopulatedTick[](numTicks);
        populateTicksInWord(pool, tickBitmapIndex, tickSpacing, populatedTicks, 0);
    }
}
