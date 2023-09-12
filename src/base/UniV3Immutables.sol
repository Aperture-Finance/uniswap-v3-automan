// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.18;

import {INonfungiblePositionManager as INPM} from "@aperture_finance/uni-v3-lib/src/interfaces/INonfungiblePositionManager.sol";
import {IUniV3Immutables} from "../interfaces/IUniV3Immutables.sol";

/// @title Immutable state
/// @notice Immutable state used by periphery contracts
abstract contract UniV3Immutables is IUniV3Immutables {
    /// @notice Uniswap v3 Position Manager
    INPM public immutable npm;
    /// @notice Uniswap v3 Factory
    address public immutable factory;
    /// @notice Wrapped ETH
    address payable public immutable override WETH9;

    constructor(INPM nonfungiblePositionManager) payable {
        npm = nonfungiblePositionManager;
        factory = nonfungiblePositionManager.factory();
        WETH9 = payable(nonfungiblePositionManager.WETH9());
    }
}
