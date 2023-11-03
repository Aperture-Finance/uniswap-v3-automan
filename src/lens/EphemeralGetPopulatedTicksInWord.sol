// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./TickLens.sol";

/// @notice A lens that fetches chunks of tick data in a single bitmap for a Uniswap v3 pool without deployment
/// @author Aperture Finance
/// @dev The return data can be accessed externally by `eth_call` without a `to` address or internally by
/// `address(new EphemeralGetPopulatedTicksInWord(pool, tickBitmapIndex)).code`, and decoded by
/// `abi.decode(data, (PopulatedTick[]))`
contract EphemeralGetPopulatedTicksInWord is TickLens {
    // slither-disable-next-line locked-ether
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
    // slither-disable-next-line locked-ether
    function getPopulatedTicksInWord(
        V3PoolCallee pool,
        int16 tickBitmapIndex
    ) public payable returns (PopulatedTick[] memory populatedTicks) {
        // checks that the pool exists
        int24 tickSpacing = IUniswapV3Pool(V3PoolCallee.unwrap(pool)).tickSpacing();
        // calculate the number of populated ticks
        (uint256 bitmap, uint256 count) = getNumberOfInitializedTicks(pool, tickBitmapIndex);
        // fetch populated tick data
        populatedTicks = new PopulatedTick[](count);
        populateTicksInWord(pool, tickBitmapIndex, tickSpacing, bitmap, populatedTicks, 0);
    }
}
