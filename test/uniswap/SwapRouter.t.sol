// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "src/base/SwapRouter.sol";
import {Helper, TickBitmap, TickMath, V3PoolCallee, UniBase} from "./UniBase.sol";
import {IPCSV3NonfungiblePositionManager} from "@aperture_finance/uni-v3-lib/src/interfaces/IPCSV3NonfungiblePositionManager.sol";

interface ISwapRouterHandler {
    function poolSwap(
        PoolKey memory poolKey,
        address pool,
        uint256 amountIn,
        bool zeroForOne
    ) external returns (uint256 amountOut);

    function routerSwap(
        PoolKey memory poolKey,
        uint256 amountIn,
        bool zeroForOne,
        bytes calldata swapData
    ) external returns (uint256 amountOut);

    function optimalSwapWithPool(
        PoolKey memory poolKey,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) external returns (uint256 amount0, uint256 amount1);

    function optimalSwapWithRouter(
        PoolKey memory poolKey,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Desired,
        uint256 amount1Desired,
        bytes calldata swapData
    ) external returns (uint256 amount0, uint256 amount1);
}

/// @dev SwapRouter with public functions for testing
abstract contract SwapRouterHandler is SwapRouter, Helper, ISwapRouterHandler {
    /// @dev Make a direct `exactIn` pool swap
    /// @param poolKey The pool key containing the token addresses and fee tier
    /// @param pool The address of the pool
    /// @param amountIn The amount of token to be swapped
    /// @param zeroForOne The direction of the swap, true for token0 to token1, false for token1 to token0
    /// @return amountOut The amount of token received after swap
    function poolSwap(
        PoolKey memory poolKey,
        address pool,
        uint256 amountIn,
        bool zeroForOne
    ) external returns (uint256 amountOut) {
        (address tokenIn, address tokenOut) = switchIf(zeroForOne, poolKey.token1, poolKey.token0);
        pay(tokenIn, msg.sender, address(this), amountIn);
        amountOut = _poolSwap(poolKey, pool, amountIn, zeroForOne);
        pay(tokenOut, address(this), msg.sender, amountOut);
    }

    /// @dev Make an `exactIn` swap through a whitelisted external router
    /// @param poolKey The pool key containing the token addresses and fee tier
    /// @param amountIn The amount of token to be swapped
    /// @param zeroForOne The direction of the swap, true for token0 to token1, false for token1 to token0
    /// @param swapData The address of the external router and call data, not abi-encoded
    /// @return amountOut The amount of token received after swap
    function routerSwap(
        PoolKey memory poolKey,
        uint256 amountIn,
        bool zeroForOne,
        bytes calldata swapData
    ) external returns (uint256 amountOut) {
        (address tokenIn, address tokenOut) = switchIf(zeroForOne, poolKey.token1, poolKey.token0);
        pay(tokenIn, msg.sender, address(this), amountIn);
        amountOut = _routerSwapFromTokenInToTokenOut(poolKey, swapData);
        pay(tokenOut, address(this), msg.sender, amountOut);
    }

    /// @dev Swap tokens to the optimal ratio to add liquidity in the same pool
    /// @param poolKey The pool key containing the token addresses and fee tier
    /// @param tickLower The lower tick of the position in which to add liquidity
    /// @param tickUpper The upper tick of the position in which to add liquidity
    /// @param amount0Desired The desired amount of token0 to be spent
    /// @param amount1Desired The desired amount of token1 to be spent
    /// @return amount0 The amount of token0 after swap
    /// @return amount1 The amount of token1 after swap
    function optimalSwapWithPool(
        PoolKey memory poolKey,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) external returns (uint256 amount0, uint256 amount1) {
        pay(poolKey.token0, msg.sender, address(this), amount0Desired);
        pay(poolKey.token1, msg.sender, address(this), amount1Desired);
        (amount0, amount1) = _optimalSwapWithPool(poolKey, tickLower, tickUpper, amount0Desired, amount1Desired);
        pay(poolKey.token0, address(this), msg.sender, amount0);
        pay(poolKey.token1, address(this), msg.sender, amount1);
    }

    /// @dev Swap tokens to the optimal ratio to add liquidity with an external router
    /// @param poolKey The pool key containing the token addresses and fee tier
    /// @param tickLower The lower tick of the position in which to add liquidity
    /// @param tickUpper The upper tick of the position in which to add liquidity
    /// @param amount0Desired The desired amount of token0 to be spent
    /// @param amount1Desired The desired amount of token1 to be spent
    /// @return amount0 The amount of token0 after swap
    /// @return amount1 The amount of token1 after swap
    function optimalSwapWithRouter(
        PoolKey memory poolKey,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Desired,
        uint256 amount1Desired,
        bytes calldata swapData
    ) external returns (uint256 amount0, uint256 amount1) {
        pay(poolKey.token0, msg.sender, address(this), amount0Desired);
        pay(poolKey.token1, msg.sender, address(this), amount1Desired);
        (amount0, amount1) = _optimalSwapWithRouter(
            poolKey,
            tickLower,
            tickUpper,
            swapData
        );
        pay(poolKey.token0, address(this), msg.sender, amount0);
        pay(poolKey.token1, address(this), msg.sender, amount1);
    }
}

contract UniV3SwapRouterHandler is SwapRouterHandler, UniV3SwapRouter {
    constructor(INPM nonfungiblePositionManager) UniV3Immutables(nonfungiblePositionManager) {}
}

contract PCSV3SwapRouterHandler is SwapRouterHandler, PCSV3SwapRouter {
    constructor(IPCSV3NonfungiblePositionManager npm) PCSV3Immutables(npm) {}
}

contract SwapRouterTest is UniBase {
    using SafeTransferLib for address;

    ISwapRouterHandler internal router;
    PoolKey internal poolKey;
    address internal v3SwapRouter;

    function setUp() public virtual override {
        super.setUp();
        v3SwapRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
        router = new UniV3SwapRouterHandler(npm);
        vm.label(address(router), "SwapRouter");
        vm.label(v3SwapRouter, "v3Router");
        poolKey = PoolAddress.getPoolKeySorted(token0, token1, fee);
        deal(address(this), 0);
    }

    /// @dev Test a direct pool swap
    function test_PoolSwap() public {
        testFuzz_PoolSwap(true, token0Unit);
    }

    /// @dev Test a direct pool swap
    function testFuzz_PoolSwap(bool zeroForOne, uint256 amountSpecified) public {
        amountSpecified = prepSwap(zeroForOne, amountSpecified);
        address tokenIn = ternary(zeroForOne, token0, token1);
        tokenIn.safeApprove(address(router), amountSpecified);
        uint256 amountOut = router.poolSwap(poolKey, pool, amountSpecified, zeroForOne);
        assertSwapSuccess(zeroForOne, amountOut);
        assertZeroBalance(address(router));
    }

    /// @dev Test a router swap
    function testFuzz_RouterSwap(bool zeroForOne, uint256 amountSpecified) public {
        amountSpecified = prepSwap(zeroForOne, amountSpecified);
        (address tokenIn, address tokenOut) = switchIf(zeroForOne, token1, token0);
        tokenIn.safeApprove(address(router), amountSpecified);
        bytes memory data = abi.encodeWithSelector(
            ISwapRouter.exactInputSingle.selector,
            ISwapRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: fee,
                recipient: address(router),
                deadline: block.timestamp,
                amountIn: amountSpecified,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );
        uint256 amountOut = router.routerSwap(
            poolKey,
            amountSpecified,
            zeroForOne,
            abi.encodePacked(v3SwapRouter, data)
        );
        assertSwapSuccess(zeroForOne, amountOut);
        assertZeroBalance(address(router));
    }

    /// @dev Test optimal swap with the same pool
    function testFuzz_OptimalSwapWithPool(
        uint256 amount0Desired,
        uint256 amount1Desired,
        int24 tickLower,
        int24 tickUpper
    ) public {
        (tickLower, tickUpper) = prepTicks(tickLower, tickUpper);
        (amount0Desired, amount1Desired) = prepAmounts(amount0Desired, amount1Desired);
        deal(token0, address(this), amount0Desired);
        deal(token1, address(this), amount1Desired);
        token0.safeApprove(address(router), amount0Desired);
        token1.safeApprove(address(router), amount1Desired);
        (uint256 amount0, uint256 amount1) = router.optimalSwapWithPool(
            poolKey,
            tickLower,
            tickUpper,
            amount0Desired,
            amount1Desired
        );
        if (mint(address(this), amount0, amount1, tickLower, tickUpper)) assertLittleLeftover();
        assertZeroBalance(address(router));
    }

    /// @dev Test optimal swap with a router
    function testFuzz_OptimalSwapWithRouter(
        uint256 amount0Desired,
        uint256 amount1Desired,
        int24 tickLower,
        int24 tickUpper
    ) public {
        uint256 amtSwap;
        bool zeroForOne;
        (tickLower, tickUpper, amount0Desired, amount1Desired, amtSwap, , zeroForOne) = prepOptimalSwap(
            tickLower,
            tickUpper,
            amount0Desired,
            amount1Desired
        );
        if (amtSwap != 0) {
            bytes memory data;
            {
                address _token0 = token0;
                address _token1 = token1;
                deal(_token0, address(this), amount0Desired);
                deal(_token1, address(this), amount1Desired);
                _token0.safeApprove(address(router), amount0Desired);
                _token1.safeApprove(address(router), amount1Desired);
                (address tokenIn, address tokenOut) = switchIf(zeroForOne, _token1, _token0);
                data = abi.encodeWithSelector(
                    ISwapRouter.exactInputSingle.selector,
                    ISwapRouter.ExactInputSingleParams({
                        tokenIn: tokenIn,
                        tokenOut: tokenOut,
                        fee: fee,
                        recipient: address(router),
                        deadline: block.timestamp,
                        amountIn: amtSwap,
                        amountOutMinimum: 0,
                        sqrtPriceLimitX96: 0
                    })
                );
            }
            (uint256 amount0, uint256 amount1) = router.optimalSwapWithRouter(
                poolKey,
                tickLower,
                tickUpper,
                amount0Desired,
                amount1Desired,
                abi.encodePacked(v3SwapRouter, data)
            );
            if (mint(address(this), amount0, amount1, tickLower, tickUpper)) assertLittleLeftover();
        }
        assertZeroBalance(address(router));
    }
}

contract PCSV3SwapRouterTest is SwapRouterTest {
    function setUp() public virtual override {
        dex = UniBase.DEX.PCSV3;
        UniBase.setUp();
        v3SwapRouter = 0x1b81D678ffb9C0263b24A97847620C99d213eB14;
        router = new PCSV3SwapRouterHandler(IPCSV3NonfungiblePositionManager(address(npm)));
        vm.label(address(router), "SwapRouter");
        vm.label(v3SwapRouter, "v3Router");
        poolKey = PoolAddress.getPoolKeySorted(token0, token1, fee);
        deal(address(this), 0);
    }
}
