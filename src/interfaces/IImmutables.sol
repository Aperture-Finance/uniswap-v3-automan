// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "@aperture_finance/uni-v3-lib/src/interfaces/ICommonNonfungiblePositionManager.sol";

/// @title Immutables of the UniV3-style DEX Automation Manager
interface IImmutables {
    /// @notice Uniswap v3 Position Manager
    function npm() external view returns (ICommonNonfungiblePositionManager);

    /// @return Returns the address of WETH9
    function WETH9() external view returns (address payable);
}

interface IUniV3Immutables is IImmutables {
    /// @return Returns the address of the Uniswap V3 factory
    function factory() external view returns (address);
}

interface IPCSV3Immutables is IImmutables {
    /// @return Returns the address of the PancakeSwap V3 deployer
    function deployer() external view returns (address);
}
