// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import "./PositionLens.sol";

/// @notice A lens for Uniswap v3 that peeks into the current state of all positions by an owner without deployment
/// @author Aperture Finance
/// @dev The return data can be accessed externally by `eth_call` without a `to` address or internally by catching the
/// revert data, and decoded by `abi.decode(data, (PositionState[]))`
contract EphemeralAllPositions is PositionLens {
    constructor(INPM npm, address owner) payable {
        PositionState[] memory positions = allPositions(npm, owner);
        bytes memory returnData = abi.encode(positions);
        assembly ("memory-safe") {
            // The return data in a constructor will be written to code, which may exceed the contract size limit.
            revert(add(returnData, 0x20), mload(returnData))
        }
    }

    /// @dev Public function to expose the abi for easier decoding using TypeChain
    /// @param npm Nonfungible position manager
    /// @param owner The address that owns the NFTs
    function allPositions(INPM npm, address owner) public payable returns (PositionState[] memory positions) {
        uint256 balance = NPMCaller.balanceOf(npm, owner);
        positions = new PositionState[](balance);
        unchecked {
            for (uint256 i; i < balance; ++i) {
                uint256 tokenId = NPMCaller.tokenOfOwnerByIndex(npm, owner, i);
                peek(npm, tokenId, positions[i]);
            }
        }
    }
}
