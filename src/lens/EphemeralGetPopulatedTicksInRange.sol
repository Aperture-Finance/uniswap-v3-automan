// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./TickLens.sol";

/// @notice A lens that fetches chunks of tick data in a range for a Uniswap v3 pool without deployment
/// @author Aperture Finance
/// @dev The return data can be accessed externally by `eth_call` without a `to` address or internally by catching the
/// revert data, and decoded by `abi.decode(data, (PopulatedTick[]))`
contract EphemeralGetPopulatedTicksInRange is TickLens {
    // slither-disable-next-line locked-ether
    constructor(V3PoolCallee pool, int24 tickLower, int24 tickUpper) payable {
        PopulatedTick[] memory populatedTicks = getPopulatedTicksInRange(pool, tickLower, tickUpper);
        bytes memory returnData = abi.encode(populatedTicks);
        assembly ("memory-safe") {
            revert(add(returnData, 0x20), mload(returnData))
        }
    }

    /// @notice Get all the tick data for the populated ticks from tickLower to tickUpper
    /// @param pool The address of the pool for which to fetch populated tick data
    /// @param tickLower The lower tick boundary of the populated ticks to fetch
    /// @param tickUpper The upper tick boundary of the populated ticks to fetch
    /// @return populatedTicks An array of tick data for the given word in the tick bitmap
    // slither-disable-next-line locked-ether
    function getPopulatedTicksInRange(
        V3PoolCallee pool,
        int24 tickLower,
        int24 tickUpper
    ) public payable returns (PopulatedTick[] memory populatedTicks) {
        require(tickLower <= tickUpper);
        // checks that the pool exists
        int24 tickSpacing = IUniswapV3Pool(V3PoolCallee.unwrap(pool)).tickSpacing();
        int16 wordPosLower;
        int16 wordPosUpper;
        {
            int24 compressed = TickBitmap.compress(tickLower, tickSpacing);
            wordPosLower = int16(compressed >> 8);
            compressed = TickBitmap.compress(tickUpper, tickSpacing);
            wordPosUpper = int16(compressed >> 8);
        }
        // calculate the number of populated ticks
        uint256 numberOfPopulatedTicks;
        for (int16 wordPos = wordPosLower; wordPos <= wordPosUpper; ++wordPos) {
            numberOfPopulatedTicks += getNumberOfInitializedTicks(pool, wordPos);
        }
        // fetch populated tick data
        populatedTicks = new PopulatedTick[](numberOfPopulatedTicks);
        uint256 startIdx;
        for (int16 wordPos = wordPosLower; wordPos <= wordPosUpper; ++wordPos) {
            startIdx = populateTicksInWord(pool, wordPos, tickSpacing, populatedTicks, startIdx);
        }
    }
}
