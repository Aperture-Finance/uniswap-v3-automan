// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./PositionLens.sol";

/// @notice A lens for Uniswap v3 that peeks into the current state of position and pool info without deployment
/// @author Aperture Finance
/// @dev The return data can be accessed externally by `eth_call` without a `to` address or internally by catching the
/// revert data, and decoded by `abi.decode(data, (PositionState[]))`
contract EphemeralGetPositions is PositionLens {
    // slither-disable-next-line locked-ether
    constructor(INPM npm, uint256 startTokenId, uint256 endTokenId) payable {
        PositionState[] memory positions = getPositions(npm, startTokenId, endTokenId);
        bytes memory returnData = abi.encode(positions);
        assembly ("memory-safe") {
            revert(add(returnData, 0x20), mload(returnData))
        }
    }

    /// @dev Public function to expose the abi for easier decoding using TypeChain
    /// @param npm Nonfungible position manager
    /// @param startTokenId The first tokenId to query
    /// @param endTokenId The last tokenId to query (exclusive)
    // slither-disable-next-line locked-ether
    function getPositions(
        INPM npm,
        uint256 startTokenId,
        uint256 endTokenId
    ) public payable returns (PositionState[] memory positions) {
        unchecked {
            positions = new PositionState[](endTokenId - startTokenId);
            uint256 i;
            for (uint256 tokenId = startTokenId; tokenId < endTokenId; ++tokenId) {
                PositionState memory state = positions[i];
                if (_positionInPlace(npm, tokenId, state.position)) {
                    ++i;
                    state.tokenId = tokenId;
                    state.owner = NPMCaller.ownerOf(npm, tokenId);
                    V3PoolCallee pool = V3PoolCallee.wrap(
                        PoolAddress.computeAddressSorted(
                            NPMCaller.factory(npm),
                            state.position.token0,
                            state.position.token1,
                            state.position.fee
                        )
                    );
                    state.activeLiquidity = pool.liquidity();
                    slot0InPlace(pool, state.slot0);
                    if (state.position.liquidity != 0) {
                        (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) = getFeeGrowthInside(
                            pool,
                            state.position.tickLower,
                            state.position.tickUpper,
                            state.slot0.tick
                        );
                        updatePosition(state.position, feeGrowthInside0X128, feeGrowthInside1X128);
                    }
                    state.decimals0 = ERC20Callee.wrap(state.position.token0).decimals();
                    state.decimals1 = ERC20Callee.wrap(state.position.token1).decimals();
                }
            }
            assembly ("memory-safe") {
                mstore(positions, i)
            }
        }
    }

    function _positionInPlace(INPM npm, uint256 tokenId, PositionFull memory pos) internal view returns (bool exists) {
        bytes4 selector = INPM.positions.selector;
        assembly ("memory-safe") {
            // Write the abi-encoded calldata into memory.
            mstore(0, selector)
            mstore(4, tokenId)
            // We use 36 because of the length of our calldata.
            // We copy up to 384 bytes of return data at pos's pointer.
            exists := staticcall(gas(), npm, 0, 0x24, pos, 0x180)
        }
    }
}
