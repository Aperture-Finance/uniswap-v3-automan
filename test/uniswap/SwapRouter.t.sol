// SPDX-License-Identifier: MIT
// FOUNDRY_PROFILE=lite forge test --match-path=test/uniswap/SwapRouter.t.sol -vvvvv
pragma solidity ^0.8.0;

import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "src/base/SwapRouter.sol";
import {Helper, TickBitmap, TickMath, V3PoolCallee, UniBase} from "./UniBase.sol";
import {IPCSV3NonfungiblePositionManager} from "@aperture_finance/uni-v3-lib/src/interfaces/IPCSV3NonfungiblePositionManager.sol";

interface ISwapRouterHandler is ISwapRouterCommon {
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

    /// @dev Make an `exactIn` swap through an allowlisted external router
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
        amountOut = _routerSwapFromTokenInToTokenOut(poolKey, zeroForOne, swapData);
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
            amount0Desired,
            amount1Desired,
            swapData
        );
        pay(poolKey.token0, address(this), msg.sender, amount0);
        pay(poolKey.token1, address(this), msg.sender, amount1);
    }
}

contract UniV3SwapRouterHandler is SwapRouterHandler, UniV3SwapRouter {
    constructor(
        INPM nonfungiblePositionManager,
        address owner
    ) Ownable(owner) UniV3Immutables(nonfungiblePositionManager) {}
}

contract PCSV3SwapRouterHandler is SwapRouterHandler, PCSV3SwapRouter {
    constructor(IPCSV3NonfungiblePositionManager npm, address owner) Ownable(owner) PCSV3Immutables(npm) {}
}

contract SwapRouterTest is UniBase {
    using SafeTransferLib for address;

    ISwapRouterHandler internal router;
    PoolKey internal poolKey;
    address internal v3SwapRouter;

    function setUp() public virtual override {
        super.setUp();
        // Uniswap's SwapRouter: https://docs.uniswap.org/contracts/v3/reference/deployments/ethereum-deployments
        v3SwapRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
        router = new UniV3SwapRouterHandler(npm, address(this));
        setUpCommon();
    }

    function setUpCommon() internal {
        address[] memory routers = new address[](1);
        routers[0] = v3SwapRouter;
        bool[] memory statuses = new bool[](1);
        statuses[0] = true;
        router.setAllowlistedRouters(routers, statuses);

        vm.label(address(router), "SwapRouter");
        vm.label(v3SwapRouter, "v3Router");
        poolKey = PoolAddress.getPoolKeySorted(token0, token1, fee);
        deal(address(this), 0);
    }

    /************************************************
     *  ENCODING TESTS, tests skipped by default because requires --via-ir due to stack too deep compiler error.
     *  To run test, uncomment below and run:
     *  forge test --via-ir --watch --match-path=test/uniswap/SwapRouter.t.sol --match-test=testFuzz_EncodeAndDecode --fuzz-runs 1000 -vvvvv
     ***********************************************/

    // // Since abi.encodePacked returns memory only, use this decodeAndTestSwapData function to change swapData from memory to calldata
    // function decodeAndTestSwapData(
    //     address optimalSwapRouter,
    //     address token0,
    //     address token1,
    //     uint24 feeOrTickSpacing,
    //     int24 tickLower,
    //     int24 tickUpper,
    //     bool zeroForOne,
    //     address approvalTarget,
    //     address router2,
    //     bytes calldata routerData,
    //     bytes calldata swapData
    // ) public {
    //     /*
    //         optimalSwapRouter := shr(96, calldataload(add(swapData.offset, 0))) == calldataload(sub(swapData.offset, 12))
    //         token0 := shr(96, calldataload(add(swapData.offset, 20))) == calldataload(add(swapData.offset, 8))
    //         token1 := shr(96, calldataload(add(swapData.offset, 40))) == calldataload(add(swapData.offset, 28))
    //         feeOrTickSpacing := shr(232, calldataload(add(swapData.offset, 60)))
    //         tickLower := sar(232, calldataload(add(swapData.offset, 63)))
    //         tickUpper := sar(232, calldataload(add(swapData.offset, 66)))
    //         zeroForOne := shr(248, calldataload(add(swapData.offset, 69)))
    //         approvalTarget := shr(96, calldataload(add(swapData.offset, 70))) == calldataload(add(swapData.offset, 58))
    //         router := shr(96, calldataload(add(swapData.offset, 90))) == calldataload(add(swapData.offset, 78))
    //         data.length := sub(swapData.length, 110)
    //         data.offset := add(swapData.offset, 110)
    //     */
    //     {
    //         address optimalSwapRouterDecoded0;
    //         address optimalSwapRouterDecoded1;
    //         assembly {
    //             optimalSwapRouterDecoded0 := shr(96, calldataload(add(swapData.offset, 0)))
    //             optimalSwapRouterDecoded1 := calldataload(sub(swapData.offset, 12))
    //         }
    //         assertEq(optimalSwapRouter, optimalSwapRouterDecoded0);
    //         assertEq(optimalSwapRouter, optimalSwapRouterDecoded1);
    //         assertEq(optimalSwapRouterDecoded0, optimalSwapRouterDecoded1);
    //     }
    //     {
    //         address token0Decoded0;
    //         address token0Decoded1;
    //         assembly {
    //             token0Decoded0 := shr(96, calldataload(add(swapData.offset, 20)))
    //             token0Decoded1 := calldataload(add(swapData.offset, 8))
    //         }
    //         assertEq(token0, token0Decoded0);
    //         assertEq(token0, token0Decoded1);
    //         assertEq(token0Decoded0, token0Decoded1);
    //     }
    //     {
    //         address token1Decoded0;
    //         address token1Decoded1;
    //         assembly {
    //             token1Decoded0 := shr(96, calldataload(add(swapData.offset, 40)))
    //             token1Decoded1 := calldataload(add(swapData.offset, 28))
    //         }
    //         assertEq(token1, token1Decoded0);
    //         assertEq(token1, token1Decoded1);
    //         assertEq(token1Decoded0, token1Decoded1);
    //     }
    //     {
    //         uint24 feeOrTickSpacingDecoded0;
    //         uint24 feeOrTickSpacingDecoded1;
    //         assembly {
    //             feeOrTickSpacingDecoded0 := shr(232, calldataload(add(swapData.offset, 60)))
    //             feeOrTickSpacingDecoded1 := calldataload(add(swapData.offset, 31))
    //         }
    //         assertEq(feeOrTickSpacing, feeOrTickSpacingDecoded0);
    //         assertEq(feeOrTickSpacing, feeOrTickSpacingDecoded1);
    //         assertEq(feeOrTickSpacingDecoded0, feeOrTickSpacingDecoded1);
    //     }
    //     {
    //         int24 tickLowerDecoded0;
    //         int24 tickLowerDecoded1;
    //         assembly {
    //             tickLowerDecoded0 := sar(232, calldataload(add(swapData.offset, 63)))
    //             tickLowerDecoded1 := calldataload(add(swapData.offset, 34))
    //         }
    //         assertEq(tickLower, tickLowerDecoded0);
    //         assertEq(tickLower, tickLowerDecoded1);
    //         assertEq(tickLowerDecoded0, tickLowerDecoded1);
    //     }
    //     {
    //         int24 tickUpperDecoded0;
    //         int24 tickUpperDecoded1;
    //         assembly {
    //             tickUpperDecoded0 := sar(232, calldataload(add(swapData.offset, 66)))
    //             tickUpperDecoded1 := calldataload(add(swapData.offset, 37))
    //         }
    //         assertEq(tickUpper, tickUpperDecoded0);
    //         assertEq(tickUpper, tickUpperDecoded1);
    //         assertEq(tickUpperDecoded0, tickUpperDecoded1);
    //     }
    //     {
    //         bool zeroForOneDecoded0;
    //         bool zeroForOneDecoded1;
    //         assembly {
    //             zeroForOneDecoded0 := shr(248, calldataload(add(swapData.offset, 69)))
    //             zeroForOneDecoded1 := calldataload(add(swapData.offset, 38))
    //         }
    //         assertEq(zeroForOne, zeroForOneDecoded0);
    //         // assertEq fails because bool is interpreted as true if word (not limited to just last byte) is non-zero
    //         // assertEq(zeroForOne, zeroForOneDecoded1);
    //         // assertEq(zeroForOneDecoded0, zeroForOneDecoded1);
    //     }
    //     {
    //         address approvalTargetDecoded0;
    //         address approvalTargetDecoded1;
    //         assembly {
    //             approvalTargetDecoded0 := shr(96, calldataload(add(swapData.offset, 70)))
    //             approvalTargetDecoded1 := calldataload(add(swapData.offset, 58))
    //         }
    //         assertEq(approvalTarget, approvalTargetDecoded0);
    //         assertEq(approvalTarget, approvalTargetDecoded1);
    //         assertEq(approvalTargetDecoded0, approvalTargetDecoded1);
    //     }
    //     {
    //         address router2Decoded0;
    //         address router2Decoded1;
    //         assembly {
    //             router2Decoded0 := shr(96, calldataload(add(swapData.offset, 90)))
    //             router2Decoded1 := calldataload(add(swapData.offset, 78))
    //         }
    //         assertEq(router2, router2Decoded0);
    //         assertEq(router2, router2Decoded1);
    //         assertEq(router2Decoded0, router2Decoded1);
    //     }
    //     {
    //         bytes calldata routerDataDecoded;
    //         assembly {
    //             routerDataDecoded.length := sub(swapData.length, 110)
    //             routerDataDecoded.offset := add(swapData.offset, 110)
    //         }
    //         assertEq(routerData, routerDataDecoded);
    //     }
    // }

    // function testFuzz_EncodeAndDecode(
    //     address optimalSwapRouter,
    //     address token0,
    //     address token1,
    //     uint24 feeOrTickSpacing,
    //     int24 tickLower,
    //     int24 tickUpper,
    //     bool zeroForOne,
    //     address approvalTarget,
    //     address router2,
    //     bytes calldata routerData
    // ) public {
    //     bytes memory swapData = abi.encodePacked(
    //         optimalSwapRouter,
    //         token0,
    //         token1,
    //         feeOrTickSpacing,
    //         tickLower,
    //         tickUpper,
    //         zeroForOne,
    //         approvalTarget,
    //         /* router= */ router2,
    //         routerData
    //     );
    //     this.decodeAndTestSwapData(
    //         optimalSwapRouter,
    //         token0,
    //         token1,
    //         feeOrTickSpacing,
    //         tickLower,
    //         tickUpper,
    //         zeroForOne,
    //         approvalTarget,
    //         router2,
    //         routerData,
    //         swapData
    //     );
    // }

    /************************************************
     *  ACCESS CONTROL TESTS
     ***********************************************/

    /// @dev Should revert if attempting to set NPM as router
    function testRevert_AllowlistNPMAsRouter() public {
        address[] memory routers = new address[](1);
        routers[0] = address(npm);
        bool[] memory statuses = new bool[](1);
        statuses[0] = true;
        vm.expectRevert(ISwapRouterCommon.InvalidRouter.selector);
        router.setAllowlistedRouters(routers, statuses);
    }

    /// @dev Should revert if attempting to set an ERC20 token as router
    function testRevert_AllowlistERC20AsRouter() public {
        address[] memory routers = new address[](1);
        routers[0] = address(WETH);
        bool[] memory statuses = new bool[](1);
        statuses[0] = true;
        vm.expectRevert(ISwapRouterCommon.InvalidRouter.selector);
        router.setAllowlistedRouters(routers, statuses);
        routers[0] = address(USDC);
        vm.expectRevert(ISwapRouterCommon.InvalidRouter.selector);
        router.setAllowlistedRouters(routers, statuses);
    }

    /************************************************
     *  SWAP TESTS
     ***********************************************/

    /// @dev Test a direct pool swap
    function test_PoolSwap() public {
        testFuzz_PoolSwap(true, token0Unit);
    }

    /// @dev Test a direct pool swap
    // FOUNDRY_PROFILE=lite forge test --watch --match-path=test/uniswap/SwapRouter.t.sol --match-test=testFuzz_PoolSwap -vvvvv
    function testFuzz_PoolSwap(bool zeroForOne, uint256 amountSpecified) public {
        amountSpecified = prepSwap(zeroForOne, amountSpecified);
        address tokenIn = ternary(zeroForOne, token0, token1);
        tokenIn.safeApprove(address(router), amountSpecified);
        uint256 amountOut = router.poolSwap(poolKey, pool, amountSpecified, zeroForOne);
        assertSwapSuccess(zeroForOne, amountOut);
        assertZeroBalance(address(router));
    }

    /// @dev Test a router swap
    // FOUNDRY_PROFILE=lite forge test --watch --match-path=test/uniswap/SwapRouter.t.sol --match-test=testFuzz_RouterSwap -vvvvv
    function testFuzz_RouterSwap(bool zeroForOne, uint256 amountSpecified) public {
        amountSpecified = prepSwap(zeroForOne, amountSpecified);
        (address tokenIn, address tokenOut) = switchIf(zeroForOne, token1, token0);
        tokenIn.safeApprove(address(router), amountSpecified);
        bytes memory txData = abi.encodeWithSelector(
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
        bytes memory swapData = abi.encodePacked(
            /* optimalSwapRouter= */ v3SwapRouter, // Not used anymore
            token0,
            token1,
            /* feeOrTickSpacing= */ fee,
            /* tickLower= */ int24(0), // Not used
            /* tickUpper= */ int24(0),
            zeroForOne,
            /* approveTarget= */ v3SwapRouter,
            /* router= */ v3SwapRouter,
            txData
        );
        uint256 amountOut = router.routerSwap(poolKey, amountSpecified, zeroForOne, swapData);
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
            bytes memory swapData;
            {
                address _token0 = token0;
                address _token1 = token1;
                deal(_token0, address(this), amount0Desired);
                deal(_token1, address(this), amount1Desired);
                _token0.safeApprove(address(router), amount0Desired);
                _token1.safeApprove(address(router), amount1Desired);
                (address tokenIn, address tokenOut) = switchIf(zeroForOne, _token1, _token0);
                bytes memory txData = abi.encodeWithSelector(
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
                swapData = abi.encodePacked(
                    /* optimalSwapRouter= */ v3SwapRouter, // Not used anymore
                    token0,
                    token1,
                    /* feeOrTickSpacing= */ fee,
                    tickLower,
                    tickUpper,
                    zeroForOne,
                    /* approveTarget= */ v3SwapRouter,
                    /* router= */ v3SwapRouter,
                    txData
                );
            }
            (uint256 amount0, uint256 amount1) = router.optimalSwapWithRouter(
                poolKey,
                tickLower,
                tickUpper,
                amount0Desired,
                amount1Desired,
                swapData
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
        router = new PCSV3SwapRouterHandler(IPCSV3NonfungiblePositionManager(address(npm)), address(this));
        setUpCommon();
    }
}
