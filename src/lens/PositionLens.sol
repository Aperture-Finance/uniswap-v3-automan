// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {INonfungiblePositionManager as INPM} from "@aperture_finance/uni-v3-lib/src/interfaces/INonfungiblePositionManager.sol";
import {FullMath} from "@aperture_finance/uni-v3-lib/src/FullMath.sol";
import {NPMCaller, PositionFull} from "@aperture_finance/uni-v3-lib/src/NPMCaller.sol";
import {PoolAddress} from "@aperture_finance/uni-v3-lib/src/PoolAddress.sol";
import {IUniswapV3PoolState, PoolCaller, V3PoolCallee} from "@aperture_finance/uni-v3-lib/src/PoolCaller.sol";
import {ERC20Callee} from "../libraries/ERC20Caller.sol";

struct Slot0 {
    uint160 sqrtPriceX96;
    int24 tick;
    uint16 observationIndex;
    uint16 observationCardinality;
    uint16 observationCardinalityNext;
    uint8 feeProtocol;
    bool unlocked;
}

// The length of the struct is 25 words.
struct PositionState {
    // token ID of the position
    uint256 tokenId;
    // position's owner
    address owner;
    // nonfungible position manager's position struct with real-time tokensOwed
    PositionFull position;
    // pool's slot0 struct
    Slot0 slot0;
    // pool's active liquidity
    uint128 activeLiquidity;
    // token0's decimals
    uint8 decimals0;
    // token1's decimals
    uint8 decimals1;
}

/// @notice A lens for Uniswap v3 that peeks into the current state of position and pool info
/// @author Aperture Finance
abstract contract PositionLens {
    uint256 internal constant Q128 = 1 << 128;

    /// @dev Peek a position and calculate the fee growth inside the position
    /// @param npm Nonfungible position manager
    /// @param tokenId Token ID of the position
    /// @param state Position state pointer to be updated in place
    function peek(INPM npm, uint256 tokenId, PositionState memory state) internal view {
        state.tokenId = tokenId;
        positionInPlace(npm, tokenId, state.position);
        V3PoolCallee pool = V3PoolCallee.wrap(
            PoolAddress.computeAddressSorted(
                NPMCaller.factory(npm),
                state.position.token0,
                state.position.token1,
                state.position.fee
            )
        );
        state.activeLiquidity = pool.liquidity();
        slot0InPlace(pool, state.slot0);
        if (state.position.liquidity != 0) {
            (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) = getFeeGrowthInside(
                pool,
                state.position.tickLower,
                state.position.tickUpper,
                state.slot0.tick
            );
            updatePosition(state.position, feeGrowthInside0X128, feeGrowthInside1X128);
        }
        state.decimals0 = ERC20Callee.wrap(state.position.token0).decimals();
        state.decimals1 = ERC20Callee.wrap(state.position.token1).decimals();
    }

    /// @dev Equivalent to `INonfungiblePositionManager.positions(tokenId)`
    /// @param npm Uniswap v3 Nonfungible Position Manager
    /// @param tokenId The ID of the token that represents the position
    /// @param pos The position pointer to be updated in place
    function positionInPlace(INPM npm, uint256 tokenId, PositionFull memory pos) internal view {
        bytes4 selector = INPM.positions.selector;
        assembly ("memory-safe") {
            // Write the abi-encoded calldata into memory.
            mstore(0, selector)
            mstore(4, tokenId)
            // We use 36 because of the length of our calldata.
            // We copy up to 384 bytes of return data at pos's pointer.
            if iszero(staticcall(gas(), npm, 0, 0x24, pos, 0x180)) {
                // Bubble up the revert reason.
                revert(pos, returndatasize())
            }
        }
    }

    /// @dev Equivalent to `IUniswapV3Pool.slot0`
    /// @param pool Uniswap v3 pool
    /// @param s Slot0 pointer to be updated in place
    function slot0InPlace(V3PoolCallee pool, Slot0 memory s) internal view {
        bytes4 selector = IUniswapV3PoolState.slot0.selector;
        assembly ("memory-safe") {
            // Write the function selector into memory.
            mstore(0, selector)
            // We use 4 because of the length of our calldata.
            // We copy up to 224 bytes of return data after fmp.
            if iszero(staticcall(gas(), pool, 0, 4, s, 0xe0)) {
                revert(0, 0)
            }
        }
    }

    /// @notice Retrieves fee growth data
    /// @param pool Uniswap v3 pool
    /// @param tickLower The lower tick boundary of the position
    /// @param tickUpper The upper tick boundary of the position
    /// @param tickCurrent The current tick
    /// @return feeGrowthInside0X128 The all-time fee growth in token0, per unit of liquidity, inside the position's tick boundaries
    /// @return feeGrowthInside1X128 The all-time fee growth in token1, per unit of liquidity, inside the position's tick boundaries
    function getFeeGrowthInside(
        V3PoolCallee pool,
        int24 tickLower,
        int24 tickUpper,
        int24 tickCurrent
    ) internal view returns (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) {
        PoolCaller.Info memory lower = pool.ticks(tickLower);
        PoolCaller.Info memory upper = pool.ticks(tickUpper);

        unchecked {
            if (tickCurrent < tickLower) {
                feeGrowthInside0X128 = lower.feeGrowthOutside0X128 - upper.feeGrowthOutside0X128;
                feeGrowthInside1X128 = lower.feeGrowthOutside1X128 - upper.feeGrowthOutside1X128;
            } else if (tickCurrent >= tickUpper) {
                feeGrowthInside0X128 = upper.feeGrowthOutside0X128 - lower.feeGrowthOutside0X128;
                feeGrowthInside1X128 = upper.feeGrowthOutside1X128 - lower.feeGrowthOutside1X128;
            } else {
                feeGrowthInside0X128 =
                    pool.feeGrowthGlobal0X128() -
                    lower.feeGrowthOutside0X128 -
                    upper.feeGrowthOutside0X128;
                feeGrowthInside1X128 =
                    pool.feeGrowthGlobal1X128() -
                    lower.feeGrowthOutside1X128 -
                    upper.feeGrowthOutside1X128;
            }
        }
    }

    /// @notice Credits accumulated fees to a user's position
    /// @param position The individual position to update
    /// @param feeGrowthInside0X128 The all-time fee growth in token0, per unit of liquidity, inside the position's tick boundaries
    /// @param feeGrowthInside1X128 The all-time fee growth in token1, per unit of liquidity, inside the position's tick boundaries
    function updatePosition(
        PositionFull memory position,
        uint256 feeGrowthInside0X128,
        uint256 feeGrowthInside1X128
    ) internal pure {
        unchecked {
            // calculate accumulated fees
            position.tokensOwed0 += uint128(
                FullMath.mulDiv(feeGrowthInside0X128 - position.feeGrowthInside0LastX128, position.liquidity, Q128)
            );
            position.tokensOwed1 += uint128(
                FullMath.mulDiv(feeGrowthInside1X128 - position.feeGrowthInside1LastX128, position.liquidity, Q128)
            );
        }
    }
}
