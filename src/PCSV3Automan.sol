// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "./base/Automan.sol";
import {PCSV3SwapRouter} from "./base/SwapRouter.sol";
import {PCSV3Immutables} from "./base/Immutables.sol";
import {IPCSV3NonfungiblePositionManager} from "@aperture_finance/uni-v3-lib/src/interfaces/IPCSV3NonfungiblePositionManager.sol";

contract PCSV3Automan is Automan, PCSV3SwapRouter {
    constructor(
        IPCSV3NonfungiblePositionManager nonfungiblePositionManager,
        address owner_
    ) payable Ownable(owner_) PCSV3Immutables(nonfungiblePositionManager) {}
}
