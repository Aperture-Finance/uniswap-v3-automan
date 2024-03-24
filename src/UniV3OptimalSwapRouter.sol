// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import {INonfungiblePositionManager} from "@aperture_finance/uni-v3-lib/src/interfaces/INonfungiblePositionManager.sol";
import {PoolAddress, PoolKey} from "@aperture_finance/uni-v3-lib/src/PoolAddress.sol";
import {OptimalSwapRouter, UniswapV3Callback} from "./base/OptimalSwapRouter.sol";
import {UniV3Immutables} from "./base/Immutables.sol";

/// @title Optimal Swap Router
/// @author Aperture Finance
/// @dev This router swaps through an aggregator to get to approximately the optimal ratio to add liquidity in a UniV3
/// pool, then swaps the tokens to the optimal ratio to add liquidity in the same pool.
contract UniV3OptimalSwapRouter is UniswapV3Callback, OptimalSwapRouter {
    constructor(INonfungiblePositionManager npm) payable UniV3Immutables(npm) {}

    function computeAddressSorted(PoolKey memory poolKey) internal view override returns (address pool) {
        pool = PoolAddress.computeAddressSorted(factory, poolKey);
    }
}
