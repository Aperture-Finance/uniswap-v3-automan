// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "./base/OptimalSwapRouter.sol";

/// @title Optimal Swap Router
/// @author Aperture Finance
/// @dev This router swaps through an aggregator to get to approximately the optimal ratio to add liquidity in a UniV3
/// pool, then swaps the tokens to the optimal ratio to add liquidity in the same pool.
contract UniV3OptimalSwapRouter is UniV3SwapRouter, OptimalSwapRouter {
    constructor(ICommonNonfungiblePositionManager npm, address owner_) payable Ownable(owner_) UniV3Immutables(npm) {}
}
