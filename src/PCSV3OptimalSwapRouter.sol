// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import {IPCSV3NonfungiblePositionManager} from "@aperture_finance/uni-v3-lib/src/interfaces/INonfungiblePositionManager.sol";
import {PoolAddressPancakeSwapV3} from "@aperture_finance/uni-v3-lib/src/PoolAddressPancakeSwapV3.sol";
import {PoolKey} from "@aperture_finance/uni-v3-lib/src/PoolKey.sol";
import {OptimalSwapRouter, PancakeV3Callback} from "./base/OptimalSwapRouter.sol";
import {PCSV3Immutables} from "./base/Immutables.sol";

/// @title Optimal Swap Router
/// @author Aperture Finance
/// @dev This router swaps through an aggregator to get to approximately the optimal ratio to add liquidity in a PCSV3
/// pool, then swaps the tokens to the optimal ratio to add liquidity in the same pool.
contract PCSV3OptimalSwapRouter is PancakeV3Callback, OptimalSwapRouter {
    constructor(IPCSV3NonfungiblePositionManager npm) payable PCSV3Immutables(npm) {}

    function computeAddressSorted(PoolKey memory poolKey) internal view override returns (address pool) {
        pool = PoolAddressPancakeSwapV3.computeAddressSorted(deployer, poolKey);
    }
}
