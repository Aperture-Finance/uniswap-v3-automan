pragma solidity ^0.8.19;

import {PTest, console} from "@narya-ai/PTest.sol";

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-core/contracts/interfaces/pool/IUniswapV3PoolImmutables.sol";
import "@uniswap/v3-core/contracts/interfaces/pool/IUniswapV3PoolState.sol";
import {WETH as IWETH} from "solady/src/tokens/WETH.sol";
import "solady/src/utils/SafeTransferLib.sol";
import {PoolAddress} from "@aperture_finance/uni-v3-lib/src/PoolAddress.sol";
import {INonfungiblePositionManager as INPM} from "@aperture_finance/uni-v3-lib/src/interfaces/INonfungiblePositionManager.sol";
import {UniV3Automan} from "../../src/UniV3Automan.sol";
import "@aperture_finance/uni-v3-lib/src/LiquidityAmounts.sol";
import "../../src/libraries/OptimalSwap.sol";

contract Base is PTest {
    // using SafeTransferLib for IERC20;
    using TickMath for int24;
    using UnsafeMath for uint160;

    UniV3Automan automan;
    // Uniswap v3 position manager
    INPM constant npm = INPM(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
    address payable WETH;
    address USDC;
    address token0;
    address token1;
    uint24 constant fee = 500;

    IUniswapV3Factory factory;
    address pool;
    uint256 token0Unit;
    uint256 token1Unit;
    int24 tickSpacing;

    function initAfterFork() internal {
        factory = IUniswapV3Factory(npm.factory());
        WETH = payable(npm.WETH9());
        if (WETH < USDC) {
            token0 = WETH;
            token1 = USDC;
        } else {
            token0 = USDC;
            token1 = WETH;
        }
        pool = factory.getPool(token0, token1, fee);
        tickSpacing = IUniswapV3PoolImmutables(pool).tickSpacing();
        token0Unit = 10 ** IERC20Metadata(token0).decimals();
        token1Unit = 10 ** IERC20Metadata(token1).decimals();
    }

    function sqrtPriceX96() internal view returns (uint160 sqrtRatioX96) {
        (sqrtRatioX96, , , , , , ) = IUniswapV3PoolState(pool).slot0();
    }

    function currentTick() internal view returns (int24 tick) {
        (, tick, , , , , ) = IUniswapV3PoolState(pool).slot0();
    }

    /// @dev Normalize tick to align with tick spacing
    function matchSpacing(int24 tick) internal view returns (int24) {
        int24 _tickSpacing = tickSpacing;
        return TickBitmap.compress(tick, _tickSpacing) * _tickSpacing;
    }

    function getLiquidityForAmount0(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint256 amount0
    ) internal pure returns (uint256 liquidity) {
        if (sqrtRatioAX96 > sqrtRatioBX96)
            (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);
        uint256 intermediate = FullMath.mulDiv(
            sqrtRatioAX96,
            sqrtRatioBX96,
            FixedPoint96.Q96
        );
        return
            FullMath.mulDiv(
                amount0,
                intermediate,
                sqrtRatioBX96.sub(sqrtRatioAX96)
            );
    }

    /// @dev Identical to `LiquidityAmounts.getLiquidityForAmount1` except for the return type
    function getLiquidityForAmount1(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint256 amount1
    ) internal pure returns (uint256 liquidity) {
        if (sqrtRatioAX96 > sqrtRatioBX96)
            (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);
        return
            FullMath.mulDiv(
                amount1,
                FixedPoint96.Q96,
                sqrtRatioBX96.sub(sqrtRatioAX96)
            );
    }

    function getLiquidityForAmounts(
        uint160 sqrtRatioX96,
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint256 amount0,
        uint256 amount1
    ) internal pure returns (uint256 liquidity) {
        if (sqrtRatioAX96 > sqrtRatioBX96)
            (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);

        if (sqrtRatioX96 <= sqrtRatioAX96) {
            liquidity = getLiquidityForAmount0(
                sqrtRatioAX96,
                sqrtRatioBX96,
                amount0
            );
        } else if (sqrtRatioX96 < sqrtRatioBX96) {
            uint256 liquidity0 = getLiquidityForAmount0(
                sqrtRatioX96,
                sqrtRatioBX96,
                amount0
            );
            uint256 liquidity1 = getLiquidityForAmount1(
                sqrtRatioAX96,
                sqrtRatioX96,
                amount1
            );

            liquidity = liquidity0 < liquidity1 ? liquidity0 : liquidity1;
        } else {
            liquidity = getLiquidityForAmount1(
                sqrtRatioAX96,
                sqrtRatioBX96,
                amount1
            );
        }
    }

    function prepAmountsForLiquidity(
        uint128 initialLiquidity,
        int24 tickLower,
        int24 tickUpper
    ) internal view returns (uint256 amount0, uint256 amount1) {
        uint160 sqrtRatioAX96 = tickLower.getSqrtRatioAtTick();
        uint160 sqrtRatioBX96 = tickUpper.getSqrtRatioAtTick();
        uint160 sqrtRatio = sqrtPriceX96();
        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtRatio,
            sqrtRatioAX96,
            sqrtRatioBX96,
            uint128(
                bound(
                    initialLiquidity,
                    1,
                    IUniswapV3PoolState(pool).liquidity() / 10
                )
            )
        );
        uint256 liquidity = getLiquidityForAmounts(
            sqrtRatio,
            sqrtRatioAX96,
            sqrtRatioBX96,
            amount0,
            amount1
        );
        vm.assume(liquidity != 0);
    }

    function prepAmounts(
        uint256 amount0Desired,
        uint256 amount1Desired
    ) internal view returns (uint256, uint256) {
        address _pool = pool;
        uint256 balance0 = IERC20(token0).balanceOf(_pool);
        uint256 balance1 = IERC20(token1).balanceOf(_pool);
        amount0Desired = bound(amount0Desired, 0, balance0 / 10);
        amount1Desired = bound(amount1Desired, 0, balance1 / 10);
        if (
            amount0Desired < token0Unit / 1e3 &&
            amount1Desired < token1Unit / 1e3
        ) {
            amount0Desired = bound(
                uint256(keccak256(abi.encode(amount0Desired))),
                token0Unit / 1e3,
                balance0 / 10
            );
            amount1Desired = bound(
                uint256(keccak256(abi.encode(amount1Desired))),
                token1Unit / 1e3,
                balance1 / 10
            );
        }
        return (amount0Desired, amount1Desired);
    }

    function deal(uint256 amount0, uint256 amount1) internal {
        address _WETH = WETH;
        uint256 prevTotSup = IERC20(_WETH).totalSupply();
        uint256 prevBal = IERC20(_WETH).balanceOf(address(this));
        if (token0 == _WETH) {
            deal(_WETH, prevTotSup + amount0 - prevBal);
            deal(_WETH, address(this), amount0);
            deal(token1, address(this), amount1, true);
        } else if (token1 == _WETH) {
            deal(token0, address(this), amount0, true);
            deal(_WETH, prevTotSup + amount1 - prevBal);
            deal(_WETH, address(this), amount1);
        } else {
            deal(token0, address(this), amount0, true);
            deal(token1, address(this), amount1, true);
        }
    }

    function fixedInputs()
        internal
        view
        returns (
            uint256 amount0Desired,
            uint256 amount1Desired,
            int24 tickLower,
            int24 tickUpper
        )
    {
        int24 multiplier = 100;
        int24 tick = matchSpacing(currentTick());
        tickLower = tick - multiplier * tickSpacing;
        tickUpper = tick + multiplier * tickSpacing;
        amount0Desired = 10 ether;
        amount1Desired = 0;
        (amount0Desired, amount1Desired) = prepAmounts(
            amount0Desired,
            amount1Desired
        );
    }
}
