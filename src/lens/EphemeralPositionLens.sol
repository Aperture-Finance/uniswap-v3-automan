// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import {INonfungiblePositionManager as INPM, IPeripheryImmutableState} from "@aperture_finance/uni-v3-lib/src/interfaces/INonfungiblePositionManager.sol";
import {FullMath} from "@aperture_finance/uni-v3-lib/src/FullMath.sol";
import {NPMCaller, PositionFull} from "@aperture_finance/uni-v3-lib/src/NPMCaller.sol";
import {PoolAddress} from "@aperture_finance/uni-v3-lib/src/PoolAddress.sol";
import {IUniswapV3PoolState, PoolCaller, V3PoolCallee} from "@aperture_finance/uni-v3-lib/src/PoolCaller.sol";

/// @notice A lens for Uniswap v3 that peeks into the current state of position and pool info without deployment
/// @author Aperture Finance
/// @dev The return data can be accessed externally by `eth_call` without a `to` address or internally by
/// `address(new EphemeralGetPosition(npm, tokenId)).code`, and decoded by `abi.decode(data, (PositionState))`
contract EphemeralGetPosition {
    constructor(INPM npm, uint256 tokenId) {
        PositionState memory pos = getPosition(npm, tokenId);
        bytes memory returnData = abi.encode(pos);
        assembly ("memory-safe") {
            return(add(returnData, 0x20), mload(returnData))
        }
    }

    /// @dev Public function to expose the abi for easier decoding using TypeChain
    /// @param npm Nonfungible position manager
    /// @param tokenId Token ID of the position
    function getPosition(INPM npm, uint256 tokenId) public view returns (PositionState memory) {
        return PositionLens.peek(npm, tokenId);
    }
}

/// @notice A lens for Uniswap v3 that peeks into the current state of all positions by an owner without deployment
/// @author Aperture Finance
/// @dev The return data can be accessed externally by `eth_call` without a `to` address or internally by
/// `address(new EphemeralAllPositions(npm, owner)).code`, and decoded by `abi.decode(data, (uint256[], PositionState[]))`
contract EphemeralAllPositions {
    constructor(INPM npm, address owner) {
        (uint256[] memory tokenIds, PositionState[] memory positions) = allPositions(npm, owner);
        bytes memory returnData = abi.encode(tokenIds, positions);
        assembly ("memory-safe") {
            return(add(returnData, 0x20), mload(returnData))
        }
    }

    /// @dev Public function to expose the abi for easier decoding using TypeChain
    /// @param npm Nonfungible position manager
    /// @param owner The address that owns the NFTs
    function allPositions(
        INPM npm,
        address owner
    ) public view returns (uint256[] memory tokenIds, PositionState[] memory positions) {
        uint256 balance = NPMCaller.balanceOf(npm, owner);
        tokenIds = new uint256[](balance);
        positions = new PositionState[](balance);
        unchecked {
            for (uint256 i; i < balance; ++i) {
                uint256 tokenId = tokenOfOwnerByIndex(npm, owner, i);
                tokenIds[i] = tokenId;
                positions[i] = PositionLens.peek(npm, tokenId);
            }
        }
    }

    /// @dev Returns a token ID owned by `owner` at a given `index` of its token list.
    /// @param npm Uniswap v3 Nonfungible Position Manager
    /// @param owner The address that owns the NFTs
    /// @param index The index of the token ID
    function tokenOfOwnerByIndex(INPM npm, address owner, uint256 index) internal view returns (uint256 tokenId) {
        bytes4 selector = IERC721Enumerable.tokenOfOwnerByIndex.selector;
        assembly ("memory-safe") {
            // Write the abi-encoded calldata into memory.
            mstore(0, selector)
            mstore(4, owner)
            mstore(0x24, index)
            // We use 68 because of the length of our calldata.
            // We use 0 and 32 to copy up to 32 bytes of return data into the scratch space.
            if iszero(staticcall(gas(), npm, 0, 0x44, 0, 0x20)) {
                returndatacopy(0, 0, returndatasize())
                // Bubble up the revert reason.
                revert(0, returndatasize())
            }
            tokenId := mload(0)
            // Clear first 4 bytes of the free memory pointer.
            mstore(0x24, 0)
        }
    }
}

struct Slot0 {
    uint160 sqrtPriceX96;
    int24 tick;
    uint16 observationIndex;
    uint16 observationCardinality;
    uint16 observationCardinalityNext;
    uint8 feeProtocol;
    bool unlocked;
}

struct PositionState {
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

library PositionLens {
    uint256 internal constant Q128 = 1 << 128;

    /// @dev Peek a position and calculate the fee growth inside the position
    /// @param npm Nonfungible position manager
    /// @param tokenId Token ID of the position
    function peek(INPM npm, uint256 tokenId) internal view returns (PositionState memory full) {
        full.position = NPMCaller.positionsFull(npm, tokenId);
        V3PoolCallee pool = V3PoolCallee.wrap(
            PoolAddress.computeAddressSorted(
                factory(npm),
                full.position.token0,
                full.position.token1,
                full.position.fee
            )
        );
        full.activeLiquidity = pool.liquidity();
        full.slot0 = slot0(pool);
        if (full.position.liquidity != 0) {
            (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) = getFeeGrowthInside(
                pool,
                full.position.tickLower,
                full.position.tickUpper,
                full.slot0.tick
            );
            updatePosition(full.position, feeGrowthInside0X128, feeGrowthInside1X128);
        }
        full.decimals0 = decimals(full.position.token0);
        full.decimals1 = decimals(full.position.token1);
    }

    /// @dev Equivalent to `IERC20Metadata.decimals` with 18 as fallback
    /// @param token ERC20 token
    function decimals(address token) internal view returns (uint8 d) {
        bytes4 selector = IERC20Metadata.decimals.selector;
        assembly ("memory-safe") {
            mstore(0, 18)
            mstore(0x20, selector)
            let success := staticcall(gas(), token, 0x20, 4, 0x20, 0x20)
            d := mload(shl(5, success))
        }
    }

    /// @dev Equivalent to `INonfungiblePositionManager.factory`
    /// @param npm Nonfungible position manager
    function factory(INPM npm) internal view returns (address f) {
        bytes4 selector = IPeripheryImmutableState.factory.selector;
        assembly ("memory-safe") {
            // Write the function selector into memory.
            mstore(0, selector)
            // We use 4 because of the length of our calldata.
            // We use 0 and 32 to copy up to 32 bytes of return data into the scratch space.
            if iszero(staticcall(gas(), npm, 0, 4, 0, 0x20)) {
                revert(0, 0)
            }
            f := mload(0)
        }
    }

    /// @dev Equivalent to `IUniswapV3Pool.feeGrowthGlobal0X128`
    /// @param pool Uniswap v3 pool
    function feeGrowthGlobal0X128(V3PoolCallee pool) internal view returns (uint256 f) {
        bytes4 selector = IUniswapV3PoolState.feeGrowthGlobal0X128.selector;
        assembly ("memory-safe") {
            // Write the function selector into memory.
            mstore(0, selector)
            // We use 4 because of the length of our calldata.
            // We use 0 and 32 to copy up to 32 bytes of return data into the scratch space.
            if iszero(staticcall(gas(), pool, 0, 4, 0, 0x20)) {
                revert(0, 0)
            }
            f := mload(0)
        }
    }

    /// @dev Equivalent to `IUniswapV3Pool.feeGrowthGlobal1X128`
    /// @param pool Uniswap v3 pool
    function feeGrowthGlobal1X128(V3PoolCallee pool) internal view returns (uint256 f) {
        bytes4 selector = IUniswapV3PoolState.feeGrowthGlobal1X128.selector;
        assembly ("memory-safe") {
            // Write the function selector into memory.
            mstore(0, selector)
            // We use 4 because of the length of our calldata.
            // We use 0 and 32 to copy up to 32 bytes of return data into the scratch space.
            if iszero(staticcall(gas(), pool, 0, 4, 0, 0x20)) {
                revert(0, 0)
            }
            f := mload(0)
        }
    }

    /// @dev Equivalent to `IUniswapV3Pool.slot0`
    /// @param pool Uniswap v3 pool
    function slot0(V3PoolCallee pool) internal view returns (Slot0 memory s) {
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
                    feeGrowthGlobal0X128(pool) -
                    lower.feeGrowthOutside0X128 -
                    upper.feeGrowthOutside0X128;
                feeGrowthInside1X128 =
                    feeGrowthGlobal1X128(pool) -
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
