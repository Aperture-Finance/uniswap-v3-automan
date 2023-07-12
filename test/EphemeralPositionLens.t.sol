// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "src/lens/EphemeralPositionLens.sol";
import "./uniswap/UniBase.sol";

contract EphemeralPositionLensTest is UniBase {
    uint256 internal lastTokenId;

    function setUp() public override {
        super.setUp();
        lastTokenId = npm.totalSupply();
    }

    function test_Deploy() public {
        new EphemeralGetPosition(npm, lastTokenId);
    }

    function testFuzz_GetPosition(uint256 tokenId) public {
        tokenId = bound(tokenId, 1, 10000);
        try new EphemeralGetPosition(npm, tokenId) returns (EphemeralGetPosition lens) {
            PositionState memory pos = abi.decode(address(lens).code, (PositionState));
            {
                (, , address token0, , uint24 fee, int24 tickLower, , uint128 liquidity, , , , ) = npm.positions(
                    tokenId
                );
                assertEq(token0, pos.position.token0, "token0");
                assertEq(fee, pos.position.fee, "fee");
                assertEq(tickLower, pos.position.tickLower, "tickLower");
                assertEq(liquidity, pos.position.liquidity, "liquidity");
            }
            IUniswapV3Pool pool = IUniswapV3Pool(
                PoolAddress.computeAddressSorted(
                    npm.factory(),
                    pos.position.token0,
                    pos.position.token1,
                    pos.position.fee
                )
            );
            (uint160 sqrtPriceX96, int24 tick, , , , , ) = pool.slot0();
            assertEq(sqrtPriceX96, pos.slot0.sqrtPriceX96, "sqrtPriceX96");
            assertEq(tick, pos.slot0.tick, "tick");
            assertEq(pool.liquidity(), pos.activeLiquidity, "liquidity");
        } catch Error(string memory reason) {
            vm.expectRevert(bytes(reason));
            npm.positions(tokenId);
        }
    }

    function test_AllPositions() public {
        address owner = npm.ownerOf(lastTokenId);
        EphemeralAllPositions lens = new EphemeralAllPositions(npm, owner);
        (uint256[] memory tokenIds, PositionState[] memory positions) = abi.decode(
            address(lens).code,
            (uint256[], PositionState[])
        );
        assertEq(tokenIds.length, npm.balanceOf(owner), "balance");
        console2.log("balance", tokenIds.length);
        for (uint256 i; i < tokenIds.length; ++i) {
            PositionState memory pos = positions[i];
            (, , address token0, , uint24 fee, int24 tickLower, , uint128 liquidity, , , , ) = npm.positions(
                tokenIds[i]
            );
            assertEq(token0, pos.position.token0, "token0");
            assertEq(fee, pos.position.fee, "fee");
            assertEq(tickLower, pos.position.tickLower, "tickLower");
            assertEq(liquidity, pos.position.liquidity, "liquidity");
            IUniswapV3Pool pool = IUniswapV3Pool(
                PoolAddress.computeAddressSorted(
                    npm.factory(),
                    pos.position.token0,
                    pos.position.token1,
                    pos.position.fee
                )
            );
            (uint160 sqrtPriceX96, int24 tick, , , , , ) = pool.slot0();
            assertEq(sqrtPriceX96, pos.slot0.sqrtPriceX96, "sqrtPriceX96");
            assertEq(tick, pos.slot0.tick, "tick");
            assertEq(pool.liquidity(), pos.activeLiquidity, "liquidity");
        }
    }
}
