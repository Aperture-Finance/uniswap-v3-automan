// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import {PoolAddressPancakeSwapV3} from "@aperture_finance/uni-v3-lib/src/PoolAddressPancakeSwapV3.sol";
import "./base/Automan.sol";
import {PancakeV3Callback} from "./base/Callback.sol";
import {PCSV3Immutables} from "./base/Immutables.sol";

contract PCSV3Automan is Automan, PancakeV3Callback {
    constructor(
        IPCSV3NonfungiblePositionManager nonfungiblePositionManager,
        address owner_
    ) payable Ownable(owner_) PCSV3Immutables(nonfungiblePositionManager) {}

    function computeAddressSorted(PoolKey memory poolKey) internal view override returns (address pool) {
        pool = PoolAddressPancakeSwapV3.computeAddressSorted(deployer, poolKey);
    }
}
