// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.18;

import {INonfungiblePositionManager as INPM, IPCSV3NonfungiblePositionManager as IPCSV3NPM} from "@aperture_finance/uni-v3-lib/src/interfaces/INonfungiblePositionManager.sol";
import "../interfaces/IImmutables.sol";

/// @title Immutable state
/// @notice Immutable state used by periphery contracts
abstract contract Immutables is IImmutables {
    /// @notice Nonfungible Position Manager
    INPM public immutable npm;
    /// @notice Wrapped ETH
    address payable public immutable override WETH9;

    constructor(INPM nonfungiblePositionManager) payable {
        npm = nonfungiblePositionManager;
        WETH9 = payable(nonfungiblePositionManager.WETH9());
    }
}

/// @title UniswapV3 Immutable state
/// @notice Immutable state used by UniV3 periphery contracts
abstract contract UniV3Immutables is Immutables, IUniV3Immutables {
    /// @notice Uniswap v3 Factory
    address public immutable factory;

    constructor(INPM nonfungiblePositionManager) payable Immutables(nonfungiblePositionManager) {
        factory = nonfungiblePositionManager.factory();
    }
}

/// @title PancakeSwapV3 Immutable state
/// @notice Immutable state used by PCSV3 periphery contracts
abstract contract PCSV3Immutables is Immutables, IPCSV3Immutables {
    /// @notice PancakeSwap v3 Deployer
    address public immutable deployer;

    constructor(IPCSV3NPM nonfungiblePositionManager) payable Immutables(nonfungiblePositionManager) {
        deployer = nonfungiblePositionManager.deployer();
    }
}
