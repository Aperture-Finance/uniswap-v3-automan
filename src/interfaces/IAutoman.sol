// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "@pancakeswap/v3-core/contracts/interfaces/callback/IPancakeV3SwapCallback.sol";
import "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";
import {INonfungiblePositionManager as INPM} from "@aperture_finance/uni-v3-lib/src/interfaces/INonfungiblePositionManager.sol";
import {V3PoolCallee} from "@aperture_finance/uni-v3-lib/src/PoolCaller.sol";
import {IPCSV3Immutables, IUniV3Immutables} from "./IImmutables.sol";

/// @title Interface for the Uniswap v3 Automation Manager
interface IAutoman {
    /************************************************
     *  EVENTS
     ***********************************************/

    event FeeConfigSet(address feeCollector, uint96 feeLimitPips);
    event ControllersSet(address[] controllers, bool[] statuses);
    event SwapRoutersSet(address[] routers, bool[] statuses);
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
    error InvalidSwapRouter();
    error NotWhitelistedRouter();
    error InsufficientAmount();
    error FeeLimitExceeded();

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

    /// @notice Creates a new position wrapped in a NFT
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
    /// @return tokenId The ID of the token that represents the minted position
    /// @return liquidity The amount of liquidity for this position
    /// @return amount0 The amount of token0 spent
    /// @return amount1 The amount of token1 spent
    function mint(
        INPM.MintParams memory params
    ) external payable returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);

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
    /// @return tokenId The ID of the token that represents the minted position
    /// @return liquidity The amount of liquidity for this position
    /// @return amount0 The amount of token0 spent
    /// @return amount1 The amount of token1 spent
    function mintOptimal(
        INPM.MintParams memory params,
        bytes calldata swapData
    ) external payable returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);

    /// @notice Increases the amount of liquidity in a position, with tokens paid by the `msg.sender`
    /// @dev Anyone can increase the liquidity of a position, but the caller must pay the tokens
    /// @param params tokenId The ID of the token for which liquidity is being increased,
    /// amount0Desired The desired amount of token0 to be spent,
    /// amount1Desired The desired amount of token1 to be spent,
    /// amount0Min The minimum amount of token0 to spend, which serves as a slippage check,
    /// amount1Min The minimum amount of token1 to spend, which serves as a slippage check,
    /// deadline The time by which the transaction must be included to effect the change
    /// @return liquidity The new liquidity amount as a result of the increase
    /// @return amount0 The amount of token0 to achieve resulting liquidity
    /// @return amount1 The amount of token1 to achieve resulting liquidity
    function increaseLiquidity(
        INPM.IncreaseLiquidityParams memory params
    ) external payable returns (uint128 liquidity, uint256 amount0, uint256 amount1);

    /// @notice Increases the amount of liquidity in a position using optimal swap
    /// @dev Anyone can increase the liquidity of a position, but the caller must pay the tokens
    /// @param params tokenId The ID of the token for which liquidity is being increased,
    /// amount0Desired The desired amount of token0 to be spent,
    /// amount1Desired The desired amount of token1 to be spent,
    /// amount0Min The minimum amount of token0 to spend, which serves as a slippage check,
    /// amount1Min The minimum amount of token1 to spend, which serves as a slippage check,
    /// deadline The time by which the transaction must be included to effect the change
    /// @param swapData The address of the external router and call data
    /// @return liquidity The new liquidity amount as a result of the increase
    /// @return amount0 The amount of token0 to achieve resulting liquidity
    /// @return amount1 The amount of token1 to achieve resulting liquidity
    function increaseLiquidityOptimal(
        INPM.IncreaseLiquidityParams memory params,
        bytes calldata swapData
    ) external payable returns (uint128 liquidity, uint256 amount0, uint256 amount1);

    /// @notice Decreases the amount of liquidity in a position and accounts it to the position
    /// @dev Slippage check is delegated to `NonfungiblePositionManager` via `DecreaseLiquidityParams`.
    /// It is applied on the principal amounts excluding trading fees.
    /// @param params tokenId The ID of the token for which liquidity is being decreased,
    /// liquidity The amount by which liquidity will be decreased,
    /// amount0Min The minimum amount of token0 that should be accounted for the burned liquidity,
    /// amount1Min The minimum amount of token1 that should be accounted for the burned liquidity,
    /// deadline The time by which the transaction must be included to effect the change
    /// @param feePips The fee in pips to be collected
    /// @return amount0 The amount of token0 returned minus fees
    /// @return amount1 The amount of token1 returned minus fees
    function decreaseLiquidity(
        INPM.DecreaseLiquidityParams memory params,
        uint256 feePips
    ) external returns (uint256 amount0, uint256 amount1);

    /// @notice Decreases the amount of liquidity in a position and accounts it to the position using permit
    /// @dev Slippage check is delegated to `NonfungiblePositionManager` via `DecreaseLiquidityParams`.
    /// It is applied on the principal amounts excluding trading fees.
    /// @param params tokenId The ID of the token for which liquidity is being decreased,
    /// liquidity The amount by which liquidity will be decreased,
    /// amount0Min The minimum amount of token0 that should be accounted for the burned liquidity,
    /// amount1Min The minimum amount of token1 that should be accounted for the burned liquidity,
    /// deadline The time by which the transaction must be included to effect the change
    /// @param feePips The fee in pips to be collected
    /// @param permitDeadline The deadline of the permit signature
    /// @param v The recovery byte of the signature
    /// @param r Half of the ECDSA signature pair
    /// @param s Half of the ECDSA signature pair
    /// @return amount0 The amount of token0 returned minus fees
    /// @return amount1 The amount of token1 returned minus fees
    function decreaseLiquidity(
        INPM.DecreaseLiquidityParams memory params,
        uint256 feePips,
        uint256 permitDeadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 amount0, uint256 amount1);

    /// @notice Decreases the amount of liquidity in a position and swaps to a single token
    /// @dev Slippage check is enforced by specifying `amount0Min` when `token0` is the target token
    /// and `amount1Min` otherwise, applied after transaction fees.
    /// @param params tokenId The ID of the token for which liquidity is being decreased,
    /// liquidity The amount by which liquidity will be decreased,
    /// amount0Min The minimum amount of token0 that should be accounted for the burned liquidity,
    /// amount1Min The minimum amount of token1 that should be accounted for the burned liquidity,
    /// deadline The time by which the transaction must be included to effect the change
    /// @param zeroForOne True if token0 is being swapped for token1, false otherwise
    /// @param feePips The fee in pips to be collected
    /// @param swapData The address of the external router and call data
    /// @return amount The total amount of desired token returned minus fees
    function decreaseLiquiditySingle(
        INPM.DecreaseLiquidityParams memory params,
        bool zeroForOne,
        uint256 feePips,
        bytes calldata swapData
    ) external returns (uint256 amount);

    /// @notice Decreases the amount of liquidity in a position and swaps to a single token using permit
    /// @dev Slippage check is enforced by specifying `amount0Min` when `token0` is the target token
    /// and `amount1Min` otherwise, applied after transaction fees.
    /// @param params tokenId The ID of the token for which liquidity is being decreased,
    /// liquidity The amount by which liquidity will be decreased,
    /// amount0Min The minimum amount of token0 that should be accounted for the burned liquidity,
    /// amount1Min The minimum amount of token1 that should be accounted for the burned liquidity,
    /// deadline The time by which the transaction must be included to effect the change
    /// @param zeroForOne True if token0 is being swapped for token1, false otherwise
    /// @param feePips The fee in pips to be collected
    /// @param swapData The address of the external router and call data
    /// @param permitDeadline The deadline of the permit signature
    /// @param v The recovery byte of the signature
    /// @param r Half of the ECDSA signature pair
    /// @param s Half of the ECDSA signature pair
    /// @return amount The total amount of desired token returned minus fees
    function decreaseLiquiditySingle(
        INPM.DecreaseLiquidityParams memory params,
        bool zeroForOne,
        uint256 feePips,
        bytes calldata swapData,
        uint256 permitDeadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 amount);

    /// @notice Removes all liquidity from a position
    /// @dev Slippage check is delegated to `NonfungiblePositionManager` via `DecreaseLiquidityParams`.
    /// It is applied on the principal amounts excluding trading fees.
    /// @param params tokenId The ID of the token for which liquidity is being removed,
    /// amount0Min The minimum amount of token0 that should be accounted for the burned liquidity,
    /// amount1Min The minimum amount of token1 that should be accounted for the burned liquidity,
    /// deadline The time by which the transaction must be included to effect the change
    /// @param feePips The fee in pips to be collected
    /// @return amount0 The amount of token0 returned minus fees
    /// @return amount1 The amount of token1 returned minus fees
    function removeLiquidity(
        INPM.DecreaseLiquidityParams memory params,
        uint256 feePips
    ) external returns (uint256 amount0, uint256 amount1);

    /// @notice Removes all liquidity from a position using permit
    /// @dev Slippage check is delegated to `NonfungiblePositionManager` via `DecreaseLiquidityParams`.
    /// It is applied on the principal amounts excluding trading fees.
    /// @param params tokenId The ID of the token for which liquidity is being removed,
    /// amount0Min The minimum amount of token0 that should be accounted for the burned liquidity,
    /// amount1Min The minimum amount of token1 that should be accounted for the burned liquidity,
    /// deadline The time by which the transaction must be included to effect the change
    /// @param feePips The fee in pips to be collected
    /// @param permitDeadline The deadline of the permit signature
    /// @param v The recovery byte of the signature
    /// @param r Half of the ECDSA signature pair
    /// @param s Half of the ECDSA signature pair
    /// @return amount0 The amount of token0 returned minus fees
    /// @return amount1 The amount of token1 returned minus fees
    function removeLiquidity(
        INPM.DecreaseLiquidityParams memory params,
        uint256 feePips,
        uint256 permitDeadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 amount0, uint256 amount1);

    /// @notice Removes all liquidity from a position and swaps to a single token
    /// @dev Slippage check is enforced by specifying `amount0Min` when `token0` is the target token
    /// and `amount1Min` otherwise, applied after transaction fees.
    /// @param params tokenId The ID of the token for which liquidity is being removed,
    /// amount0Min The minimum amount of token0 that should be accounted for the burned liquidity,
    /// amount1Min The minimum amount of token1 that should be accounted for the burned liquidity,
    /// deadline The time by which the transaction must be included to effect the change
    /// @param zeroForOne True if token0 is being swapped for token1, false otherwise
    /// @param feePips The fee in pips to be collected
    /// @param swapData The address of the external router and call data
    /// @return amount The total amount of desired token returned minus fees
    function removeLiquiditySingle(
        INPM.DecreaseLiquidityParams memory params,
        bool zeroForOne,
        uint256 feePips,
        bytes calldata swapData
    ) external returns (uint256 amount);

    /// @notice Removes all liquidity from a position and swaps to a single token using permit
    /// @dev Slippage check is enforced by specifying `amount0Min` when `token0` is the target token
    /// and `amount1Min` otherwise, applied after transaction fees.
    /// @param params tokenId The ID of the token for which liquidity is being removed,
    /// amount0Min The minimum amount of token0 that should be accounted for the burned liquidity,
    /// amount1Min The minimum amount of token1 that should be accounted for the burned liquidity,
    /// deadline The time by which the transaction must be included to effect the change
    /// @param zeroForOne True if token0 is being swapped for token1, false otherwise
    /// @param feePips The fee in pips to be collected
    /// @param swapData The address of the external router and call data
    /// @param permitDeadline The deadline of the permit signature
    /// @param v The recovery byte of the signature
    /// @param r Half of the ECDSA signature pair
    /// @param s Half of the ECDSA signature pair
    /// @return amount The total amount of desired token returned minus fees
    function removeLiquiditySingle(
        INPM.DecreaseLiquidityParams memory params,
        bool zeroForOne,
        uint256 feePips,
        bytes calldata swapData,
        uint256 permitDeadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 amount);

    /// @notice Reinvests all fees owed to a specific position to the same position using optimal swap
    /// @param params tokenId The ID of the token for which liquidity is being increased,
    /// amount0Desired The desired amount of token0 to be spent,
    /// amount1Desired The desired amount of token1 to be spent,
    /// amount0Min The minimum amount of token0 to spend, which serves as a slippage check,
    /// amount1Min The minimum amount of token1 to spend, which serves as a slippage check,
    /// deadline The time by which the transaction must be included to effect the change
    /// @param feePips The fee in pips to be collected
    /// @param swapData The address of the external router and call data
    /// @return liquidity The new liquidity amount as a result of the increase
    /// @return amount0 The amount of token0 to achieve resulting liquidity
    /// @return amount1 The amount of token1 to achieve resulting liquidity
    function reinvest(
        INPM.IncreaseLiquidityParams memory params,
        uint256 feePips,
        bytes calldata swapData
    ) external returns (uint128 liquidity, uint256 amount0, uint256 amount1);

    /// @notice Reinvests all fees owed to a specific position to the same position using optimal swap and permit
    /// @param params tokenId The ID of the token for which liquidity is being increased,
    /// amount0Desired The desired amount of token0 to be spent,
    /// amount1Desired The desired amount of token1 to be spent,
    /// amount0Min The minimum amount of token0 to spend, which serves as a slippage check,
    /// amount1Min The minimum amount of token1 to spend, which serves as a slippage check,
    /// deadline The time by which the transaction must be included to effect the change
    /// @param feePips The fee in pips to be collected
    /// @param swapData The address of the external router and call data
    /// @param permitDeadline The deadline of the permit signature
    /// @param v The recovery byte of the signature
    /// @param r Half of the ECDSA signature pair
    /// @param s Half of the ECDSA signature pair
    /// @return liquidity The new liquidity amount as a result of the increase
    /// @return amount0 The amount of token0 to achieve resulting liquidity
    /// @return amount1 The amount of token1 to achieve resulting liquidity
    function reinvest(
        INPM.IncreaseLiquidityParams memory params,
        uint256 feePips,
        bytes calldata swapData,
        uint256 permitDeadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint128 liquidity, uint256 amount0, uint256 amount1);

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
    /// @param feePips The fee in pips to be collected
    /// @param swapData The address of the external router and call data
    /// @return newTokenId The ID of the new position
    /// @return liquidity The amount of liquidity in the new position
    /// @return amount0 The amount of token0 in the new position
    /// @return amount1 The amount of token1 in the new position
    function rebalance(
        INPM.MintParams memory params,
        uint256 tokenId,
        uint256 feePips,
        bytes calldata swapData
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
    /// @param feePips The fee in pips to be collected
    /// @param swapData The address of the external router and call data
    /// @param permitDeadline The deadline of the permit signature
    /// @param v The recovery byte of the signature
    /// @param r Half of the ECDSA signature pair
    /// @param s Half of the ECDSA signature pair
    /// @return newTokenId The ID of the new position
    /// @return liquidity The amount of liquidity in the new position
    /// @return amount0 The amount of token0 in the new position
    /// @return amount1 The amount of token1 in the new position
    function rebalance(
        INPM.MintParams memory params,
        uint256 tokenId,
        uint256 feePips,
        bytes calldata swapData,
        uint256 permitDeadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 newTokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
}

interface IUniV3Automan is IAutoman, IUniV3Immutables, IUniswapV3SwapCallback {}
interface IPCSV3Automan is IAutoman, IPCSV3Immutables, IPancakeV3SwapCallback {}
