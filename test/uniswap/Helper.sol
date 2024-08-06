// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@aperture_finance/uni-v3-lib/src/SqrtPriceMath.sol";
import "@aperture_finance/uni-v3-lib/src/TernaryLib.sol";

abstract contract Helper {
    using UnsafeMath for uint160;
    using TernaryLib for *;

    /// @notice Equivalent to the ternary operator: `condition ? a : b`
    function ternary(bool condition, uint256 a, uint256 b) internal pure returns (uint256) {
        return condition.ternary(a, b);
    }

    /// @notice Equivalent to the ternary operator: `condition ? a : b`
    function ternary(bool condition, address a, address b) internal pure returns (address) {
        return condition.ternary(a, b);
    }

    /// @notice Equivalent to: `condition ? (b, a) : (a, b)`
    function switchIf(bool condition, address a, address b) internal pure returns (address, address) {
        return condition.switchIf(a, b);
    }

    /// @notice Sorts two uint160s and returns them in ascending order
    function sort2(uint160 a, uint160 b) internal pure returns (uint160, uint160) {
        return a.sort2U160(b);
    }

    /// @dev Identical to `LiquidityAmounts.getLiquidityForAmount0` except for the return type
    function getLiquidityForAmount0(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint256 amount0
    ) internal pure returns (uint256 liquidity) {
        (sqrtRatioAX96, sqrtRatioBX96) = sort2(sqrtRatioAX96, sqrtRatioBX96);
        uint256 intermediate = FullMath.mulDiv(sqrtRatioAX96, sqrtRatioBX96, FixedPoint96.Q96);
        return FullMath.mulDiv(amount0, intermediate, sqrtRatioBX96.sub(sqrtRatioAX96));
    }

    /// @dev Identical to `LiquidityAmounts.getLiquidityForAmount1` except for the return type
    function getLiquidityForAmount1(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint256 amount1
    ) internal pure returns (uint256 liquidity) {
        (sqrtRatioAX96, sqrtRatioBX96) = sort2(sqrtRatioAX96, sqrtRatioBX96);
        return FullMath.mulDiv(amount1, FixedPoint96.Q96, sqrtRatioBX96.sub(sqrtRatioAX96));
    }

    /// @dev Identical to `LiquidityAmounts.getLiquidityForAmounts` except for the return type
    function getLiquidityForAmounts(
        uint160 sqrtRatioX96,
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint256 amount0,
        uint256 amount1
    ) internal pure returns (uint256 liquidity) {
        (sqrtRatioAX96, sqrtRatioBX96) = sort2(sqrtRatioAX96, sqrtRatioBX96);

        if (sqrtRatioX96 <= sqrtRatioAX96) {
            liquidity = getLiquidityForAmount0(sqrtRatioAX96, sqrtRatioBX96, amount0);
        } else if (sqrtRatioX96 < sqrtRatioBX96) {
            uint256 liquidity0 = getLiquidityForAmount0(sqrtRatioX96, sqrtRatioBX96, amount0);
            uint256 liquidity1 = getLiquidityForAmount1(sqrtRatioAX96, sqrtRatioX96, amount1);

            liquidity = liquidity0 < liquidity1 ? liquidity0 : liquidity1;
        } else {
            liquidity = getLiquidityForAmount1(sqrtRatioAX96, sqrtRatioBX96, amount1);
        }
    }
}
