// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {NPMCaller, Position, SlipStreamPosition} from "@aperture_finance/uni-v3-lib/src/NPMCaller.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "src/interfaces/IAutoman.sol";
import "solady/src/utils/SafeTransferLib.sol";
import {UniBase} from "./UniBase.sol";
import {TickMath} from "src/libraries/OptimalSwap.sol";

// https://book.getfoundry.sh/forge/invariant-testing#handler-based-testing
contract UniHandler is UniBase {
    using SafeTransferLib for address;
    using TickMath for int24;
    using EnumerableSet for EnumerableSet.UintSet;

    IAutomanCommon internal automan;
    EnumerableSet.UintSet internal _tokenIds;
    mapping(bytes32 => uint256) internal calls;

    function countCall(bytes32 key) internal {
        calls[key]++;
    }

    function callSummary() public view {
        console2.log("Call summary:");
        console2.log("-------------------");
        console2.log("mint", calls["mint"]);
        console2.log("mintOptimal", calls["mintOptimal"]);
        console2.log("increaseLiquidity", calls["increaseLiquidity"]);
        console2.log("increaseLiquidityOptimal", calls["increaseLiquidityOptimal"]);
        console2.log("decreaseLiquidity", calls["decreaseLiquidity"]);
        console2.log("decreaseLiquiditySingle", calls["decreaseLiquiditySingle"]);
        console2.log("removeLiquidity", calls["removeLiquidity"]);
        console2.log("removeLiquiditySingle", calls["removeLiquiditySingle"]);
        console2.log("reinvest", calls["reinvest"]);
        console2.log("rebalance", calls["rebalance"]);
        console2.log("swapBackAndForth", calls["swapBackAndForth"]);
    }

    function init(IAutomanCommon _automan, DEX _dex) public {
        dex = _dex;
        initBeforeFork();
        initAfterFork();
        automan = _automan;
    }

    /************************************************
     *  INTERNAL ACTIONS
     ***********************************************/

    /// @dev Select an existing tokenId
    function selectTokenId(uint256 tokenId) internal view returns (uint256) {
        if (!_tokenIds.contains(tokenId)) {
            uint256 length = _tokenIds.length();
            if (length != 0) return _tokenIds.at(tokenId % length);
        }
        return 0;
    }

    /// @dev Deal token0 and token1 with special care for WETH
    /// @dev The `totalSupply` of WETH doesn't use storage. Can't adjust with `deal`.
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

    /// @dev Mint a v3 LP position through Automan
    function _mint(
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Desired,
        uint256 amount1Desired,
        bool sendValue
    ) internal returns (uint256 tokenId) {
        deal(amount0Desired, amount1Desired);
        token0.safeApprove(address(automan), type(uint256).max);
        token1.safeApprove(address(automan), type(uint256).max);
        uint256 value = sendValue ? handleWETH(amount0Desired, amount1Desired) : 0;
        (bool ok, uint128 liquidity) = prepLiquidity(tickLower, tickUpper, amount0Desired, amount1Desired);
        if (ok)
            if (dex == DEX.SlipStream) {
                try
                    IAutomanSlipStreamMintRebalance(address(automan)).mint{value: value}(
                        ISlipStreamNPM.MintParams({
                            token0: token0,
                            token1: token1,
                            tickSpacing: tickSpacingSlipStream,
                            tickLower: tickLower,
                            tickUpper: tickUpper,
                            amount0Desired: amount0Desired,
                            amount1Desired: amount1Desired,
                            amount0Min: 0,
                            amount1Min: 0,
                            recipient: recipient,
                            deadline: block.timestamp,
                            sqrtPriceX96: 0
                        })
                    )
                returns (uint256 _tokenId, uint128 _liquidity, uint256, uint256) {
                    tokenId = _tokenId;
                    assertEq(_liquidity, liquidity, "liquidity mismatch");
                } catch Error(string memory reason) {
                    assertEq(reason, "LO", "only catch liquidity overflow");
                }
            } else {
                try
                    IAutomanUniV3MintRebalance(address(automan)).mint{value: value}(
                        IUniV3NPM.MintParams({
                            token0: token0,
                            token1: token1,
                            fee: fee,
                            tickLower: tickLower,
                            tickUpper: tickUpper,
                            amount0Desired: amount0Desired,
                            amount1Desired: amount1Desired,
                            amount0Min: 0,
                            amount1Min: 0,
                            recipient: recipient,
                            deadline: block.timestamp
                        })
                    )
                returns (uint256 _tokenId, uint128 _liquidity, uint256, uint256) {
                    tokenId = _tokenId;
                    assertEq(_liquidity, liquidity, "liquidity mismatch");
                } catch Error(string memory reason) {
                    assertEq(reason, "LO", "only catch liquidity overflow");
                }
            }
    }

    /// @dev Mint a v3 LP position with built-in optimal swap
    function _mintOptimal(
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Desired,
        uint256 amount1Desired,
        bytes memory swapData
    ) internal returns (uint256 tokenId, uint128 liquidity) {
        deal(amount0Desired, amount1Desired);
        token0.safeApprove(address(automan), type(uint256).max);
        token1.safeApprove(address(automan), type(uint256).max);
        uint256 value = handleWETH(amount0Desired, amount1Desired);
        if (dex == DEX.SlipStream) {
            try
                IAutomanSlipStreamMintRebalance(address(automan)).mintOptimal{value: value}(
                    ISlipStreamNPM.MintParams({
                        token0: token0,
                        token1: token1,
                        tickSpacing: tickSpacingSlipStream,
                        tickLower: tickLower,
                        tickUpper: tickUpper,
                        amount0Desired: amount0Desired,
                        amount1Desired: amount1Desired,
                        amount0Min: 0,
                        amount1Min: 0,
                        recipient: recipient,
                        deadline: block.timestamp,
                        sqrtPriceX96: 0
                    }),
                    swapData,
                    /* token0FeeAmount= */ 0,
                    /* token1FeeAmount= */ 0
                )
            returns (uint256 _tokenId, uint128 _liquidity, uint256, uint256) {
                tokenId = _tokenId;
                liquidity = _liquidity;
            } catch Error(string memory reason) {
                assertEq(reason, "LO", "only catch liquidity overflow");
            }
        } else {
            try
                IAutomanUniV3MintRebalance(address(automan)).mintOptimal{value: value}(
                    IUniV3NPM.MintParams({
                        token0: token0,
                        token1: token1,
                        fee: fee,
                        tickLower: tickLower,
                        tickUpper: tickUpper,
                        amount0Desired: amount0Desired,
                        amount1Desired: amount1Desired,
                        amount0Min: 0,
                        amount1Min: 0,
                        recipient: recipient,
                        deadline: block.timestamp
                    }),
                    swapData,
                    /* token0FeeAmount= */ 0,
                    /* token1FeeAmount= */ 0
                )
            returns (uint256 _tokenId, uint128 _liquidity, uint256, uint256) {
                tokenId = _tokenId;
                liquidity = _liquidity;
            } catch Error(string memory reason) {
                assertEq(reason, "LO", "only catch liquidity overflow");
            }
        }
    }

    /// @dev Increase liquidity of a v3 LP position through Automan
    function _increaseLiquidity(
        uint256 tokenId,
        uint256 amount0Desired,
        uint256 amount1Desired,
        bool sendValue
    ) internal returns (uint128) {
        deal(amount0Desired, amount1Desired);
        token0.safeApprove(address(automan), type(uint256).max);
        token1.safeApprove(address(automan), type(uint256).max);
        uint256 value = sendValue ? handleWETH(amount0Desired, amount1Desired) : 0;
        int24 tickLower;
        int24 tickUpper;
        uint128 posLiquidity;
        if (dex == DEX.SlipStream) {
            SlipStreamPosition memory pos = NPMCaller.positionsSlipStream(npm, tokenId);
            tickLower = pos.tickLower;
            tickUpper = pos.tickUpper;
            posLiquidity = pos.liquidity;
        } else {
            Position memory pos = NPMCaller.positions(npm, tokenId);
            tickLower = pos.tickLower;
            tickUpper = pos.tickUpper;
            posLiquidity = pos.liquidity;
        }
        (bool ok, uint128 liquidity) = prepLiquidity(tickLower, tickUpper, amount0Desired, amount1Desired);
        if (ok && (uint256(liquidity) + posLiquidity) <= type(uint128).max)
            try
                automan.increaseLiquidity{value: value}(
                    INPM.IncreaseLiquidityParams({
                        tokenId: tokenId,
                        amount0Desired: amount0Desired,
                        amount1Desired: amount1Desired,
                        amount0Min: 0,
                        amount1Min: 0,
                        deadline: block.timestamp
                    })
                )
            returns (uint128 _liquidity, uint256, uint256) {
                assertEq(_liquidity, liquidity, "liquidity mismatch");
                return liquidity;
            } catch Error(string memory reason) {
                assertEq(reason, "LO", "only catch liquidity overflow");
            }
        return 0;
    }

    /// @dev Increase liquidity with built-in optimal swap
    function _increaseLiquidityOptimal(
        uint256 tokenId,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) internal returns (uint128 liquidity) {
        deal(amount0Desired, amount1Desired);
        token0.safeApprove(address(automan), type(uint256).max);
        token1.safeApprove(address(automan), type(uint256).max);
        uint256 value = handleWETH(amount0Desired, amount1Desired);
        try
            automan.increaseLiquidityOptimal{value: value}(
                INPM.IncreaseLiquidityParams({
                    tokenId: tokenId,
                    amount0Desired: amount0Desired,
                    amount1Desired: amount1Desired,
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: block.timestamp
                }),
                /* swapData= */ new bytes(0),
                /* token0FeeAmount= */ 0,
                /* token1FeeAmount= */ 0
            )
        returns (uint128 _liquidity, uint256, uint256) {
            liquidity = _liquidity;
        } catch Error(string memory reason) {
            assertEq(reason, "LO", "only catch liquidity overflow");
        }
    }

    /// @dev Decrease liquidity of a v3 LP position through Automan
    function _decreaseLiquidity(
        uint256 tokenId,
        uint128 liquidityDelta,
        uint256 token0FeeAmount,
        uint256 token1FeeAmount
    ) internal returns (uint256 amount0, uint256 amount1) {
        (amount0, amount1) = automan.decreaseLiquidity(
            INPM.DecreaseLiquidityParams(tokenId, liquidityDelta, 0, 0, block.timestamp),
            token0FeeAmount,
            token1FeeAmount,
            /* isUnwrapNative= */ true
        );
    }

    /// @dev Decrease liquidity of a v3 LP position and withdrawing a single token
    function _decreaseLiquiditySingle(
        uint256 tokenId,
        uint128 liquidityDelta,
        bool zeroForOne,
        uint256 token0FeeAmount,
        uint256 token1FeeAmount
    ) internal returns (uint256 amount) {
        (, , address token0, address token1, , , , , , , , ) = IUniV3NPM(address(npm)).positions(tokenId);
        amount = automan.decreaseLiquidityToTokenOut(
            // amountMins are used as feeAmounts due to stack too deep compiler error.
            INPM.DecreaseLiquidityParams(tokenId, liquidityDelta, token0FeeAmount, token1FeeAmount, block.timestamp),
            /* tokenOut= */ zeroForOne ? token1 : token0,
            /* tokenOutMin= */ 0,
            /* swapData0= */ new bytes(0),
            /* swapData1= */ new bytes(0),
            /* isUnwrapNative= */ true
        );
    }

    /// @dev Decrease liquidity of a v3 LP position and withdrawing a single token
    function _decreaseLiquidityToTokenOut(
        uint256 tokenId,
        uint128 liquidityDelta,
        address tokenOut,
        uint256 token0FeeAmount,
        uint256 token1FeeAmount
    ) internal returns (uint256 amount) {
        amount = automan.decreaseLiquidityToTokenOut(
            // amountMins are used as feeAmounts due to stack too deep compiler error.
            INPM.DecreaseLiquidityParams(tokenId, liquidityDelta, token0FeeAmount, token1FeeAmount, block.timestamp),
            tokenOut,
            /* tokenOutMin= */ 0,
            /* swapData0= */ new bytes(0),
            /* swapData1= */ new bytes(0),
            /* isUnwrapNative= */ true
        );
    }

    /// @dev Remove liquidity of a v3 LP position through Automan
    function _removeLiquidity(
        uint256 tokenId,
        uint256 token0FeeAmount,
        uint256 token1FeeAmount
    ) internal returns (uint256 amount0, uint256 amount1) {
        (, , , , , , , uint128 liquidity, , , , ) = IUniV3NPM(address(npm)).positions(tokenId);
        (amount0, amount1) = automan.decreaseLiquidity(
            INPM.DecreaseLiquidityParams({
                tokenId: tokenId,
                liquidity: liquidity,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            }),
            token0FeeAmount,
            token1FeeAmount,
            /* isUnwrapNative= */ true
        );
    }

    /// @dev Remove liquidity of a v3 LP position and withdrawing a single token
    function _removeLiquiditySingle(
        uint256 tokenId,
        bool zeroForOne,
        uint256 token0FeeAmount,
        uint256 token1FeeAmount
    ) internal returns (uint256 amount) {
        (, , address token0, address token1, , , , uint128 liquidity, , , , ) = IUniV3NPM(address(npm)).positions(
            tokenId
        );
        amount = automan.decreaseLiquidityToTokenOut(
            INPM.DecreaseLiquidityParams({
                tokenId: tokenId,
                liquidity: liquidity,
                // amountMins are used as feeAmounts due to stack too deep compiler error.
                amount0Min: token0FeeAmount,
                amount1Min: token1FeeAmount,
                deadline: block.timestamp
            }),
            /* tokenOut= */ zeroForOne ? token1 : token0,
            /* tokenOutMin= */ 0,
            /* swapData0= */ new bytes(0),
            /* swapData1= */ new bytes(0),
            /* isUnwrapNative= */ true
        );
    }

    /// @dev Reinvest fees
    function _reinvest(
        uint256 tokenId,
        uint256 token0FeeAmount,
        uint256 token1FeeAmount
    ) internal returns (uint128 liquidity) {
        (liquidity, , ) = automan.reinvest(
            INPM.IncreaseLiquidityParams({
                tokenId: tokenId,
                amount0Desired: 0,
                amount1Desired: 0,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            }),
            token0FeeAmount,
            token1FeeAmount,
            new bytes(0)
        );
    }

    /// @dev Reinvest fees
    function _reinvest(
        uint256 tokenId,
        uint256 token0FeeAmount,
        uint256 token1FeeAmount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal returns (uint128 liquidity) {
        (liquidity, , ) = automan.reinvest(
            INPM.IncreaseLiquidityParams({
                tokenId: tokenId,
                amount0Desired: 0,
                amount1Desired: 0,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            }),
            token0FeeAmount,
            token1FeeAmount,
            new bytes(0),
            deadline,
            v,
            r,
            s
        );
    }

    function _rebalance(
        uint256 tokenId,
        int24 tickLower,
        int24 tickUpper,
        uint256 token0FeeAmount,
        uint256 token1FeeAmount
    ) internal returns (uint256 newTokenId) {
        if (dex == DEX.SlipStream) {
            (newTokenId, , , ) = IAutomanSlipStreamMintRebalance(address(automan)).rebalance(
                ISlipStreamNPM.MintParams({
                    token0: token0,
                    token1: token1,
                    tickSpacing: tickSpacingSlipStream,
                    tickLower: tickLower,
                    tickUpper: tickUpper,
                    amount0Desired: 0,
                    amount1Desired: 0,
                    amount0Min: 0,
                    amount1Min: 0,
                    recipient: address(0),
                    deadline: block.timestamp,
                    sqrtPriceX96: 0
                }),
                tokenId,
                token0FeeAmount,
                token1FeeAmount,
                new bytes(0)
            );
        } else {
            (newTokenId, , , ) = IAutomanUniV3MintRebalance(address(automan)).rebalance(
                IUniV3NPM.MintParams({
                    token0: token0,
                    token1: token1,
                    fee: fee,
                    tickLower: tickLower,
                    tickUpper: tickUpper,
                    amount0Desired: 0,
                    amount1Desired: 0,
                    amount0Min: 0,
                    amount1Min: 0,
                    recipient: address(0),
                    deadline: block.timestamp
                }),
                tokenId,
                token0FeeAmount,
                token1FeeAmount,
                new bytes(0)
            );
        }
    }

    /************************************************
     *  HANDLER FUNCTIONS
     ***********************************************/

    /// @dev Mint a v3 LP position through Automan
    function mint(
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Desired,
        uint256 amount1Desired,
        bool sendValue
    ) public returns (uint256 tokenId) {
        if (recipient.code.length != 0) return 0;
        (tickLower, tickUpper) = prepTicks(tickLower, tickUpper);
        (amount0Desired, amount1Desired) = prepAmounts(amount0Desired, amount1Desired);
        tokenId = _mint(recipient, tickLower, tickUpper, amount0Desired, amount1Desired, sendValue);
        if (tokenId != 0) {
            _tokenIds.add(tokenId);
            countCall("mint");
        }
    }

    /// @dev Mint a v3 LP position with built-in optimal swap
    function mintOptimal(
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) public returns (uint256 tokenId) {
        if (recipient.code.length != 0) return 0;
        (tickLower, tickUpper) = prepTicks(tickLower, tickUpper);
        (amount0Desired, amount1Desired) = prepAmounts(amount0Desired, amount1Desired);
        (tokenId, ) = _mintOptimal(recipient, tickLower, tickUpper, amount0Desired, amount1Desired, new bytes(0));
        if (tokenId != 0) {
            _tokenIds.add(tokenId);
            countCall("mintOptimal");
        }
    }

    /// @dev Increase liquidity of a v3 LP position through Automan
    function increaseLiquidity(
        uint256 tokenId,
        uint256 amount0Desired,
        uint256 amount1Desired,
        bool sendValue
    ) public returns (uint128 liquidity) {
        tokenId = selectTokenId(tokenId);
        if (tokenId != 0) {
            (amount0Desired, amount1Desired) = prepAmounts(amount0Desired, amount1Desired);
            liquidity = _increaseLiquidity(tokenId, amount0Desired, amount1Desired, sendValue);
            if (liquidity != 0) countCall("increaseLiquidity");
        }
    }

    /// @dev Increase liquidity with built-in optimal swap
    function increaseLiquidityOptimal(
        uint256 tokenId,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) public returns (uint128 liquidity) {
        tokenId = selectTokenId(tokenId);
        if (tokenId != 0) {
            (amount0Desired, amount1Desired) = prepAmounts(amount0Desired, amount1Desired);
            liquidity = _increaseLiquidityOptimal(tokenId, amount0Desired, amount1Desired);
            if (liquidity != 0) countCall("increaseLiquidityOptimal");
        }
    }

    /// @dev Decrease liquidity of a v3 LP position through Automan
    function decreaseLiquidity(
        uint256 tokenId,
        uint128 liquidityDelta
    ) public returns (uint256 amount0, uint256 amount1) {
        tokenId = selectTokenId(tokenId);
        if (tokenId != 0) {
            (, , , , , , , uint128 liquidity, , , , ) = IUniV3NPM(address(npm)).positions(tokenId);
            if (liquidity != 0) {
                liquidityDelta = uint128(bound(liquidityDelta, 1, liquidity));
                vm.prank(NPMCaller.ownerOf(npm, tokenId));
                npm.approve(address(automan), tokenId);
                (amount0, amount1) = _decreaseLiquidity(
                    tokenId,
                    liquidityDelta,
                    /* token0FeeAmount= */ 0,
                    /* token1FeeAmount= */ 0
                );
                countCall("decreaseLiquidity");
            }
        }
    }

    /// @dev Decrease liquidity of a v3 LP position and withdrawing a single token
    function decreaseLiquiditySingle(
        uint256 tokenId,
        uint128 liquidityDelta,
        bool zeroForOne
    ) public returns (uint256 amount) {
        tokenId = selectTokenId(tokenId);
        if (tokenId != 0) {
            (, , , , , , , uint128 liquidity, , , , ) = IUniV3NPM(address(npm)).positions(tokenId);
            if (liquidity != 0) {
                liquidityDelta = uint128(bound(liquidityDelta, 1, liquidity));
                vm.prank(NPMCaller.ownerOf(npm, tokenId));
                npm.approve(address(automan), tokenId);
                amount = _decreaseLiquiditySingle(
                    tokenId,
                    liquidityDelta,
                    zeroForOne,
                    /* token0FeeAmount= */ 0,
                    /* token1FeeAmount= */ 0
                );
                countCall("decreaseLiquiditySingle");
            }
        }
    }

    /// @dev Remove liquidity of a v3 LP position through Automan
    function removeLiquidity(uint256 tokenId) public returns (uint256 amount0, uint256 amount1) {
        tokenId = selectTokenId(tokenId);
        if (tokenId != 0) {
            (, , , , , , , uint128 liquidity, , , , ) = IUniV3NPM(address(npm)).positions(tokenId);
            if (liquidity != 0) {
                vm.prank(NPMCaller.ownerOf(npm, tokenId));
                npm.approve(address(automan), tokenId);
                (amount0, amount1) = _decreaseLiquidity(
                    tokenId,
                    liquidity,
                    /* token0FeeAmount= */ 0,
                    /* token1FeeAmount= */ 0
                );
                _tokenIds.remove(tokenId);
                countCall("decreaseLiquidity");
            }
        }
    }

    /// @dev Remove liquidity of a v3 LP position and withdrawing a single token
    function removeLiquiditySingle(uint256 tokenId, bool zeroForOne) public returns (uint256 amount) {
        tokenId = selectTokenId(tokenId);
        if (tokenId != 0) {
            (, , , , , , , uint128 liquidity, , , , ) = IUniV3NPM(address(npm)).positions(tokenId);
            if (liquidity != 0) {
                vm.prank(NPMCaller.ownerOf(npm, tokenId));
                npm.approve(address(automan), tokenId);
                amount = _decreaseLiquiditySingle(
                    tokenId,
                    liquidity,
                    zeroForOne,
                    /* token0FeeAmount= */ 0,
                    /* token1FeeAmount= */ 0
                );
                _tokenIds.remove(tokenId);
                countCall("decreaseLiquiditySingle");
            }
        }
    }

    /// @dev Reinvest fees
    function reinvest(uint256 tokenId) public {
        tokenId = selectTokenId(tokenId);
        if (tokenId != 0) {
            (
                ,
                ,
                ,
                ,
                ,
                int24 tickLower,
                int24 tickUpper,
                ,
                uint256 feeGrowthInside0LastX128,
                uint256 feeGrowthInside1LastX128,
                ,

            ) = IUniV3NPM(address(npm)).positions(tokenId);
            vm.prank(address(npm));
            IUniswapV3Pool(pool).burn(tickLower, tickUpper, 0);
            (, uint256 _feeGrowthInside0LastX128, uint256 _feeGrowthInside1LastX128, , ) = IUniswapV3Pool(pool)
                .positions(keccak256(abi.encodePacked(address(npm), tickLower, tickUpper)));
            if (
                _feeGrowthInside0LastX128 != feeGrowthInside0LastX128 ||
                _feeGrowthInside1LastX128 != feeGrowthInside1LastX128
            ) {
                vm.prank(NPMCaller.ownerOf(npm, tokenId));
                npm.approve(address(automan), tokenId);
                _reinvest(tokenId, /* token0FeeAmount= */ 0, /* token1FeeAmount= */ 0);
                countCall("reinvest");
            }
        }
    }

    /// @dev Rebalance a v3 LP position through Automan
    function rebalance(uint256 tokenId, int24 tickLower, int24 tickUpper) public returns (uint256 newTokenId) {
        tokenId = selectTokenId(tokenId);
        if (tokenId != 0) {
            (tickLower, tickUpper) = prepTicks(tickLower, tickUpper);
            vm.prank(NPMCaller.ownerOf(npm, tokenId));
            npm.approve(address(automan), tokenId);
            newTokenId = _rebalance(tokenId, tickLower, tickUpper, /* token0FeeAmount= */ 0, /* token1FeeAmount= */ 0);
            _tokenIds.remove(tokenId);
            _tokenIds.add(newTokenId);
            countCall("rebalance");
        }
    }

    /// @dev Swap twice and return to the initial price to generate some fees
    function swapBackAndForth(uint256 amountIn, bool zeroForOne) public {
        uint160 initialPrice = sqrtPriceX96();
        if (zeroForOne) {
            uint256 balance = IERC20(token0).balanceOf(pool);
            amountIn = bound(amountIn, balance / 50, balance / 10);
            deal(token0, address(this), amountIn);
            (, int256 amount1) = IUniswapV3Pool(pool).swap(
                address(this),
                true,
                int256(amountIn),
                TickMath.MIN_SQRT_RATIO + 1,
                new bytes(0)
            );
            amountIn = uint256(-amount1) * 2;
            deal(token1, address(this), amountIn);
            // Swap back to the initial price
            IUniswapV3Pool(pool).swap(address(this), false, int256(amountIn), initialPrice, new bytes(0));
        } else {
            uint256 balance = IERC20(token1).balanceOf(pool);
            amountIn = bound(amountIn, balance / 50, balance / 10);
            deal(token1, address(this), amountIn);
            (int256 amount0, ) = IUniswapV3Pool(pool).swap(
                address(this),
                false,
                int256(amountIn),
                TickMath.MAX_SQRT_RATIO - 1,
                new bytes(0)
            );
            amountIn = uint256(-amount0) * 2;
            deal(token0, address(this), amountIn);
            // Swap back to the initial price
            IUniswapV3Pool(pool).swap(address(this), true, int256(amountIn), initialPrice, new bytes(0));
        }
        countCall("swapBackAndForth");
    }
}
