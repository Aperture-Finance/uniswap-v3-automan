// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "./base/OptimalSwapRouter.sol";
import {IPCSV3NonfungiblePositionManager} from "@aperture_finance/uni-v3-lib/src/interfaces/IPCSV3NonfungiblePositionManager.sol";

/// @title Optimal Swap Router
/// @author Aperture Finance
/// @dev This router swaps through an aggregator to get to approximately the optimal ratio to add liquidity in a PCSV3
/// pool, then swaps the tokens to the optimal ratio to add liquidity in the same pool.
contract PCSV3OptimalSwapRouter is PCSV3SwapRouter, OptimalSwapRouter {
    constructor(IPCSV3NonfungiblePositionManager npm, address owner_) payable Ownable(owner_) PCSV3Immutables(npm) {}
}
