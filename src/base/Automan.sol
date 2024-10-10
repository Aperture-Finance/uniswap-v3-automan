// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "solady/src/utils/SafeTransferLib.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-periphery/contracts/interfaces/IPoolInitializer.sol";
import {ICommonNonfungiblePositionManager as INPM, IUniswapV3NonfungiblePositionManager as IUniV3NPM} from "@aperture_finance/uni-v3-lib/src/interfaces/IUniswapV3NonfungiblePositionManager.sol";
import {LiquidityAmounts} from "@aperture_finance/uni-v3-lib/src/LiquidityAmounts.sol";
import {NPMCaller, Position} from "@aperture_finance/uni-v3-lib/src/NPMCaller.sol";
import {PoolKey} from "@aperture_finance/uni-v3-lib/src/PoolKey.sol";
import {SwapRouter} from "./SwapRouter.sol";
import {IAutomanCommon, IAutomanUniV3MintRebalance} from "../interfaces/IAutoman.sol";
import {FullMath, OptimalSwap, TickMath, V3PoolCallee} from "../libraries/OptimalSwap.sol";

/// @title Automation manager for UniV3-like liquidity positions with built-in optimal swap algorithm
/// @author Aperture Finance
/// @dev The validity of the tokens in `poolKey` and the pool contract computed from it is not checked here.
/// However if they are invalid, pool `swap`, `burn` and `mint` will revert here or in `NonfungiblePositionManager`.
abstract contract Automan is Ownable, SwapRouter, IAutomanCommon, IAutomanUniV3MintRebalance {
    using SafeTransferLib for address;
    using FullMath for uint256;
    using TickMath for int24;

    uint256 internal constant MAX_FEE_PIPS = 1e18;

    /************************************************
     *  STATE VARIABLES
     ***********************************************/
    FeeConfig public feeConfig;
    /// @notice The address list that can perform automation
    mapping(address => bool) public isController;
    /// @notice The list of whitelisted routers
    mapping(address => bool) public isWhiteListedSwapRouter;

    /************************************************
     *  ACCESS CONTROL
     ***********************************************/

    /// @dev Reverts if the caller is not a controller or the position owner
    function checkAuthorizedForToken(uint256 tokenId) internal view {
        if (isController[msg.sender]) return;
        if (msg.sender != NPMCaller.ownerOf(npm, tokenId)) revert NotApproved();
    }

    /// @dev Reverts if the fee is greater than the limit
    function checkFeeSanity(uint256 feeAmount, uint256 collectableAmount) internal view {
        if (collectableAmount < feeAmount) revert InsufficientAmount();
        if (collectableAmount != 0) {
            uint256 feePips = feeAmount.mulDiv(MAX_FEE_PIPS, collectableAmount);
            if (feePips > feeConfig.feeLimitPips) revert FeeLimitExceeded();
        }
    }

    /// @dev Reverts if the router is not whitelisted
    /// @param swapData The address of the external router and call data
    function checkRouter(bytes calldata swapData) internal view returns (address router) {
        assembly {
            router := shr(96, calldataload(swapData.offset))
        }
        if (!isWhiteListedSwapRouter[router]) revert NotWhitelistedRouter();
    }

    /************************************************
     *  SETTERS
     ***********************************************/

    /// @notice Set the fee limit and collector
    /// @param _feeConfig The new fee configuration
    function setFeeConfig(FeeConfig calldata _feeConfig) external payable onlyOwner {
        require(_feeConfig.feeLimitPips < MAX_FEE_PIPS);
        require(_feeConfig.feeCollector != address(0));
        feeConfig = _feeConfig;
        emit FeeConfigSet(_feeConfig.feeCollector, _feeConfig.feeLimitPips);
    }

    /// @notice Set addresses that can perform automation
    function setControllers(address[] calldata controllers, bool[] calldata statuses) external payable onlyOwner {
        uint256 len = controllers.length;
        require(len == statuses.length);
        unchecked {
            for (uint256 i; i < len; ++i) {
                isController[controllers[i]] = statuses[i];
            }
        }
        emit ControllersSet(controllers, statuses);
    }

    /// @notice Set whitelisted swap routers
    /// @dev If `NonfungiblePositionManager` is a whitelisted router, this contract may approve arbitrary address to
    /// spend NFTs it has been approved of.
    /// @dev If an ERC20 token is whitelisted as a router, `transferFrom` may be called to drain tokens approved
    /// to this contract during `mintOptimal` or `increaseLiquidityOptimal`.
    /// @dev If a malicious router is whitelisted and called without slippage control, the caller may lose tokens in an
    /// external swap. The router can't, however, drain ERC20 or ERC721 tokens which have been approved by other users
    /// to this contract. Because this contract doesn't contain `transferFrom` with random `from` address like that in
    /// SushiSwap's [`RouteProcessor2`](https://rekt.news/sushi-yoink-rekt/).
    function setSwapRouters(address[] calldata routers, bool[] calldata statuses) external payable onlyOwner {
        uint256 len = routers.length;
        require(len == statuses.length);
        unchecked {
            for (uint256 i; i < len; ++i) {
                address router = routers[i];
                if (statuses[i]) {
                    // revert if `router` is `NonfungiblePositionManager`
                    if (router == address(npm)) revert InvalidSwapRouter();
                    // revert if `router` is an ERC20 or not a contract
                    //slither-disable-next-line reentrancy-no-eth
                    (bool success, ) = router.call(abi.encodeCall(IERC20.approve, (address(npm), 0)));
                    if (success) revert InvalidSwapRouter();
                    isWhiteListedSwapRouter[router] = true;
                } else {
                    delete isWhiteListedSwapRouter[router];
                }
            }
        }
        emit SwapRoutersSet(routers, statuses);
    }

    /************************************************
     *  GETTERS
     ***********************************************/

    /// @dev Wrapper around `INonfungiblePositionManager.positions`
    /// @param tokenId The ID of the token that represents the position
    /// @return Position token0 The address of the token0 for a specific pool
    /// token1 The address of the token1 for a specific pool
    /// feeTier The fee tier of the pool
    /// tickLower The lower end of the tick range for the position
    /// tickUpper The higher end of the tick range for the position
    /// liquidity The liquidity of the position
    function _positions(uint256 tokenId) internal view returns (Position memory) {
        return NPMCaller.positions(npm, tokenId);
    }

    /// @notice Cast `Position` to `PoolKey`
    /// @dev Solidity assigns free memory to structs when they are declared, which is unnecessary in this case.
    /// But there is nothing we can do unless the memory of a struct is only assigned when using the `new` keyword.
    function castPoolKey(Position memory pos) internal pure returns (PoolKey memory poolKey) {
        assembly ("memory-safe") {
            // `PoolKey` is a subset of `Position`
            poolKey := pos
        }
    }

    /// @notice Cast `MintParams` to `PoolKey`
    function castPoolKey(IUniV3NPM.MintParams memory params) internal pure returns (PoolKey memory poolKey) {
        assembly ("memory-safe") {
            // `PoolKey` is a subset of `MintParams`
            poolKey := params
        }
    }

    /// @inheritdoc IAutomanCommon
    function getOptimalSwap(
        V3PoolCallee pool,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) external view returns (uint256 amountIn, uint256 amountOut, bool zeroForOne, uint160 sqrtPriceX96) {
        return OptimalSwap.getOptimalSwap(pool, tickLower, tickUpper, amount0Desired, amount1Desired);
    }

    /************************************************
     *  INTERNAL ACTIONS
     ***********************************************/

    /// @dev Make a swap using a v3 pool directly or through an external router
    /// @param poolKey The pool key containing the token addresses and fee tier
    /// @param amountIn The amount of token to be swapped
    /// @param zeroForOne The direction of the swap, true for token0 to token1, false for token1 to token0
    /// @param swapData The address of the external router and call data
    /// @return amountOut The amount of token received after swap
    function _swap(
        PoolKey memory poolKey,
        uint256 amountIn,
        bool zeroForOne,
        bytes calldata swapData
    ) private returns (uint256 amountOut) {
        if (swapData.length == 0) {
            amountOut = _poolSwap(poolKey, computeAddressSorted(poolKey), amountIn, zeroForOne);
        } else {
            address router = checkRouter(swapData);
            amountOut = _routerSwap(poolKey, router, zeroForOne, swapData);
        }
    }

    /// @dev Swap tokens to the optimal ratio to add liquidity and approve npm to spend
    /// @param poolKey The pool key containing the token addresses and fee tier
    /// @param tickLower The lower tick of the position in which to add liquidity
    /// @param tickUpper The upper tick of the position in which to add liquidity
    /// @param amount0Desired The desired amount of token0 to be spent
    /// @param amount1Desired The desired amount of token1 to be spent
    /// @return amount0 The amount of token0 after swap
    /// @return amount1 The amount of token1 after swap
    function _optimalSwap(
        PoolKey memory poolKey,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Desired,
        uint256 amount1Desired,
        bytes calldata swapData
    ) private returns (uint256 amount0, uint256 amount1) {
        if (swapData.length == 0) {
            // Swap with the v3 pool directly
            (amount0, amount1) = _optimalSwapWithPool(poolKey, tickLower, tickUpper, amount0Desired, amount1Desired);
        } else {
            // Swap with a whitelisted router
            address router = checkRouter(swapData);
            (amount0, amount1) = _optimalSwapWithRouter(
                poolKey,
                router,
                tickLower,
                tickUpper,
                amount0Desired,
                amount1Desired,
                swapData
            );
        }
        // Approve the v3 position manager to spend the tokens
        if (amount0 != 0) poolKey.token0.safeApprove(address(npm), amount0);
        if (amount1 != 0) poolKey.token1.safeApprove(address(npm), amount1);
    }

    /// @notice Burns a token ID, which deletes it from the NFT contract. The token must have 0 liquidity and all tokens
    /// must be collected first.
    /// @param tokenId The ID of the token that is being burned
    function _burn(uint256 tokenId) private {
        return NPMCaller.burn(npm, tokenId);
    }

    /// @notice Collects tokens owed for a given token ID to this contract
    /// @param tokenId The ID of the NFT for which tokens are being collected
    /// @return amount0 The amount of fees collected in token0
    /// @return amount1 The amount of fees collected in token1
    function _collect(uint256 tokenId) private returns (uint256 amount0, uint256 amount1) {
        return NPMCaller.collect(npm, tokenId, address(this));
    }

    /// @dev Internal function to mint and refund
    function _mint(
        IUniV3NPM.MintParams memory params
    ) private returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) {
        (tokenId, liquidity, amount0, amount1) = NPMCaller.mint(npm, params);
        address recipient = params.recipient;
        uint256 amount0Desired = params.amount0Desired;
        uint256 amount1Desired = params.amount1Desired;
        // Refund any surplus value to the recipient
        unchecked {
            if (amount0 < amount0Desired) {
                address token0 = params.token0;
                token0.safeApprove(address(npm), 0);
                refund(token0, recipient, amount0Desired - amount0);
            }
            if (amount1 < amount1Desired) {
                address token1 = params.token1;
                token1.safeApprove(address(npm), 0);
                refund(token1, recipient, amount1Desired - amount1);
            }
        }
    }

    /// @dev Internal increase liquidity abstraction, tokens already in correct ratio.
    function _increaseLiquidity(
        INPM.IncreaseLiquidityParams memory params,
        address token0,
        address token1
    ) private returns (uint128 liquidity, uint256 amount0, uint256 amount1) {
        (liquidity, amount0, amount1) = NPMCaller.increaseLiquidity(npm, params);
        uint256 amount0Desired = params.amount0Desired;
        uint256 amount1Desired = params.amount1Desired;
        // Refund any surplus value to the caller
        unchecked {
            if (amount0 < amount0Desired) {
                token0.safeApprove(address(npm), 0);
                refund(token0, msg.sender, amount0Desired - amount0);
            }
            if (amount1 < amount1Desired) {
                token1.safeApprove(address(npm), 0);
                refund(token1, msg.sender, amount1Desired - amount1);
            }
        }
    }

    /// @dev Internal collect gas and aperture fees abstraction
    /// @param token0 The address of token0
    /// @param token1 The address of token1
    /// @param token0DeductibleAmount The amount of token0 collected or zapped in that can deduct fees
    /// @param token1DeductibleAmount The amount of token1 collected or zapped in that can deduct fees
    /// @param token0FeeAmount The amount of token0 fees to be deducted
    /// @param token1FeeAmount The amount of token1 fees to be deducted
    /// @return token0DeductibleAmount The amount of token0 after deducting fees
    /// @return token1DeductibleAmount The amount of token1 after deducting fees
    function _deductFees(
        address token0,
        address token1,
        uint256 token0DeductibleAmount,
        uint256 token1DeductibleAmount,
        uint256 token0FeeAmount,
        uint256 token1FeeAmount
    ) private returns (uint256, uint256) {
        // Calculations outside mulDiv won't overflow.
        unchecked {
            checkFeeSanity(token0FeeAmount, token0DeductibleAmount);
            checkFeeSanity(token1FeeAmount, token1DeductibleAmount);
            address _feeCollector = feeConfig.feeCollector;
            if (token0FeeAmount != 0) {
                token0DeductibleAmount -= token0FeeAmount;
                refund(token0, _feeCollector, token0FeeAmount);
            }
            if (token1FeeAmount != 0) {
                token1DeductibleAmount -= token1FeeAmount;
                refund(token1, _feeCollector, token1FeeAmount);
            }
        }
        return (token0DeductibleAmount, token1DeductibleAmount);
    }

    /// @dev Collect the tokens owed, deduct gas and aperture fees and send it to the fee collector
    /// @return amount0 The amount of token0 after fees
    /// @return amount1 The amount of token1 after fees
    function _collectDeductFees(
        uint256 tokenId,
        address token0,
        address token1,
        uint256 token0FeeAmount,
        uint256 token1FeeAmount
    ) private returns (uint256, uint256) {
        // Collect the fees collected from providing liquidity.
        (uint256 amount0Collected, uint256 amount1Collected) = _collect(tokenId);
        return _deductFees(token0, token1, amount0Collected, amount1Collected, token0FeeAmount, token1FeeAmount);
    }

    /// @dev Internal decrease liquidity abstraction
    function _decreaseLiquidity(
        INPM.DecreaseLiquidityParams memory params,
        uint256 token0FeeAmount,
        uint256 token1FeeAmount
    ) private returns (uint256 amount0, uint256 amount1) {
        uint256 tokenId = params.tokenId;
        Position memory pos = _positions(tokenId);
        // Slippage check is delegated to `NonfungiblePositionManager` via `DecreaseLiquidityParams`.
        NPMCaller.decreaseLiquidity(npm, params);
        // Collect the tokens owed and deduct gas and aperture fees.
        (amount0, amount1) = _collectDeductFees(tokenId, pos.token0, pos.token1, token0FeeAmount, token1FeeAmount);
        // Send the remaining amounts to the position owner
        address owner = NPMCaller.ownerOf(npm, tokenId);
        if (amount0 != 0) refund(pos.token0, owner, amount0);
        if (amount1 != 0) refund(pos.token1, owner, amount1);
    }

    /// @dev Decrease liquidity and swap the tokens to a single token
    function _decreaseCollectSingle(
        INPM.DecreaseLiquidityParams memory params,
        Position memory pos,
        bool zeroForOne,
        uint256 token0FeeAmount,
        uint256 token1FeeAmount,
        bytes calldata swapData
    ) private returns (uint256 amount) {
        uint256 amountMin;
        // Slippage check is done here instead of `NonfungiblePositionManager`
        if (zeroForOne) {
            amountMin = params.amount1Min;
            params.amount1Min = 0;
        } else {
            amountMin = params.amount0Min;
            params.amount0Min = 0;
        }
        NPMCaller.decreaseLiquidity(npm, params);
        // Collect the tokens owed and deduct gas and aperture fees.
        uint256 tokenId = params.tokenId;
        (uint256 amount0, uint256 amount1) = _collectDeductFees(
            tokenId,
            pos.token0,
            pos.token1,
            token0FeeAmount,
            token1FeeAmount
        );
        // Swap to the desired token and send it to the position owner
        // It is assumed that the swap is `exactIn` and all of the input tokens are consumed.
        unchecked {
            if (zeroForOne) {
                amount = amount1 + _swap(castPoolKey(pos), amount0, true, swapData);
                refund(pos.token1, NPMCaller.ownerOf(npm, tokenId), amount);
            } else {
                amount = amount0 + _swap(castPoolKey(pos), amount1, false, swapData);
                refund(pos.token0, NPMCaller.ownerOf(npm, tokenId), amount);
            }
        }
        if (amount < amountMin) revert InsufficientAmount();
    }

    /// @dev Internal decrease liquidity abstraction
    function _decreaseLiquiditySingle(
        INPM.DecreaseLiquidityParams memory params,
        bool zeroForOne,
        uint256 token0FeeAmount,
        uint256 token1FeeAmount,
        bytes calldata swapData
    ) private returns (uint256 amount) {
        Position memory pos = _positions(params.tokenId);
        amount = _decreaseCollectSingle(params, pos, zeroForOne, token0FeeAmount, token1FeeAmount, swapData);
    }

    /// @dev Internal function to remove liquidity, collect tokens to this contract, and deduct fees
    function _removeAndCollect(
        INPM.DecreaseLiquidityParams memory params,
        uint256 token0FeeAmount,
        uint256 token1FeeAmount
    ) private returns (address token0, address token1, uint256 amount0, uint256 amount1) {
        uint256 tokenId = params.tokenId;
        Position memory pos = _positions(tokenId);
        token0 = pos.token0;
        token1 = pos.token1;
        // Update `params.liquidity` to the current liquidity
        params.liquidity = pos.liquidity;
        NPMCaller.decreaseLiquidity(npm, params);
        // Collect the tokens owed and deduct gas and aperture fees
        (amount0, amount1) = _collectDeductFees(tokenId, token0, token1, token0FeeAmount, token1FeeAmount);
    }

    /// @dev Internal remove liquidity abstraction
    function _removeLiquidity(
        INPM.DecreaseLiquidityParams memory params,
        uint256 token0FeeAmount,
        uint256 token1FeeAmount
    ) private returns (uint256, uint256) {
        uint256 tokenId = params.tokenId;
        (address token0, address token1, uint256 amount0, uint256 amount1) = _removeAndCollect(
            params,
            token0FeeAmount,
            token1FeeAmount
        );
        address owner = NPMCaller.ownerOf(npm, tokenId);
        if (amount0 != 0) refund(token0, owner, amount0);
        if (amount1 != 0) refund(token1, owner, amount1);
        _burn(tokenId);
        return (amount0, amount1);
    }

    /// @dev Internal function to remove liquidity and swap to a single token
    function _removeLiquiditySingle(
        INPM.DecreaseLiquidityParams memory params,
        bool zeroForOne,
        uint256 token0FeeAmount,
        uint256 token1FeeAmount,
        bytes calldata swapData
    ) private returns (uint256 amount) {
        uint256 tokenId = params.tokenId;
        Position memory pos = _positions(tokenId);
        // Update `params.liquidity` to the current liquidity
        params.liquidity = pos.liquidity;
        amount = _decreaseCollectSingle(params, pos, zeroForOne, token0FeeAmount, token1FeeAmount, swapData);
        _burn(tokenId);
    }

    /// @dev Internal reinvest abstraction
    function _reinvest(
        INPM.IncreaseLiquidityParams memory params,
        uint256 token0FeeAmount,
        uint256 token1FeeAmount,
        bytes calldata swapData
    ) private returns (uint128, uint256, uint256) {
        Position memory pos = _positions(params.tokenId);
        PoolKey memory poolKey = castPoolKey(pos);
        uint256 amount0;
        uint256 amount1;
        {
            // Calculate the principal amounts
            (uint160 sqrtPriceX96, ) = V3PoolCallee.wrap(computeAddressSorted(poolKey)).sqrtPriceX96AndTick();
            LiquidityAmounts.getAmountsForLiquidity(
                sqrtPriceX96,
                pos.tickLower.getSqrtRatioAtTick(),
                pos.tickUpper.getSqrtRatioAtTick(),
                pos.liquidity
            );
        }
        // Collect the tokens owed then deduct gas and aperture fees
        (amount0, amount1) = _collectDeductFees(
            params.tokenId,
            pos.token0,
            pos.token1,
            token0FeeAmount,
            token1FeeAmount
        );
        // Perform optimal swap and update `params`
        (params.amount0Desired, params.amount1Desired) = _optimalSwap(
            poolKey,
            pos.tickLower,
            pos.tickUpper,
            amount0,
            amount1,
            swapData
        );
        return _increaseLiquidity(params, pos.token0, pos.token1);
    }

    /// @dev Internal rebalance abstraction
    function _rebalance(
        IUniV3NPM.MintParams memory params,
        uint256 tokenId,
        uint256 token0FeeAmount,
        uint256 token1FeeAmount,
        bytes calldata swapData
    ) private returns (uint256 newTokenId, uint128 liquidity, uint256 amount0, uint256 amount1) {
        // Remove liquidity and collect the tokens owed
        (, , amount0, amount1) = _removeAndCollect(
            INPM.DecreaseLiquidityParams({
                tokenId: tokenId,
                liquidity: 0, // Updated in `_removeAndCollect`
                amount0Min: 0,
                amount1Min: 0,
                deadline: params.deadline
            }),
            token0FeeAmount,
            token1FeeAmount
        );
        // Update `recipient` to the current owner
        params.recipient = NPMCaller.ownerOf(npm, tokenId);
        // Perform optimal swap
        (params.amount0Desired, params.amount1Desired) = _optimalSwap(
            castPoolKey(params),
            params.tickLower,
            params.tickUpper,
            amount0,
            amount1,
            swapData
        );
        // `token0` and `token1` are assumed to be the same as the old position while fee tier may change.
        (newTokenId, liquidity, amount0, amount1) = _mint(params);
    }

    /// @notice Approve of a specific token ID for spending by this contract via signature if necessary
    /// @param tokenId The ID of the token that is being approved for spending
    /// @param deadline The deadline timestamp by which the call must be mined for the approve to work
    /// @param v The recovery byte of the signature
    /// @param r Half of the ECDSA signature pair
    /// @param s Half of the ECDSA signature pair
    function selfPermitIfNecessary(uint256 tokenId, uint256 deadline, uint8 v, bytes32 r, bytes32 s) internal {
        if (NPMCaller.getApproved(npm, tokenId) == address(this)) return;
        if (NPMCaller.isApprovedForAll(npm, NPMCaller.ownerOf(npm, tokenId), address(this))) return;
        NPMCaller.permit(npm, address(this), tokenId, deadline, v, r, s);
    }

    /************************************************
     *  LIQUIDITY MANAGEMENT
     ***********************************************/

    /// @inheritdoc IAutomanUniV3MintRebalance
    function mint(
        IUniV3NPM.MintParams memory params
    ) external payable returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) {
        pullAndApprove(params.token0, params.token1, params.amount0Desired, params.amount1Desired);
        (tokenId, liquidity, amount0, amount1) = _mint(params);
        emit Mint(tokenId);
    }

    /// @inheritdoc IAutomanUniV3MintRebalance
    function mintOptimal(
        IUniV3NPM.MintParams memory params,
        bytes calldata swapData,
        uint256 token0FeeAmount,
        uint256 token1FeeAmount
    ) external payable returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) {
        PoolKey memory poolKey = castPoolKey(params);
        // Pull tokens
        if (params.amount0Desired != 0) pay(poolKey.token0, msg.sender, address(this), params.amount0Desired);
        if (params.amount1Desired != 0) pay(poolKey.token1, msg.sender, address(this), params.amount1Desired);
        // Collect zap-in fees before swap.
        _deductFees(
            poolKey.token0,
            poolKey.token1,
            params.amount0Desired,
            params.amount1Desired,
            token0FeeAmount,
            token1FeeAmount
        );
        params.amount0Desired -= token0FeeAmount;
        params.amount1Desired -= token1FeeAmount;
        // Perform optimal swap after which the amounts desired are updated
        (params.amount0Desired, params.amount1Desired) = _optimalSwap(
            poolKey,
            params.tickLower,
            params.tickUpper,
            params.amount0Desired,
            params.amount1Desired,
            swapData
        );
        (tokenId, liquidity, amount0, amount1) = _mint(params);
        emit Mint(tokenId);
    }

    /// @inheritdoc IAutomanCommon
    function increaseLiquidity(
        INPM.IncreaseLiquidityParams memory params
    ) external payable returns (uint128 liquidity, uint256 amount0, uint256 amount1) {
        uint256 tokenId = params.tokenId;
        Position memory pos = _positions(tokenId);
        address token0 = pos.token0;
        address token1 = pos.token1;
        pullAndApprove(token0, token1, params.amount0Desired, params.amount1Desired);
        (liquidity, amount0, amount1) = _increaseLiquidity(params, token0, token1);
        emit IncreaseLiquidity(tokenId);
    }

    /// @inheritdoc IAutomanCommon
    function increaseLiquidityOptimal(
        INPM.IncreaseLiquidityParams memory params,
        bytes calldata swapData,
        uint256 token0FeeAmount,
        uint256 token1FeeAmount
    ) external payable returns (uint128 liquidity, uint256 amount0, uint256 amount1) {
        Position memory pos = _positions(params.tokenId);
        address token0 = pos.token0;
        address token1 = pos.token1;
        // Pull tokens
        if (params.amount0Desired != 0) pay(token0, msg.sender, address(this), params.amount0Desired);
        if (params.amount1Desired != 0) pay(token1, msg.sender, address(this), params.amount1Desired);
        // Collect zap-in fees before swap.
        _deductFees(token0, token1, params.amount0Desired, params.amount1Desired, token0FeeAmount, token1FeeAmount);
        params.amount0Desired -= token0FeeAmount;
        params.amount1Desired -= token1FeeAmount;
        // Perform optimal swap after which the amounts desired are updated
        (params.amount0Desired, params.amount1Desired) = _optimalSwap(
            castPoolKey(pos),
            pos.tickLower,
            pos.tickUpper,
            params.amount0Desired,
            params.amount1Desired,
            swapData
        );
        (liquidity, amount0, amount1) = _increaseLiquidity(params, token0, token1);
        emit IncreaseLiquidity(params.tokenId);
    }

    /// @inheritdoc IAutomanCommon
    function decreaseLiquidity(
        INPM.DecreaseLiquidityParams memory params,
        uint256 token0FeeAmount,
        uint256 token1FeeAmount
    ) external returns (uint256 amount0, uint256 amount1) {
        uint256 tokenId = params.tokenId;
        checkAuthorizedForToken(tokenId);
        (amount0, amount1) = _decreaseLiquidity(params, token0FeeAmount, token1FeeAmount);
        emit DecreaseLiquidity(tokenId);
    }

    /// @inheritdoc IAutomanCommon
    function decreaseLiquidity(
        INPM.DecreaseLiquidityParams memory params,
        uint256 token0FeeAmount,
        uint256 token1FeeAmount,
        uint256 permitDeadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 amount0, uint256 amount1) {
        uint256 tokenId = params.tokenId;
        checkAuthorizedForToken(tokenId);
        selfPermitIfNecessary(tokenId, permitDeadline, v, r, s);
        (amount0, amount1) = _decreaseLiquidity(params, token0FeeAmount, token1FeeAmount);
        emit DecreaseLiquidity(tokenId);
    }

    /// @inheritdoc IAutomanCommon
    function decreaseLiquiditySingle(
        INPM.DecreaseLiquidityParams memory params,
        bool zeroForOne,
        uint256 token0FeeAmount,
        uint256 token1FeeAmount,
        bytes calldata swapData
    ) external returns (uint256 amount) {
        uint256 tokenId = params.tokenId;
        checkAuthorizedForToken(tokenId);
        amount = _decreaseLiquiditySingle(params, zeroForOne, token0FeeAmount, token1FeeAmount, swapData);
        emit DecreaseLiquidity(tokenId);
    }

    /// @inheritdoc IAutomanCommon
    function decreaseLiquiditySingle(
        INPM.DecreaseLiquidityParams memory params,
        bool zeroForOne,
        uint256 token0FeeAmount,
        uint256 token1FeeAmount,
        bytes calldata swapData,
        uint256 permitDeadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 amount) {
        uint256 tokenId = params.tokenId;
        checkAuthorizedForToken(tokenId);
        selfPermitIfNecessary(tokenId, permitDeadline, v, r, s);
        amount = _decreaseLiquiditySingle(params, zeroForOne, token0FeeAmount, token1FeeAmount, swapData);
        emit DecreaseLiquidity(tokenId);
    }

    /// @inheritdoc IAutomanCommon
    function removeLiquidity(
        INPM.DecreaseLiquidityParams memory params,
        uint256 token0FeeAmount,
        uint256 token1FeeAmount
    ) external returns (uint256 amount0, uint256 amount1) {
        uint256 tokenId = params.tokenId;
        checkAuthorizedForToken(tokenId);
        (amount0, amount1) = _removeLiquidity(params, token0FeeAmount, token1FeeAmount);
        emit RemoveLiquidity(tokenId);
    }

    /// @inheritdoc IAutomanCommon
    function removeLiquidity(
        INPM.DecreaseLiquidityParams memory params,
        uint256 token0FeeAmount,
        uint256 token1FeeAmount,
        uint256 permitDeadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 amount0, uint256 amount1) {
        uint256 tokenId = params.tokenId;
        checkAuthorizedForToken(tokenId);
        selfPermitIfNecessary(tokenId, permitDeadline, v, r, s);
        (amount0, amount1) = _removeLiquidity(params, token0FeeAmount, token1FeeAmount);
        emit RemoveLiquidity(tokenId);
    }

    /// @inheritdoc IAutomanCommon
    function removeLiquiditySingle(
        INPM.DecreaseLiquidityParams memory params,
        bool zeroForOne,
        uint256 token0FeeAmount,
        uint256 token1FeeAmount,
        bytes calldata swapData
    ) external returns (uint256 amount) {
        uint256 tokenId = params.tokenId;
        checkAuthorizedForToken(tokenId);
        amount = _removeLiquiditySingle(params, zeroForOne, token0FeeAmount, token1FeeAmount, swapData);
        emit RemoveLiquidity(tokenId);
    }

    /// @inheritdoc IAutomanCommon
    function removeLiquiditySingle(
        INPM.DecreaseLiquidityParams memory params,
        bool zeroForOne,
        uint256 token0FeeAmount,
        uint256 token1FeeAmount,
        bytes calldata swapData,
        uint256 permitDeadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 amount) {
        uint256 tokenId = params.tokenId;
        checkAuthorizedForToken(tokenId);
        selfPermitIfNecessary(tokenId, permitDeadline, v, r, s);
        amount = _removeLiquiditySingle(params, zeroForOne, token0FeeAmount, token1FeeAmount, swapData);
        emit RemoveLiquidity(tokenId);
    }

    /// @inheritdoc IAutomanCommon
    function reinvest(
        INPM.IncreaseLiquidityParams memory params,
        uint256 token0FeeAmount,
        uint256 token1FeeAmount,
        bytes calldata swapData
    ) external returns (uint128 liquidity, uint256 amount0, uint256 amount1) {
        uint256 tokenId = params.tokenId;
        checkAuthorizedForToken(tokenId);
        (liquidity, amount0, amount1) = _reinvest(params, token0FeeAmount, token1FeeAmount, swapData);
        emit Reinvest(tokenId);
    }

    /// @inheritdoc IAutomanCommon
    function reinvest(
        INPM.IncreaseLiquidityParams memory params,
        uint256 token0FeeAmount,
        uint256 token1FeeAmount,
        bytes calldata swapData,
        uint256 permitDeadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint128 liquidity, uint256 amount0, uint256 amount1) {
        uint256 tokenId = params.tokenId;
        checkAuthorizedForToken(tokenId);
        selfPermitIfNecessary(tokenId, permitDeadline, v, r, s);
        (liquidity, amount0, amount1) = _reinvest(params, token0FeeAmount, token1FeeAmount, swapData);
        emit Reinvest(tokenId);
    }

    /// @inheritdoc IAutomanUniV3MintRebalance
    function rebalance(
        IUniV3NPM.MintParams memory params,
        uint256 tokenId,
        uint256 token0FeeAmount,
        uint256 token1FeeAmount,
        bytes calldata swapData
    ) external returns (uint256 newTokenId, uint128 liquidity, uint256 amount0, uint256 amount1) {
        checkAuthorizedForToken(tokenId);
        (newTokenId, liquidity, amount0, amount1) = _rebalance(
            params,
            tokenId,
            token0FeeAmount,
            token1FeeAmount,
            swapData
        );
        emit Rebalance(newTokenId);
    }

    /// @inheritdoc IAutomanUniV3MintRebalance
    function rebalance(
        IUniV3NPM.MintParams memory params,
        uint256 tokenId,
        uint256 token0FeeAmount,
        uint256 token1FeeAmount,
        bytes calldata swapData,
        uint256 permitDeadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 newTokenId, uint128 liquidity, uint256 amount0, uint256 amount1) {
        checkAuthorizedForToken(tokenId);
        selfPermitIfNecessary(tokenId, permitDeadline, v, r, s);
        (newTokenId, liquidity, amount0, amount1) = _rebalance(
            params,
            tokenId,
            token0FeeAmount,
            token1FeeAmount,
            swapData
        );
        emit Rebalance(newTokenId);
    }
}
