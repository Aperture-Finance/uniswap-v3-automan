// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "./base/Automan.sol";
import "./base/SwapRouter.sol";

contract UniV3Automan is Automan, UniV3SwapRouter {
    constructor(
        INPM nonfungiblePositionManager,
        address owner_
    ) payable Ownable(owner_) UniV3Immutables(nonfungiblePositionManager) {}
}
