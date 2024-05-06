// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/access/Ownable.sol";
import {INonfungiblePositionManager as INPM} from "@aperture_finance/uni-v3-lib/src/interfaces/INonfungiblePositionManager.sol";

interface Automan {
    function rebalance(
        INPM.MintParams memory params,
        uint256 tokenId,
        uint256 feePips,
        bytes calldata swapData,
        uint256 permitDeadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 newTokenId, uint128 liquidity, uint256 amount0, uint256 amount1);

    function rebalance(
        INPM.MintParams memory params,
        uint256 tokenId,
        uint256 feePips,
        bytes calldata swapData
    ) external returns (uint256 newTokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
}

contract AutomanRelayerProxy is Ownable, Automan {
    mapping(address=>mapping(address=>bool)) public allowance;
    INPM public npm;
    Automan public automan;
    constructor(INPM _npm, Automan _automan) Ownable(msg.sender) {
        npm = _npm;
        automan = _automan;
    }

    function setAllowance(address[] calldata relayers, address[] calldata owners, bool value) external onlyOwner {
        uint lrelayer = relayers.length;
        uint lowners = owners.length;
        for(uint i = 0; i < lrelayer; i ++ ) {
            for (uint j = 0; j < lowners; j ++) {
                allowance[relayers[i]][owners[j]] = value;
            }
        }
    }

    function updateNpm(INPM _npm) external onlyOwner {
        npm = _npm;
    }

    function rebalance(
        INPM.MintParams memory params,
        uint256 tokenId,
        uint256 feePips,
        bytes calldata swapData,
        uint256 permitDeadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 newTokenId, uint128 liquidity, uint256 amount0, uint256 amount1) {
        address owner = npm.ownerOf(tokenId);
        require(allowance[msg.sender][owner], "not allow relayer");
        return automan.rebalance(params, tokenId, feePips, swapData, permitDeadline, v, r, s);
    }

    function rebalance(
        INPM.MintParams memory params,
        uint256 tokenId,
        uint256 feePips,
        bytes calldata swapData
    ) external returns (uint256 newTokenId, uint128 liquidity, uint256 amount0, uint256 amount1) {
        address owner = npm.ownerOf(tokenId);
        require(allowance[msg.sender][owner], "not allow relayer");
        return automan.rebalance(params, tokenId, feePips, swapData);
    }
}
