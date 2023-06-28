// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "@aperture_finance/uni-v3-lib/src/interfaces/INonfungiblePositionManager.sol";

/// @title Immutables of the Uniswap v3 Automation Manger
interface IUniV3Immutables {
    /// @notice Uniswap v3 Position Manager
    function npm() external view returns (INonfungiblePositionManager);

    /// @return Returns the address of the Uniswap V3 factory
    function factory() external view returns (address);

    /// @return Returns the address of WETH9
    function WETH9() external view returns (address payable);
}
