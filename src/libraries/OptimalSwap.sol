// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.8;

import "@aperture_finance/uni-v3-lib/src/SwapMath.sol";
import "@aperture_finance/uni-v3-lib/src/TickBitmap.sol";
import "@aperture_finance/uni-v3-lib/src/TickMath.sol";

/// @title Optimal Swap Library
/// @author Aperture Finance
/// @notice Optimal library for optimal double-sided Uniswap v3 liquidity provision using closed form solution
library OptimalSwap {
    using TickMath for int24;
    using FullMath for uint256;
    using UnsafeMath for uint256;

    uint256 internal constant MAX_FEE_PIPS = 1e6;

    error Invalid_Pool();
    error Invalid_Tick_Range();
    error Math_Overflow();

    struct SwapState {
        // liquidity in range after swap, accessible by `mload(state)`
        uint128 liquidity;
        // sqrt(price) after swap, accessible by `mload(add(state, 0x20))`
        uint256 sqrtPriceX96;
        // tick after swap, accessible by `mload(add(state, 0x40))`
        int24 tick;
        // The desired amount of token0 to add liquidity, `mload(add(state, 0x60))`
        uint256 amount0Desired;
        // The desired amount of token1 to add liquidity, `mload(add(state, 0x80))`
        uint256 amount1Desired;
        // sqrt(price) at the lower tick, `mload(add(state, 0xa0))`
        uint256 sqrtRatioLowerX96;
        // sqrt(price) at the upper tick, `mload(add(state, 0xc0))`
        uint256 sqrtRatioUpperX96;
        // the fee taken from the input amount, expressed in hundredths of a bip
        // accessible by `mload(add(state, 0xe0))`
        uint256 feePips;
        // the tick spacing of the pool, accessible by `mload(add(state, 0x100))`
        int24 tickSpacing;
    }

    /// @notice Get swap amount, output amount, swap direction for double-sided optimal deposit
    /// @dev Given the elegant analytic solution and custom optimizations to Uniswap libraries,
    /// the amount of gas is at the order of 10k depending on the swap amount and the number of ticks crossed,
    /// an order of magnitude less than that achieved by binary search, which can be calculated on-chain.
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
    ) internal view returns (uint256 amountIn, uint256 amountOut, bool zeroForOne, uint160 sqrtPriceX96) {
        if (amount0Desired == 0 && amount1Desired == 0) return (0, 0, false, 0);
        if (tickLower >= tickUpper || tickLower < TickMath.MIN_TICK || tickUpper > TickMath.MAX_TICK)
            revert Invalid_Tick_Range();
        // Ensure the pool exists.
        assembly ("memory-safe") {
            let poolCodeSize := extcodesize(pool)
            if iszero(poolCodeSize) {
                // revert Invalid_Pool()
                mstore(0, 0x01ac05a5)
                revert(0x1c, 0x04)
            }
        }
        // intermediate state cache
        SwapState memory state;
        // Populate `SwapState` with hardcoded offsets.
        {
            int24 tick;
            (sqrtPriceX96, tick) = pool.sqrtPriceX96AndTick();
            assembly ("memory-safe") {
                // state.tick = tick
                mstore(add(state, 0x40), tick)
            }
        }
        {
            uint128 liquidity = pool.liquidity();
            uint256 feePips = pool.fee();
            int24 tickSpacing = pool.tickSpacing();
            assembly ("memory-safe") {
                // state.liquidity = liquidity
                mstore(state, liquidity)
                // state.sqrtPriceX96 = sqrtPriceX96
                mstore(add(state, 0x20), sqrtPriceX96)
                // state.amount0Desired = amount0Desired
                mstore(add(state, 0x60), amount0Desired)
                // state.amount1Desired = amount1Desired
                mstore(add(state, 0x80), amount1Desired)
                // state.feePips = feePips
                mstore(add(state, 0xe0), feePips)
                // state.tickSpacing = tickSpacing
                mstore(add(state, 0x100), tickSpacing)
            }
        }
        uint160 sqrtRatioLowerX96 = tickLower.getSqrtRatioAtTick();
        uint160 sqrtRatioUpperX96 = tickUpper.getSqrtRatioAtTick();
        assembly ("memory-safe") {
            // state.sqrtRatioLowerX96 = sqrtRatioLowerX96
            mstore(add(state, 0xa0), sqrtRatioLowerX96)
            // state.sqrtRatioUpperX96 = sqrtRatioUpperX96
            mstore(add(state, 0xc0), sqrtRatioUpperX96)
        }
        zeroForOne = isZeroForOne(amount0Desired, amount1Desired, sqrtPriceX96, sqrtRatioLowerX96, sqrtRatioUpperX96);
        // Simulate optimal swap by crossing ticks until the direction reverses.
        crossTicks(pool, state, sqrtPriceX96, zeroForOne);
        // Active liquidity at the last tick of optimal swap
        uint128 liquidityLast;
        // sqrt(price) at the last tick of optimal swap
        uint160 sqrtPriceLastTickX96;
        // Remaining amount of token0 to add liquidity at the last tick
        uint256 amount0LastTick;
        // Remaining amount of token1 to add liquidity at the last tick
        uint256 amount1LastTick;
        assembly ("memory-safe") {
            // liquidityLast = state.liquidity
            liquidityLast := mload(state)
            // sqrtPriceLastTickX96 = state.sqrtPriceX96
            sqrtPriceLastTickX96 := mload(add(state, 0x20))
            // amount0LastTick = state.amount0Desired
            amount0LastTick := mload(add(state, 0x60))
            // amount1LastTick = state.amount1Desired
            amount1LastTick := mload(add(state, 0x80))
        }
        unchecked {
            if (!zeroForOne) {
                // The last tick is out of range. There are two cases:
                // 1. There is not enough token1 to swap to reach the lower tick.
                // 2. There is no initialized tick between the last tick and the lower tick.
                if (sqrtPriceLastTickX96 < sqrtRatioLowerX96) {
                    sqrtPriceX96 = SqrtPriceMath.getNextSqrtPriceFromAmount1RoundingDown(
                        sqrtPriceLastTickX96,
                        liquidityLast,
                        amount1LastTick.mulDiv(MAX_FEE_PIPS - state.feePips, MAX_FEE_PIPS),
                        true
                    );
                    // The final price is out of range. Simply consume all token1.
                    if (sqrtPriceX96 < sqrtRatioLowerX96) {
                        amountIn = amount1Desired;
                    }
                    // Swap to the lower tick and update the state.
                    else {
                        amount1LastTick -= SqrtPriceMath
                            .getAmount1Delta(sqrtPriceLastTickX96, sqrtRatioLowerX96, liquidityLast, true)
                            .mulDiv(MAX_FEE_PIPS, MAX_FEE_PIPS - state.feePips);
                        amount0LastTick += SqrtPriceMath.getAmount0Delta(
                            sqrtPriceLastTickX96,
                            sqrtRatioLowerX96,
                            liquidityLast,
                            false
                        );
                        sqrtPriceLastTickX96 = sqrtRatioLowerX96;
                        state.sqrtPriceX96 = sqrtPriceLastTickX96;
                        state.amount0Desired = amount0LastTick;
                        state.amount1Desired = amount1LastTick;
                    }
                }
                // The final price is in range. Use the closed form solution.
                if (sqrtPriceLastTickX96 >= sqrtRatioLowerX96) {
                    sqrtPriceX96 = solveOptimalOneForZero(state);
                    amountIn =
                        amount1Desired -
                        amount1LastTick +
                        SqrtPriceMath.getAmount1Delta(sqrtPriceX96, sqrtPriceLastTickX96, liquidityLast, true).mulDiv(
                            MAX_FEE_PIPS,
                            MAX_FEE_PIPS - state.feePips
                        );
                }
                amountOut =
                    amount0LastTick -
                    amount0Desired +
                    SqrtPriceMath.getAmount0Delta(sqrtPriceX96, sqrtPriceLastTickX96, liquidityLast, false);
            } else {
                // The last tick is out of range. There are two cases:
                // 1. There is not enough token0 to swap to reach the upper tick.
                // 2. There is no initialized tick between the last tick and the upper tick.
                if (sqrtPriceLastTickX96 > sqrtRatioUpperX96) {
                    sqrtPriceX96 = SqrtPriceMath.getNextSqrtPriceFromAmount0RoundingUp(
                        sqrtPriceLastTickX96,
                        liquidityLast,
                        amount0LastTick.mulDiv(MAX_FEE_PIPS - state.feePips, MAX_FEE_PIPS),
                        true
                    );
                    // The final price is out of range. Simply consume all token0.
                    if (sqrtPriceX96 >= sqrtRatioUpperX96) {
                        amountIn = amount0Desired;
                    }
                    // Swap to the upper tick and update the state.
                    else {
                        amount0LastTick -= SqrtPriceMath
                            .getAmount0Delta(sqrtRatioUpperX96, sqrtPriceLastTickX96, liquidityLast, true)
                            .mulDiv(MAX_FEE_PIPS, MAX_FEE_PIPS - state.feePips);
                        amount1LastTick += SqrtPriceMath.getAmount1Delta(
                            sqrtRatioUpperX96,
                            sqrtPriceLastTickX96,
                            liquidityLast,
                            false
                        );
                        sqrtPriceLastTickX96 = sqrtRatioUpperX96;
                        state.sqrtPriceX96 = sqrtPriceLastTickX96;
                        state.amount0Desired = amount0LastTick;
                        state.amount1Desired = amount1LastTick;
                    }
                }
                // The final price is in range. Use the closed form solution.
                if (sqrtPriceLastTickX96 <= sqrtRatioUpperX96) {
                    sqrtPriceX96 = solveOptimalZeroForOne(state);
                    amountIn =
                        amount0Desired -
                        amount0LastTick +
                        SqrtPriceMath.getAmount0Delta(sqrtPriceX96, sqrtPriceLastTickX96, liquidityLast, true).mulDiv(
                            MAX_FEE_PIPS,
                            MAX_FEE_PIPS - state.feePips
                        );
                }
                amountOut =
                    amount1LastTick -
                    amount1Desired +
                    SqrtPriceMath.getAmount1Delta(sqrtPriceX96, sqrtPriceLastTickX96, liquidityLast, false);
            }
        }
    }

    /// @dev Check if the remaining amount is enough to cross the next initialized tick.
    // If so, check whether the swap direction changes for optimal deposit. If so, we swap too much and the final sqrt
    // price must be between the current tick and the next tick. Otherwise the next tick must be crossed.
    function crossTicks(V3PoolCallee pool, SwapState memory state, uint160 sqrtPriceX96, bool zeroForOne) private view {
        // the next tick to swap to from the current tick in the swap direction
        int24 tickNext;
        // Ensure the initial `wordPos` doesn't coincide with the starting tick's.
        int16 wordPos = type(int16).min;
        // a word in `pool.tickBitmap`
        uint256 tickWord;

        do {
            (tickNext, wordPos, tickWord) = TickBitmap.nextInitializedTick(
                pool,
                state.tick,
                state.tickSpacing,
                zeroForOne,
                wordPos,
                tickWord
            );
            // sqrt(price) for the next tick (1/0)
            uint160 sqrtPriceNextX96 = tickNext.getSqrtRatioAtTick();
            // The desired amount of token0 to add liquidity after swap
            uint256 amount0Desired;
            // The desired amount of token1 to add liquidity after swap
            uint256 amount1Desired;

            unchecked {
                if (!zeroForOne) {
                    // Abuse `amount1Desired` to store `amountIn` to avoid stack too deep errors.
                    (sqrtPriceX96, amount1Desired, amount0Desired) = SwapMath.computeSwapStepExactIn(
                        uint160(state.sqrtPriceX96),
                        sqrtPriceNextX96,
                        state.liquidity,
                        state.amount1Desired,
                        state.feePips
                    );
                    amount0Desired = state.amount0Desired + amount0Desired;
                    amount1Desired = state.amount1Desired - amount1Desired;
                } else {
                    // Abuse `amount0Desired` to store `amountIn` to avoid stack too deep errors.
                    (sqrtPriceX96, amount0Desired, amount1Desired) = SwapMath.computeSwapStepExactIn(
                        uint160(state.sqrtPriceX96),
                        sqrtPriceNextX96,
                        state.liquidity,
                        state.amount0Desired,
                        state.feePips
                    );
                    amount0Desired = state.amount0Desired - amount0Desired;
                    amount1Desired = state.amount1Desired + amount1Desired;
                }
            }

            // If the remaining amount is large enough to consume the current tick and the optimal swap direction
            // doesn't change, continue crossing ticks.
            if (sqrtPriceX96 != sqrtPriceNextX96) break;
            if (
                isZeroForOne(
                    amount0Desired,
                    amount1Desired,
                    sqrtPriceX96,
                    state.sqrtRatioLowerX96,
                    state.sqrtRatioUpperX96
                ) != zeroForOne
            ) {
                break;
            } else {
                int128 liquidityNet = pool.liquidityNet(tickNext);
                assembly ("memory-safe") {
                    // If we're moving leftward, we interpret `liquidityNet` as the opposite sign.
                    // If zeroForOne, liquidityNet = -liquidityNet = ~liquidityNet + 1 = -1 ^ liquidityNet + 1.
                    // Therefore, liquidityNet = -zeroForOne ^ liquidityNet + zeroForOne.
                    liquidityNet := add(zeroForOne, xor(sub(0, zeroForOne), liquidityNet))
                    // `liquidity` is the first in `SwapState`
                    mstore(state, add(mload(state), liquidityNet))
                    // state.sqrtPriceX96 = sqrtPriceX96
                    mstore(add(state, 0x20), sqrtPriceX96)
                    // state.tick = zeroForOne ? tickNext - 1 : tickNext
                    mstore(add(state, 0x40), sub(tickNext, zeroForOne))
                    // state.amount0Desired = amount0Desired
                    mstore(add(state, 0x60), amount0Desired)
                    // state.amount1Desired = amount1Desired
                    mstore(add(state, 0x80), amount1Desired)
                }
            }
        } while (true);
    }

    /// @dev Analytic solution for optimal swap between two nearest initialized ticks swapping token0 to token1
    /// @param state Pool state at the last tick of optimal swap
    /// @return sqrtPriceFinalX96 sqrt(price) after optimal swap
    function solveOptimalZeroForOne(SwapState memory state) private pure returns (uint160 sqrtPriceFinalX96) {
        /**
         * root = (sqrt(b^2 + 4ac) + b) / 2a
         * `a` is in the order of `amount0Desired`. `b` is in the order of `liquidity`.
         * `c` is in the order of `amount1Desired`.
         * `a`, `b`, `c` are signed integers in two's complement but typed as unsigned to avoid unnecessary casting.
         */
        uint256 a;
        uint256 b;
        uint256 c;
        uint256 sqrtPriceX96;
        unchecked {
            uint256 liquidity;
            uint256 sqrtRatioLowerX96;
            uint256 sqrtRatioUpperX96;
            uint256 feePips;
            uint256 FEE_COMPLEMENT;
            assembly ("memory-safe") {
                // liquidity = state.liquidity
                liquidity := mload(state)
                // sqrtPriceX96 = state.sqrtPriceX96
                sqrtPriceX96 := mload(add(state, 0x20))
                // sqrtRatioLowerX96 = state.sqrtRatioLowerX96
                sqrtRatioLowerX96 := mload(add(state, 0xa0))
                // sqrtRatioUpperX96 = state.sqrtRatioUpperX96
                sqrtRatioUpperX96 := mload(add(state, 0xc0))
                // feePips = state.feePips
                feePips := mload(add(state, 0xe0))
                // FEE_COMPLEMENT = MAX_FEE_PIPS - feePips
                FEE_COMPLEMENT := sub(MAX_FEE_PIPS, feePips)
            }
            {
                uint256 a0;
                assembly ("memory-safe") {
                    // amount0Desired = state.amount0Desired
                    let amount0Desired := mload(add(state, 0x60))
                    let liquidityX96 := shl(96, liquidity)
                    // a = amount0Desired + liquidity / ((1 - f) * sqrtPrice) - liquidity / sqrtRatioUpper
                    a0 := add(amount0Desired, div(mul(MAX_FEE_PIPS, liquidityX96), mul(FEE_COMPLEMENT, sqrtPriceX96)))
                    a := sub(a0, div(liquidityX96, sqrtRatioUpperX96))
                    // `a` is always positive and greater than `amount0Desired`.
                    if iszero(gt(a, amount0Desired)) {
                        // revert Math_Overflow()
                        mstore(0, 0x20236808)
                        revert(0x1c, 0x04)
                    }
                }
                b = a0.mulDiv96(sqrtRatioLowerX96);
                assembly {
                    b := add(div(mul(feePips, liquidity), FEE_COMPLEMENT), b)
                }
            }
            {
                // c = amount1Desired + liquidity * sqrtPrice - liquidity * sqrtRatioLower / (1 - f)
                uint256 c0 = liquidity.mulDiv96(sqrtPriceX96);
                assembly ("memory-safe") {
                    // c0 = amount1Desired + liquidity * sqrtPrice
                    c0 := add(mload(add(state, 0x80)), c0)
                }
                c = c0 - liquidity.mulDiv96((MAX_FEE_PIPS * sqrtRatioLowerX96) / FEE_COMPLEMENT);
                b -= c0.mulDiv(FixedPoint96.Q96, sqrtRatioUpperX96);
            }
            assembly {
                a := shl(1, a)
                c := shl(1, c)
            }
        }
        // Given a root exists, the following calculations cannot realistically overflow/underflow.
        unchecked {
            uint256 numerator = FullMath.sqrt(b * b + a * c) + b;
            assembly {
                // `numerator` and `a` must be positive so use `div`.
                sqrtPriceFinalX96 := div(shl(96, numerator), a)
            }
        }
        // The final price must be less than or equal to the price at the last tick.
        // However the calculated price may increase if the ratio is close to optimal.
        assembly {
            // sqrtPriceFinalX96 = min(sqrtPriceFinalX96, sqrtPriceX96)
            sqrtPriceFinalX96 := xor(
                sqrtPriceX96,
                mul(xor(sqrtPriceX96, sqrtPriceFinalX96), lt(sqrtPriceFinalX96, sqrtPriceX96))
            )
        }
    }

    /// @dev Analytic solution for optimal swap between two nearest initialized ticks swapping token1 to token0
    /// @param state Pool state at the last tick of optimal swap
    /// @return sqrtPriceFinalX96 sqrt(price) after optimal swap
    function solveOptimalOneForZero(SwapState memory state) private pure returns (uint160 sqrtPriceFinalX96) {
        /**
         * root = (sqrt(b^2 + 4ac) + b) / 2a
         * `a` is in the order of `amount0Desired`. `b` is in the order of `liquidity`.
         * `c` is in the order of `amount1Desired`.
         * `a`, `b`, `c` are signed integers in two's complement but typed as unsigned to avoid unnecessary casting.
         */
        uint256 a;
        uint256 b;
        uint256 c;
        uint256 sqrtPriceX96;
        unchecked {
            uint256 liquidity;
            uint256 sqrtRatioLowerX96;
            uint256 sqrtRatioUpperX96;
            uint256 feePips;
            uint256 FEE_COMPLEMENT;
            assembly ("memory-safe") {
                // liquidity = state.liquidity
                liquidity := mload(state)
                // sqrtPriceX96 = state.sqrtPriceX96
                sqrtPriceX96 := mload(add(state, 0x20))
                // sqrtRatioLowerX96 = state.sqrtRatioLowerX96
                sqrtRatioLowerX96 := mload(add(state, 0xa0))
                // sqrtRatioUpperX96 = state.sqrtRatioUpperX96
                sqrtRatioUpperX96 := mload(add(state, 0xc0))
                // feePips = state.feePips
                feePips := mload(add(state, 0xe0))
                // FEE_COMPLEMENT = MAX_FEE_PIPS - feePips
                FEE_COMPLEMENT := sub(MAX_FEE_PIPS, feePips)
            }
            {
                // a = state.amount0Desired + liquidity / sqrtPrice - liquidity / ((1 - f) * sqrtRatioUpper)
                uint256 a0;
                assembly ("memory-safe") {
                    let liquidityX96 := shl(96, liquidity)
                    // a0 = state.amount0Desired + liquidity / sqrtPrice
                    a0 := add(mload(add(state, 0x60)), div(liquidityX96, sqrtPriceX96))
                    a := sub(a0, div(mul(MAX_FEE_PIPS, liquidityX96), mul(FEE_COMPLEMENT, sqrtRatioUpperX96)))
                }
                b = a0.mulDiv96(sqrtRatioLowerX96);
                assembly {
                    b := sub(b, div(mul(feePips, liquidity), FEE_COMPLEMENT))
                }
            }
            {
                // c = amount1Desired + liquidity * sqrtPrice / (1 - f) - liquidity * sqrtRatioLower
                uint256 c0 = liquidity.mulDiv96((MAX_FEE_PIPS * sqrtPriceX96) / FEE_COMPLEMENT);
                uint256 amount1Desired;
                assembly ("memory-safe") {
                    // amount1Desired = state.amount1Desired
                    amount1Desired := mload(add(state, 0x80))
                    // c0 = amount1Desired + liquidity * sqrtPrice / (1 - f)
                    c0 := add(amount1Desired, c0)
                }
                c = c0 - liquidity.mulDiv96(sqrtRatioLowerX96);
                assembly ("memory-safe") {
                    // `c` is always positive and greater than `amount1Desired`.
                    if iszero(gt(c, amount1Desired)) {
                        // revert Math_Overflow()
                        mstore(0, 0x20236808)
                        revert(0x1c, 0x04)
                    }
                }
                b -= c0.mulDiv(FixedPoint96.Q96, state.sqrtRatioUpperX96);
            }
            assembly {
                a := shl(1, a)
                c := shl(1, c)
            }
        }
        // Given a root exists, the following calculations cannot realistically overflow/underflow.
        unchecked {
            uint256 numerator = FullMath.sqrt(b * b + a * c) + b;
            assembly {
                // `numerator` and `a` may be negative so use `sdiv`.
                sqrtPriceFinalX96 := sdiv(shl(96, numerator), a)
            }
        }
        // The final price must be greater than or equal to the price at the last tick.
        // However the calculated price may decrease if the ratio is close to optimal.
        assembly {
            // sqrtPriceFinalX96 = max(sqrtPriceFinalX96, sqrtPriceX96)
            sqrtPriceFinalX96 := xor(
                sqrtPriceX96,
                mul(xor(sqrtPriceX96, sqrtPriceFinalX96), gt(sqrtPriceFinalX96, sqrtPriceX96))
            )
        }
    }

    /// @dev Swap direction to achieve optimal deposit when the current price is in range
    /// @param amount0Desired The desired amount of token0 to be spent
    /// @param amount1Desired The desired amount of token1 to be spent
    /// @param sqrtPriceX96 sqrt(price) at the last tick of optimal swap
    /// @param sqrtRatioLowerX96 The lower sqrt(price) of the position in which to add liquidity
    /// @param sqrtRatioUpperX96 The upper sqrt(price) of the position in which to add liquidity
    /// @return The direction of the swap, true for token0 to token1, false for token1 to token0
    function isZeroForOneInRange(
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 sqrtPriceX96,
        uint256 sqrtRatioLowerX96,
        uint256 sqrtRatioUpperX96
    ) private pure returns (bool) {
        // amount0 = liquidity * (sqrt(upper) - sqrt(current)) / (sqrt(upper) * sqrt(current))
        // amount1 = liquidity * (sqrt(current) - sqrt(lower))
        // amount0 * amount1 = liquidity * (sqrt(upper) - sqrt(current)) / (sqrt(upper) * sqrt(current)) * amount1
        //     = liquidity * (sqrt(current) - sqrt(lower)) * amount0
        unchecked {
            return
                amount0Desired.mulDiv96(sqrtPriceX96).mulDiv96(sqrtPriceX96 - sqrtRatioLowerX96) >
                amount1Desired.mulDiv(sqrtRatioUpperX96 - sqrtPriceX96, sqrtRatioUpperX96);
        }
    }

    /// @dev Swap direction to achieve optimal deposit
    /// @param amount0Desired The desired amount of token0 to be spent
    /// @param amount1Desired The desired amount of token1 to be spent
    /// @param sqrtPriceX96 sqrt(price) at the last tick of optimal swap
    /// @param sqrtRatioLowerX96 The lower sqrt(price) of the position in which to add liquidity
    /// @param sqrtRatioUpperX96 The upper sqrt(price) of the position in which to add liquidity
    /// @return The direction of the swap, true for token0 to token1, false for token1 to token0
    function isZeroForOne(
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 sqrtPriceX96,
        uint256 sqrtRatioLowerX96,
        uint256 sqrtRatioUpperX96
    ) internal pure returns (bool) {
        // If the current price is below `sqrtRatioLowerX96`, only token0 is required.
        if (sqrtPriceX96 <= sqrtRatioLowerX96) return false;
        // If the current tick is above `sqrtRatioUpperX96`, only token1 is required.
        else if (sqrtPriceX96 >= sqrtRatioUpperX96) return true;
        else
            return
                isZeroForOneInRange(amount0Desired, amount1Desired, sqrtPriceX96, sqrtRatioLowerX96, sqrtRatioUpperX96);
    }
}
