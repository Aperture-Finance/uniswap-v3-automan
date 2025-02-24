// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "@pancakeswap/v3-core/contracts/interfaces/callback/IPancakeV3SwapCallback.sol";
import "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";
import {ICommonNonfungiblePositionManager as INPM} from "@aperture_finance/uni-v3-lib/src/interfaces/ICommonNonfungiblePositionManager.sol";
import {IUniswapV3NonfungiblePositionManager as IUniV3NPM} from "@aperture_finance/uni-v3-lib/src/interfaces/IUniswapV3NonfungiblePositionManager.sol";
import {ISlipStreamNonfungiblePositionManager as ISlipStreamNPM} from "@aperture_finance/uni-v3-lib/src/interfaces/ISlipStreamNonfungiblePositionManager.sol";
import {V3PoolCallee} from "@aperture_finance/uni-v3-lib/src/PoolCaller.sol";
import {IPCSV3Immutables, IUniV3Immutables} from "./IImmutables.sol";
import {ISwapRouterCommon} from "./ISwapRouter.sol";

/// @title Interface for the Uniswap v3 Automation Manager
interface IAutomanCommon is ISwapRouterCommon {
    /************************************************
     *  EVENTS
     ***********************************************/

    event FeeConfigSet(address feeCollector, uint96 feeLimitPips);
    event ControllersSet(address[] controllers, bool[] statuses);
    event Mint(uint256 indexed tokenId);
    event IncreaseLiquidity(uint256 indexed tokenId);
    event DecreaseLiquidity(uint256 indexed tokenId);
    event RemoveLiquidity(uint256 indexed tokenId);
    event Reinvest(uint256 indexed tokenId);
    event Rebalance(uint256 indexed tokenId);

    /************************************************
     *  ERRORS
     ***********************************************/

    error NotApproved();
    error InsufficientAmount();
    error FeeLimitExceeded();

    struct FeeConfig {
        /// @notice The address that receives fees
        /// @dev It is stored in the lower 160 bits of the slot
        address feeCollector;
        /// @notice The maximum fee percentage that can be charged for a transaction
        /// @dev It is stored in the upper 96 bits of the slot
        uint96 feeLimitPips;
    }

    struct ZapOutParams {
        // The amount of token0 to send to feeCollector
        uint256 token0FeeAmount;
        // The amount of token1 to send to feeCollector
        uint256 token1FeeAmount;
        // The token to collect. E.g. allows collecting volatile pairs to stablecoin.
        // Use address(0) to collect as same pair
        address tokenOut;
        // The minimum amount of tokenOut to receive
        uint256 tokenOutMin;
        // If isCollect and tokenOut, swapData for swapping collected fees to tokenOut
        bytes swapData0;
        bytes swapData1;
        // If isCollect and tokenOut is native, whether to unwrap
        bool isUnwrapNative;
    }

    // Signature permit struct.
    struct Permit {
        // The deadline of the permit signature
        uint256 deadline;
        // The recovery byte of the signature
        uint8 v;
        // Half of the ECDSA signature pair
        bytes32 r;
        // Half of the ECDSA signature pair
        bytes32 s;
    }

    /// @notice Set the fee limit and collector
    /// @param _feeConfig The new fee configuration
    function setFeeConfig(FeeConfig calldata _feeConfig) external;

    /// @notice Set addresses that can perform automation
    function setControllers(address[] calldata controllers, bool[] calldata statuses) external;

    /// @notice Check if an address is a controller
    /// @param addressToCheck The address to check
    function isController(address addressToCheck) external view returns (bool);

    /// @notice Get swap amount, output amount, swap direction for double-sided optimal deposit
    /// @param pool Uniswap v3 pool
    /// @param tickLower The lower tick of the position in which to add liquidity
    /// @param tickUpper The upper tick of the position in which to add liquidity
    /// @param amount0Desired The desired amount of token0 to be spent
    /// @param amount1Desired The desired amount of token1 to be spent
    /// @return amountIn The optimal swap amount
    /// @return amountOut Expected output amount
    /// @return zeroForOne The direction of the swap, true for token0 to token1, false for token1 to token0
    /// @return sqrtPriceX96 The sqrt(price) after the swap
    function getOptimalSwap(
        V3PoolCallee pool,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) external view returns (uint256 amountIn, uint256 amountOut, bool zeroForOne, uint160 sqrtPriceX96);

    /// @notice Increases the amount of liquidity in a position using optimal swap
    /// @dev Anyone can increase the liquidity of a position, but the caller must pay the tokens
    /// @param params tokenId The ID of the token for which liquidity is being increased,
    /// amount0Desired The desired amount of token0 to be spent,
    /// amount1Desired The desired amount of token1 to be spent,
    /// amount0Min The minimum amount of token0 to spend, which serves as a slippage check,
    /// amount1Min The minimum amount of token1 to spend, which serves as a slippage check,
    /// deadline The time by which the transaction must be included to effect the change
    /// @param swapData The address of the external router and call data
    /// @param token0FeeAmount The amount of token0 to send to feeCollector
    /// @param token1FeeAmount The amount of token1 to send to feeCollector
    /// @return liquidity The new liquidity amount as a result of the increase
    /// @return amount0 The amount of token0 to achieve resulting liquidity
    /// @return amount1 The amount of token1 to achieve resulting liquidity
    function increaseLiquidityOptimal(
        INPM.IncreaseLiquidityParams memory params,
        bytes calldata swapData,
        uint256 token0FeeAmount,
        uint256 token1FeeAmount
    ) external payable returns (uint128 liquidity, uint256 amount0, uint256 amount1);

    /// @notice Increases the amount of liquidity in a position using optimal swap and a single tokenIn.
    /// @dev Call this when the pool does exist and is initialized. Note that if the pool is created but not initialized
    /// a method does not exist, i.e. the pool is assumed to be initialized.
    /// @param params tokenId The ID of the token for which liquidity is being increased,
    /// amount0Desired The amount of tokenIn to swap for token0,
    /// amount1Desired The amount of tokenIn to swap for token1,
    /// amount0Min The minimum amount of token0 to spend, which serves as a slippage check,
    /// amount1Min The minimum amount of token1 to spend, which serves as a slippage check,
    /// deadline The time by which the transaction must be included to effect the change
    /// @param tokenIn The tokenIn to swap for token0 and token1
    /// @param tokenInFeeAmount The amount of tokenIn to send to feeCollector
    /// @param swapData0 The swap data for swapping from tokenIn to token0
    /// @param swapData1 The swap data for swapping from tokenIn to token1
    /// @return liquidity The amount of liquidity for this position
    /// @return amount0 The amount of token0 spent
    /// @return amount1 The amount of token1 spent
    function increaseLiquidityFromTokenIn(
        IUniV3NPM.IncreaseLiquidityParams memory params,
        address tokenIn,
        uint256 tokenInFeeAmount,
        bytes calldata swapData0,
        bytes calldata swapData1
    ) external payable returns (uint128 liquidity, uint256 amount0, uint256 amount1);

    /// @notice Decreases the amount of liquidity in a position and optionally swaps to tokenOut
    /// @param params tokenId The ID of the token for which liquidity is being decreased,
    /// liquidity The amount by which liquidity will be decreased,
    /// amount0Min The minimum amount of token0 that should be accounted for the burned liquidity,
    /// amount1Min The minimum amount of token1 that should be accounted for the burned liquidity,
    /// deadline The time by which the transaction must be included to effect the change
    /// @param zapOutParams The zap out params
    /// @return amount0 The amount of token0 returned minus fees
    /// @return amount1 The amount of token1 returned minus fees
    function decreaseLiquidity(
        INPM.DecreaseLiquidityParams memory params,
        IAutomanCommon.ZapOutParams calldata zapOutParams
    ) external returns (uint256 amount0, uint256 amount1);

    /// @notice Decreases the amount of liquidity in a position and swaps to a single token using permit
    /// @param params tokenId The ID of the token for which liquidity is being decreased,
    /// liquidity The amount by which liquidity will be decreased,
    /// amount0Min The minimum amount of token0 that should be accounted for the burned liquidity,
    /// amount1Min The minimum amount of token1 that should be accounted for the burned liquidity,
    /// deadline The time by which the transaction must be included to effect the change
    /// @param zapOutParams The zap out params
    /// @param permit The signature permit
    /// @return amount0 The amount of token0 returned minus fees
    /// @return amount1 The amount of token1 returned minus fees
    function decreaseLiquidity(
        INPM.DecreaseLiquidityParams memory params,
        IAutomanCommon.ZapOutParams calldata zapOutParams,
        Permit calldata permit
    ) external returns (uint256 amount0, uint256 amount1);

    /// @notice Reinvests all fees owed to a specific position to the same position using optimal swap
    /// @param params tokenId The ID of the token for which liquidity is being increased,
    /// amount0Desired The desired amount of token0 to be spent,
    /// amount1Desired The desired amount of token1 to be spent,
    /// amount0Min The minimum amount of token0 to spend, which serves as a slippage check,
    /// amount1Min The minimum amount of token1 to spend, which serves as a slippage check,
    /// deadline The time by which the transaction must be included to effect the change
    /// @param token0FeeAmount The amount of token0 to send to feeCollector
    /// @param token1FeeAmount The amount of token1 to send to feeCollector
    /// @param swapData The address of the external router and call data
    /// @return liquidity The new liquidity amount as a result of the increase
    /// @return amount0 The amount of token0 to achieve resulting liquidity
    /// @return amount1 The amount of token1 to achieve resulting liquidity
    function reinvest(
        INPM.IncreaseLiquidityParams memory params,
        uint256 token0FeeAmount,
        uint256 token1FeeAmount,
        bytes calldata swapData
    ) external returns (uint128 liquidity, uint256 amount0, uint256 amount1);

    /// @notice Reinvests all fees owed to a specific position to the same position using optimal swap and permit
    /// @param params tokenId The ID of the token for which liquidity is being increased,
    /// amount0Desired The desired amount of token0 to be spent,
    /// amount1Desired The desired amount of token1 to be spent,
    /// amount0Min The minimum amount of token0 to spend, which serves as a slippage check,
    /// amount1Min The minimum amount of token1 to spend, which serves as a slippage check,
    /// deadline The time by which the transaction must be included to effect the change
    /// @param token0FeeAmount The amount of token0 to send to feeCollector
    /// @param token1FeeAmount The amount of token1 to send to feeCollector
    /// @param swapData The address of the external router and call data
    /// @param permit The signature permit
    /// @return liquidity The new liquidity amount as a result of the increase
    /// @return amount0 The amount of token0 to achieve resulting liquidity
    /// @return amount1 The amount of token1 to achieve resulting liquidity
    function reinvest(
        INPM.IncreaseLiquidityParams memory params,
        uint256 token0FeeAmount,
        uint256 token1FeeAmount,
        bytes calldata swapData,
        Permit calldata permit
    ) external returns (uint128 liquidity, uint256 amount0, uint256 amount1);
}

interface IAutomanUniV3MintRebalance {
    /// @notice Creates a new position wrapped in a NFT using optimal swap
    /// @dev Call this when the pool does exist and is initialized. Note that if the pool is created but not initialized
    /// a method does not exist, i.e. the pool is assumed to be initialized.
    /// @param params The params necessary to mint a position, encoded as `MintParams` in calldata
    /// token0 The address of the token0 for a specific pool
    /// token1 The address of the token1 for a specific pool
    /// fee The fee associated with the pool
    /// tickLower The lower tick of the position in which to add liquidity
    /// tickUpper The upper tick of the position in which to add liquidity
    /// amount0Desired The desired amount of token0 to be spent
    /// amount1Desired The desired amount of token1 to be spent
    /// amount0Min The minimum amount of token0 to spend, which serves as a slippage check
    /// amount1Min The minimum amount of token1 to spend, which serves as a slippage check
    /// recipient The recipient of the minted position
    /// deadline The time by which the transaction must be included to effect the change
    /// @param swapData The address of the external router and call data
    /// @param token0FeeAmount The amount of token0 to send to feeCollector
    /// @param token1FeeAmount The amount of token1 to send to feeCollector
    /// @return tokenId The ID of the token that represents the minted position
    /// @return liquidity The amount of liquidity for this position
    /// @return amount0 The amount of token0 spent
    /// @return amount1 The amount of token1 spent
    function mintOptimal(
        IUniV3NPM.MintParams memory params,
        bytes calldata swapData,
        uint256 token0FeeAmount,
        uint256 token1FeeAmount
    ) external payable returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);

    /// @notice Creates a new position wrapped in a NFT using a single tokenIn.
    /// @dev Call this when the pool does exist and is initialized. Note that if the pool is created but not initialized
    /// a method does not exist, i.e. the pool is assumed to be initialized.
    /// @param params The params necessary to mint a position, encoded as `MintParams` in calldata
    /// token0 The address of the token0 for a specific pool
    /// token1 The address of the token1 for a specific pool
    /// fee The fee associated with the pool
    /// tickLower The lower tick of the position in which to add liquidity
    /// tickUpper The upper tick of the position in which to add liquidity
    /// amount0Desired The amount of tokenIn to swap for token0
    /// amount1Desired The amount of tokenIn to swap for token1
    /// amount0Min The minimum amount of token0 to spend, which serves as a slippage check
    /// amount1Min The minimum amount of token1 to spend, which serves as a slippage check
    /// recipient The recipient of the minted position
    /// deadline The time by which the transaction must be included to effect the change
    /// @param tokenIn The tokenIn to swap for token0 and token1
    /// @param tokenInFeeAmount The amount of tokenIn to send to feeCollector
    /// @param swapData0 The swap data for swapping from tokenIn to token0
    /// @param swapData1 The swap data for swapping from tokenIn to token1
    /// @return tokenId The ID of the token that represents the minted position
    /// @return liquidity The amount of liquidity for this position
    /// @return amount0 The amount of token0 spent
    /// @return amount1 The amount of token1 spent
    function mintFromTokenIn(
        IUniV3NPM.MintParams memory params,
        address tokenIn,
        uint256 tokenInFeeAmount,
        bytes calldata swapData0,
        bytes calldata swapData1
    ) external payable returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);

    /// @notice Rebalances a position to a new tick range
    /// @param params The params of the target position after rebalance
    /// token0 The address of the token0 for a specific pool
    /// token1 The address of the token1 for a specific pool
    /// fee The fee associated with the pool
    /// tickLower The lower tick of the position in which to add liquidity
    /// tickUpper The upper tick of the position in which to add liquidity
    /// amount0Desired The desired amount of token0 to be spent
    /// amount1Desired The desired amount of token1 to be spent
    /// amount0Min The minimum amount of token0 to spend, which serves as a slippage check
    /// amount1Min The minimum amount of token1 to spend, which serves as a slippage check
    /// recipient The recipient of the minted position
    /// deadline The time by which the transaction must be included to effect the change
    /// @param tokenId The ID of the position to rebalance
    /// @param swapData The address of the external router and call data
    /// @param isCollect If true, collect fees to owner's wallet. If false, roll fees into new position
    /// @param zapOutParams The zap out params
    /// @return newTokenId The ID of the new position
    /// @return liquidity The amount of liquidity in the new position
    /// @return amount0 The amount of token0 in the new position
    /// @return amount1 The amount of token1 in the new position
    function rebalance(
        IUniV3NPM.MintParams memory params,
        uint256 tokenId,
        bytes calldata swapData,
        bool isCollect,
        IAutomanCommon.ZapOutParams calldata zapOutParams
    ) external returns (uint256 newTokenId, uint128 liquidity, uint256 amount0, uint256 amount1);

    /// @notice Rebalances a position to a new tick range using permit
    /// @param params The params of the target position after rebalance
    /// token0 The address of the token0 for a specific pool
    /// token1 The address of the token1 for a specific pool
    /// fee The fee associated with the pool
    /// tickLower The lower tick of the position in which to add liquidity
    /// tickUpper The upper tick of the position in which to add liquidity
    /// amount0Desired The desired amount of token0 to be spent
    /// amount1Desired The desired amount of token1 to be spent
    /// amount0Min The minimum amount of token0 to spend, which serves as a slippage check
    /// amount1Min The minimum amount of token1 to spend, which serves as a slippage check
    /// recipient The recipient of the minted position
    /// deadline The time by which the transaction must be included to effect the change
    /// @param tokenId The ID of the position to rebalance
    /// @param swapData The address of the external router and call data
    /// @param isCollect If true, collect fees to owner's wallet. If false, roll fees into new position
    /// @param zapOutParams The zap out params
    /// @param permit The signature permit
    /// @return newTokenId The ID of the new position
    /// @return liquidity The amount of liquidity in the new position
    /// @return amount0 The amount of token0 in the new position
    /// @return amount1 The amount of token1 in the new position
    function rebalance(
        IUniV3NPM.MintParams memory params,
        uint256 tokenId,
        bytes calldata swapData,
        bool isCollect,
        IAutomanCommon.ZapOutParams calldata zapOutParams,
        IAutomanCommon.Permit calldata permit
    ) external returns (uint256 newTokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
}

interface IAutomanSlipStreamMintRebalance {
    /// @notice Creates a new position wrapped in a NFT using optimal swap
    /// @dev Call this when the pool does exist and is initialized. Note that if the pool is created but not initialized
    /// a method does not exist, i.e. the pool is assumed to be initialized.
    /// @param params The params necessary to mint a position, encoded as `MintParams` in calldata
    /// token0 The address of the token0 for a specific pool
    /// token1 The address of the token1 for a specific pool
    /// tickSpacing The tick spacing associated with the pool
    /// tickLower The lower tick of the position in which to add liquidity
    /// tickUpper The upper tick of the position in which to add liquidity
    /// amount0Desired The desired amount of token0 to be spent
    /// amount1Desired The desired amount of token1 to be spent
    /// amount0Min The minimum amount of token0 to spend, which serves as a slippage check
    /// amount1Min The minimum amount of token1 to spend, which serves as a slippage check
    /// recipient The recipient of the minted position
    /// deadline The time by which the transaction must be included to effect the change
    /// @param swapData The address of the external router and call data
    /// @param token0FeeAmount The amount of token0 to send to feeCollector
    /// @param token1FeeAmount The amount of token1 to send to feeCollector
    /// @return tokenId The ID of the token that represents the minted position
    /// @return liquidity The amount of liquidity for this position
    /// @return amount0 The amount of token0 spent
    /// @return amount1 The amount of token1 spent
    function mintOptimal(
        ISlipStreamNPM.MintParams memory params,
        bytes calldata swapData,
        uint256 token0FeeAmount,
        uint256 token1FeeAmount
    ) external payable returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);

    /// @notice Creates a new position wrapped in a NFT using a single tokenIn.
    /// @dev Call this when the pool does exist and is initialized. Note that if the pool is created but not initialized
    /// a method does not exist, i.e. the pool is assumed to be initialized.
    /// @param params The params necessary to mint a position, encoded as `MintParams` in calldata
    /// token0 The address of the token0 for a specific pool
    /// token1 The address of the token1 for a specific pool
    /// tickSpacing The tickSpacing associated with the pool
    /// tickLower The lower tick of the position in which to add liquidity
    /// tickUpper The upper tick of the position in which to add liquidity
    /// amount0Desired The amount of tokenIn to swap for token0
    /// amount1Desired The amount of tokenIn to swap for token1
    /// amount0Min The minimum amount of token0 to spend, which serves as a slippage check
    /// amount1Min The minimum amount of token1 to spend, which serves as a slippage check
    /// recipient The recipient of the minted position
    /// deadline The time by which the transaction must be included to effect the change
    /// @param tokenIn The tokenIn to swap for token0 and token1
    /// @param tokenInFeeAmount The amount of tokenIn to send to feeCollector
    /// @param swapData0 The swap data for swapping from tokenIn to token0
    /// @param swapData1 The swap data for swapping from tokenIn to token1
    /// @return tokenId The ID of the token that represents the minted position
    /// @return liquidity The amount of liquidity for this position
    /// @return amount0 The amount of token0 spent
    /// @return amount1 The amount of token1 spent
    function mintFromTokenIn(
        ISlipStreamNPM.MintParams memory params,
        address tokenIn,
        uint256 tokenInFeeAmount,
        bytes calldata swapData0,
        bytes calldata swapData1
    ) external payable returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);

    /// @notice Rebalances a position to a new tick range
    /// @param params The params of the target position after rebalance
    /// token0 The address of the token0 for a specific pool
    /// token1 The address of the token1 for a specific pool
    /// tickSpacing The tick spacing associated with the pool
    /// tickLower The lower tick of the position in which to add liquidity
    /// tickUpper The upper tick of the position in which to add liquidity
    /// amount0Desired The desired amount of token0 to be spent
    /// amount1Desired The desired amount of token1 to be spent
    /// amount0Min The minimum amount of token0 to spend, which serves as a slippage check
    /// amount1Min The minimum amount of token1 to spend, which serves as a slippage check
    /// recipient The recipient of the minted position
    /// deadline The time by which the transaction must be included to effect the change
    /// @param tokenId The ID of the position to rebalance
    /// @param swapData The address of the external router and call data
    /// @param isCollect If true, collect fees to owner's wallet. If false, roll fees into new position
    /// @param zapOutParams The zap out params
    /// @return newTokenId The ID of the new position
    /// @return liquidity The amount of liquidity in the new position
    /// @return amount0 The amount of token0 in the new position
    /// @return amount1 The amount of token1 in the new position
    function rebalance(
        ISlipStreamNPM.MintParams memory params,
        uint256 tokenId,
        bytes calldata swapData,
        bool isCollect,
        IAutomanCommon.ZapOutParams calldata zapOutParams
    ) external returns (uint256 newTokenId, uint128 liquidity, uint256 amount0, uint256 amount1);

    /// @notice Rebalances a position to a new tick range using permit
    /// @param params The params of the target position after rebalance
    /// token0 The address of the token0 for a specific pool
    /// token1 The address of the token1 for a specific pool
    /// tickSpacing The tick spacing associated with the pool
    /// tickLower The lower tick of the position in which to add liquidity
    /// tickUpper The upper tick of the position in which to add liquidity
    /// amount0Desired The desired amount of token0 to be spent
    /// amount1Desired The desired amount of token1 to be spent
    /// amount0Min The minimum amount of token0 to spend, which serves as a slippage check
    /// amount1Min The minimum amount of token1 to spend, which serves as a slippage check
    /// recipient The recipient of the minted position
    /// deadline The time by which the transaction must be included to effect the change
    /// @param tokenId The ID of the position to rebalance
    /// @param swapData The address of the external router and call data
    /// @param isCollect If true, collect fees to owner's wallet. If false, roll fees into new position
    /// @param zapOutParams The zap out params
    /// @param permit The signature permit
    /// @return newTokenId The ID of the new position
    /// @return liquidity The amount of liquidity in the new position
    /// @return amount0 The amount of token0 in the new position
    /// @return amount1 The amount of token1 in the new position
    function rebalance(
        ISlipStreamNPM.MintParams memory params,
        uint256 tokenId,
        bytes calldata swapData,
        bool isCollect,
        IAutomanCommon.ZapOutParams calldata zapOutParams,
        IAutomanCommon.Permit calldata permit
    ) external returns (uint256 newTokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
}

interface IUniV3Automan is IAutomanCommon, IAutomanUniV3MintRebalance, IUniV3Immutables, IUniswapV3SwapCallback {}

interface IPCSV3Automan is IAutomanCommon, IAutomanUniV3MintRebalance, IPCSV3Immutables, IPancakeV3SwapCallback {}

interface ISlipStreamAutoman is
    IAutomanCommon,
    IAutomanSlipStreamMintRebalance,
    IUniV3Immutables,
    IUniswapV3SwapCallback
{}
