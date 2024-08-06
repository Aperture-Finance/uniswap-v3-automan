// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "./base/Automan.sol";
import {UniV3SwapRouter} from "./base/SwapRouter.sol";
import {UniV3Immutables} from "./base/Immutables.sol";

contract UniV3Automan is Automan, UniV3SwapRouter {
    constructor(
        INPM nonfungiblePositionManager,
        address owner_
    ) payable Ownable(owner_) UniV3Immutables(nonfungiblePositionManager) {}
}
