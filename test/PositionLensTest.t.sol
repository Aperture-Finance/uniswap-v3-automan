// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "src/lens/EphemeralAllPositions.sol";
import "src/lens/EphemeralGetPosition.sol";
import "./uniswap/UniBase.sol";

contract PositionLensTest is UniBase {
    uint256 internal lastTokenId;

    function setUp() public override {
        super.setUp();
        lastTokenId = npm.totalSupply();
    }

    function verifyPosition(PositionState memory pos) internal {
        {
            assertEq(pos.owner, npm.ownerOf(pos.tokenId), "owner");
            (, , address token0, , uint24 fee, int24 tickLower, , uint128 liquidity, , , , ) = npm.positions(
                pos.tokenId
            );
            assertEq(token0, pos.position.token0, "token0");
            assertEq(fee, pos.position.fee, "fee");
            assertEq(tickLower, pos.position.tickLower, "tickLower");
            assertEq(liquidity, pos.position.liquidity, "liquidity");
        }
        {
            IUniswapV3Pool pool = IUniswapV3Pool(
                PoolAddress.computeAddressSorted(
                    address(factory),
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
        assertEq(IERC20Metadata(pos.position.token0).decimals(), pos.decimals0, "decimals0");
        assertEq(IERC20Metadata(pos.position.token1).decimals(), pos.decimals1, "decimals1");
    }

    function test_Deploy() public {
        new EphemeralGetPosition(npm, lastTokenId);
    }

    function testFuzz_GetPosition(uint256 tokenId) public {
        tokenId = bound(tokenId, 1, 10000);
        try new EphemeralGetPosition(npm, tokenId) returns (EphemeralGetPosition lens) {
            PositionState memory pos = abi.decode(address(lens).code, (PositionState));
            verifyPosition(pos);
        } catch Error(string memory reason) {
            vm.expectRevert(bytes(reason));
            npm.positions(tokenId);
        }
    }

    function test_AllPositions() public {
        address owner = npm.ownerOf(lastTokenId);
        try new EphemeralAllPositions(npm, owner) {} catch (bytes memory returnData) {
            PositionState[] memory positions = abi.decode(returnData, (PositionState[]));
            uint256 length = positions.length;
            console2.log("balance", length);
            for (uint256 i; i < length; ++i) {
                verifyPosition(positions[i]);
            }
        }
    }
}
