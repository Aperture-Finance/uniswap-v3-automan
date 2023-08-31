// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./PositionLens.sol";

/// @notice A lens for Uniswap v3 that peeks into the current state of position and pool info without deployment
/// @author Aperture Finance
/// @dev The return data can be accessed externally by `eth_call` without a `to` address or internally by
/// `address(new EphemeralGetPosition(npm, tokenId)).code`, and decoded by `abi.decode(data, (PositionState))`
contract EphemeralGetPosition is PositionLens {
    // slither-disable-next-line locked-ether
    constructor(INPM npm, uint256 tokenId) payable {
        PositionState memory pos = getPosition(npm, tokenId);
        bytes memory returnData = abi.encode(pos);
        assembly ("memory-safe") {
            return(add(returnData, 0x20), mload(returnData))
        }
    }

    /// @dev Public function to expose the abi for easier decoding using TypeChain
    /// @param npm Nonfungible position manager
    /// @param tokenId Token ID of the position
    // slither-disable-next-line locked-ether
    function getPosition(INPM npm, uint256 tokenId) public payable returns (PositionState memory state) {
        state.owner = NPMCaller.ownerOf(npm, tokenId);
        peek(npm, tokenId, state);
    }
}
