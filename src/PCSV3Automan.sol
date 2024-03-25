// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "./base/Automan.sol";
import "./base/SwapRouter.sol";

contract PCSV3Automan is Automan, PCSV3SwapRouter {
    constructor(
        IPCSV3NonfungiblePositionManager nonfungiblePositionManager,
        address owner_
    ) payable Ownable(owner_) PCSV3Immutables(nonfungiblePositionManager) {}
}
