// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import {PoolAddress} from "@aperture_finance/uni-v3-lib/src/PoolAddress.sol";
import "./base/Automan.sol";
import {UniswapV3Callback} from "./base/Callback.sol";
import {UniV3Immutables} from "./base/Immutables.sol";

contract UniV3Automan is Automan, UniswapV3Callback {
    constructor(
        INPM nonfungiblePositionManager,
        address owner_
    ) payable Ownable(owner_) UniV3Immutables(nonfungiblePositionManager) {}

    function computeAddressSorted(PoolKey memory poolKey) internal view override returns (address pool) {
        pool = PoolAddress.computeAddressSorted(factory, poolKey);
    }
}
