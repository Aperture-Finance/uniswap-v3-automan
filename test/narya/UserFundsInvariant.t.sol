pragma solidity ^0.8.19;

import {Base} from "./Base.t.sol";

import {WETH as IWETH} from "solady/src/tokens/WETH.sol";
import "solady/src/utils/SafeTransferLib.sol";
import {PoolAddress} from "@aperture_finance/uni-v3-lib/src/PoolAddress.sol";
import {INonfungiblePositionManager as INPM} from "@aperture_finance/uni-v3-lib/src/interfaces/INonfungiblePositionManager.sol";
import {UniV3Automan} from "../../src/UniV3Automan.sol";
import "@uniswap/v3-core/contracts/interfaces/pool/IUniswapV3PoolImmutables.sol";
import "@uniswap/v3-core/contracts/interfaces/pool/IUniswapV3PoolState.sol";
import "lib/forge-std/src/interfaces/IERC20.sol";

import {console} from "lib/forge-std/src/console.sol";

contract UserFundsInvariant is Base {
    // using SafeTransferLib for IERC20;

    uint setFeeLimit = 100;

    address owner;
    address feeCollector;
    address user;
    address user2;

    uint256[] existingIds;

    struct LogInfo {
        uint typ; // 0 unset, 1 mint, 2 remove, 3 rebalance, 4 add liquidity/reinvest, 5 remove liquidity
        uint nftBefore;
        uint token0Before;
        uint token1Before;
        uint ethBefore;
        uint nftAfter;
        uint token0After;
        uint token1After;
        uint ethAfter;
        uint128 prevLiquidity;
        uint128 newLiquidity;
    }

    LogInfo[] pnmLogs;

    function setUp() public {
        vm.createSelectFork(
            "https://eth-mainnet.g.alchemy.com/v2/FArizTRkkhtDtVJNNeoWld_SDLWyW1hw",
            17000000
        );
        USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

        initAfterFork();
        vm.label(address(npm), "npm");
        vm.label(pool, "pool");

        owner = makeAddr("Owner");
        feeCollector = makeAddr("Collector");
        user = makeAddr("User");
        user2 = makeAddr("User2");

        UniV3Automan.FeeConfig memory feeConfig = UniV3Automan.FeeConfig(
            feeCollector,
            5e16
        );

        address[] memory controllers = new address[](1);
        bool[] memory statuses = new bool[](1);
        controllers[0] = owner;
        statuses[0] = true;
        

        vm.startPrank(owner);

        automan = new UniV3Automan(
            npm,
            owner
        );

        automan.setFeeConfig(feeConfig);
        automan.setControllers(controllers, statuses);

        // automan.setFeeLimit(1e18 - 1);

        vm.stopPrank();

        vm.label(address(automan), "UniV3Automan");
        vm.label(address(this), "TestContract");
    }

    function testMintAndBurn(uint128 targetLiquidity) public {
        vm.assume(
            targetLiquidity > 0 &&
                targetLiquidity < IUniswapV3PoolState(pool).liquidity()
        );

        (, , int24 tickLower, int24 tickUpper) = fixedInputs();
        (uint256 amount0, uint256 amount1) = prepAmountsForLiquidity(
            targetLiquidity,
            tickLower,
            tickUpper
        );

        deal(amount0, amount1);

        IERC20(token0).approve(address(automan), type(uint256).max);
        IERC20(token1).approve(address(automan), type(uint256).max);

        (
            uint256 tokenId,
            uint128 liquidity,
            uint256 _amount0,
            uint256 _amount1
        ) = automan.mint(
                INPM.MintParams({
                    token0: token0,
                    token1: token1,
                    fee: fee,
                    tickLower: tickLower,
                    tickUpper: tickUpper,
                    amount0Desired: amount0,
                    amount1Desired: amount1,
                    amount0Min: 0,
                    amount1Min: 0,
                    recipient: user,
                    deadline: block.timestamp
                })
            );

        require(npm.ownerOf(tokenId) == user, "didnt mint any tokens");

        // transfer nft to someone else who will burn it
        vm.prank(user);
        npm.transferFrom(user, user2, tokenId);

        require(npm.ownerOf(tokenId) == user2, "didnt transfer successfully");

        // burn it
        vm.startPrank(user2);
        npm.setApprovalForAll(address(automan), true);

        uint beforeNFTBalance = npm.balanceOf(user2);
        uint beforeToken0Balance = IERC20(token0).balanceOf(user2);
        uint beforeToken1Balance = IERC20(token1).balanceOf(user2);
        uint beforeEthBalance = user2.balance;

        (uint __amount0, uint __amount1) = automan.removeLiquidity(
            INPM.DecreaseLiquidityParams({
                tokenId: tokenId,
                liquidity: liquidity,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp + 1 hours
            }),
            0
        );

        vm.stopPrank();

        require(
            npm.balanceOf(user2) == beforeNFTBalance - 1,
            "nft was not burned"
        );

        require(
            IERC20(token0).balanceOf(user2) > beforeToken0Balance ||
                IERC20(token1).balanceOf(user2) > beforeToken1Balance ||
                user2.balance > beforeEthBalance,
            "Didnt get back any funds"
        );
    }

    function actionMint(uint128 targetLiquidity, bool isUser1) public {
        vm.assume(
            targetLiquidity > 0 &&
                targetLiquidity < IUniswapV3PoolState(pool).liquidity()
        );

        address recipient = user;
        if (!isUser1) recipient = user2;

        (, , int24 tickLower, int24 tickUpper) = fixedInputs();
        (uint256 amount0, uint256 amount1) = prepAmountsForLiquidity(
            targetLiquidity,
            tickLower,
            tickUpper
        );

        deal(amount0, amount1);
        IERC20(token0).transfer(recipient, amount0);
        IERC20(token1).transfer(recipient, amount1);

        vm.startPrank(recipient);

        uint beforeNFTBalance = npm.balanceOf(recipient);
        uint beforeToken0Balance = IERC20(token0).balanceOf(recipient);
        uint beforeToken1Balance = IERC20(token1).balanceOf(recipient);

        require(beforeToken0Balance == amount0, "deal amount0 failed");
        require(beforeToken1Balance == amount1, "deal amount1 failed");

        IERC20(token0).approve(address(automan), type(uint256).max);
        IERC20(token1).approve(address(automan), type(uint256).max);

        INPM.MintParams memory params = INPM.MintParams({
            token0: token0,
            token1: token1,
            fee: fee,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: amount0,
            amount1Desired: amount1,
            amount0Min: 0,
            amount1Min: 0,
            recipient: recipient,
            deadline: block.timestamp
        });

        (
            uint256 tokenId,
            uint128 liquidity,
            uint256 _amount0,
            uint256 _amount1
        ) = automan.mint(params);

        vm.stopPrank();

        recordMint(
            tokenId,
            recipient,
            beforeNFTBalance,
            beforeToken0Balance,
            beforeToken1Balance
        );
    }

    function recordMint(
        uint tokenId,
        address recipient,
        uint beforeNFTBalance,
        uint beforeToken0Balance,
        uint beforeToken1Balance
    ) public {
        existingIds.push(tokenId);
        LogInfo memory info = LogInfo(
            1,
            beforeNFTBalance,
            beforeToken0Balance,
            beforeToken1Balance,
            0,
            npm.balanceOf(recipient),
            IERC20(token0).balanceOf(recipient),
            IERC20(token1).balanceOf(recipient),
            0,
            0,
            0
        );
        pnmLogs.push(info);
    }

    function actionRemoveLiquidity(uint x) public {
        vm.assume(existingIds.length > 0);
        uint tokenId = existingIds[x % existingIds.length];
        address target = npm.ownerOf(tokenId);

        (, , , , , , , uint128 liquidity, , , , ) = npm.positions(tokenId);

        vm.startPrank(target);
        npm.setApprovalForAll(address(automan), true);

        uint beforeNFTBalance = npm.balanceOf(target);
        uint beforeToken0Balance = IERC20(token0).balanceOf(target);
        uint beforeToken1Balance = IERC20(token1).balanceOf(target);
        uint beforeEthBalance = target.balance;

        (uint __amount0, uint __amount1) = automan.removeLiquidity(
            INPM.DecreaseLiquidityParams({
                tokenId: tokenId,
                liquidity: liquidity,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp + 1 hours
            }),
            0
        );

        vm.stopPrank();

        pnmLogs.push(
            LogInfo(
                2,
                beforeNFTBalance,
                beforeToken0Balance,
                beforeToken1Balance,
                beforeEthBalance,
                npm.balanceOf(target),
                IERC20(token0).balanceOf(target),
                IERC20(token1).balanceOf(target),
                target.balance,
                0,
                0
            )
        );

        // remove the tokenId
        uint[] memory _existingIds = new uint[](existingIds.length);
        for (uint i = 0; i < existingIds.length; ++i) {
            _existingIds[i] = existingIds[i];
        }
        delete existingIds;
        for (uint i = 0; i < _existingIds.length; ++i) {
            if (_existingIds[i] != tokenId) existingIds.push(_existingIds[i]);
        }
    }

    function actionRemoveLiquiditySingle(uint x, bool zeroForOne) public {
        vm.assume(existingIds.length > 0);
        uint tokenId = existingIds[x % existingIds.length];
        address target = npm.ownerOf(tokenId);

        (, , , , , , , uint128 liquidity, , , , ) = npm.positions(tokenId);

        vm.startPrank(target);
        npm.setApprovalForAll(address(automan), true);

        uint beforeNFTBalance = npm.balanceOf(target);
        uint beforeToken0Balance = IERC20(token0).balanceOf(target);
        uint beforeToken1Balance = target.balance;
        uint beforeEthBalance = target.balance;

        automan.removeLiquiditySingle(
            INPM.DecreaseLiquidityParams({
                tokenId: tokenId,
                liquidity: liquidity,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp + 1 hours
            }),
            zeroForOne,
            0,
            new bytes(0)
        );

        vm.stopPrank();

        pnmLogs.push(
            LogInfo(
                2,
                beforeNFTBalance,
                beforeToken0Balance,
                beforeToken1Balance,
                beforeEthBalance,
                npm.balanceOf(target),
                IERC20(token0).balanceOf(target),
                IERC20(token1).balanceOf(target),
                target.balance,
                0,
                0
            )
        );

        // remove the tokenId
        uint[] memory _existingIds = new uint[](existingIds.length);
        for (uint i = 0; i < existingIds.length; ++i) {
            _existingIds[i] = existingIds[i];
        }
        delete existingIds;
        for (uint i = 0; i < _existingIds.length; ++i) {
            if (_existingIds[i] != tokenId) existingIds.push(_existingIds[i]);
        }
    }

    function invariantMint() public {
        for (uint i = 0; i < pnmLogs.length; ++i) {
            LogInfo memory log = pnmLogs[i];
            if (log.typ == 1) {
                require(log.nftBefore + 1 == log.nftAfter, "no nft was minted");

                require(
                    log.token0Before > log.token0After ||
                        log.token1Before > log.token1After,
                    "no tokens were spent"
                );

                delete pnmLogs[i];
            }
        }
    }

    function invariantRemove() public {
        for (uint i = 0; i < pnmLogs.length; ++i) {
            LogInfo memory log = pnmLogs[i];
            if (log.typ == 2) {
                require(log.nftBefore - 1 == log.nftAfter, "no nft was burned");

                require(
                    log.token0Before < log.token0After ||
                        log.token1Before < log.token1After ||
                        log.ethBefore < log.ethAfter,
                    "no tokens were recovered"
                );

                delete pnmLogs[i];
            }
        }
    }

    function actionRebalance(uint x, bool zeroForOne) public {
        vm.assume(existingIds.length > 0);
        uint tokenId = existingIds[x % existingIds.length];
        address target = npm.ownerOf(tokenId);

        (, , int24 tickLower, int24 tickUpper) = fixedInputs();
        uint beforeNFTBalance = npm.balanceOf(target);

        vm.startPrank(target);

        (uint newTokenId, , , ) = automan.rebalance(
            INPM.MintParams({
                token0: token0,
                token1: token1,
                fee: fee,
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount0Desired: 0,
                amount1Desired: 0,
                amount0Min: 0,
                amount1Min: 0,
                recipient: target,
                deadline: block.timestamp
            }),
            tokenId,
            0,
            new bytes(0)
        );
        vm.stopPrank();

        uint[] memory _existingIds = new uint[](existingIds.length);
        for (uint i = 0; i < existingIds.length; ++i) {
            _existingIds[i] = existingIds[i];
        }
        delete existingIds;
        for (uint i = 0; i < _existingIds.length; ++i) {
            if (_existingIds[i] != tokenId) existingIds.push(_existingIds[i]);
        }

        existingIds.push(newTokenId);

        pnmLogs.push(
            LogInfo(
                3,
                beforeNFTBalance,
                0,
                0,
                0,
                npm.balanceOf(target),
                0,
                0,
                0,
                0,
                0
            )
        );
    }

    // decreaseLiquidity does not burn the nft (removeLiquidity does)
    // so rebalance will mint additional nft
    function invariantRebalance() public {
        for (uint i = 0; i < pnmLogs.length; ++i) {
            LogInfo memory log = pnmLogs[i];
            if (log.typ == 3) {
                require(
                    log.nftBefore + 1 == log.nftAfter,
                    "rebalance changed nft balance"
                );

                delete pnmLogs[i];
            }
        }
    }

    function actionIncreaseLiquidity(uint x, uint128 targetLiquidity) public {
        vm.assume(existingIds.length > 0);
        uint tokenId = existingIds[x % existingIds.length];
        address target = npm.ownerOf(tokenId);

        (, , int24 tickLower, int24 tickUpper) = fixedInputs();
        (uint256 amount0, uint256 amount1) = prepAmountsForLiquidity(
            targetLiquidity,
            tickLower,
            tickUpper
        );

        deal(amount0, amount1);

        uint beforeNFTBalance = npm.balanceOf(target);
        (, , , , , , , uint128 prevLiquidity, , , , ) = npm.positions(tokenId);

        (uint128 liquidity, , ) = automan.increaseLiquidity(
            INPM.IncreaseLiquidityParams({
                tokenId: tokenId,
                amount0Desired: amount0,
                amount1Desired: amount1,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            })
        );

        (, , , , , , , uint128 newLiquidity, , , , ) = npm.positions(tokenId);

        pnmLogs.push(
            LogInfo(
                4,
                beforeNFTBalance,
                0,
                0,
                0,
                npm.balanceOf(target),
                0,
                0,
                0,
                prevLiquidity,
                newLiquidity
            )
        );
    }

    function invariantIncreaseLiquidity() public {
        for (uint i = 0; i < pnmLogs.length; ++i) {
            LogInfo memory log = pnmLogs[i];
            if (log.typ == 4) {
                require(
                    log.nftBefore == log.nftAfter,
                    "increase changed nft balance"
                );

                require(
                    log.prevLiquidity < log.newLiquidity,
                    "liquidity did not increase when calling increase"
                );

                delete pnmLogs[i];
            }
        }
    }

    function actionReinvest(uint x) public {
        vm.assume(existingIds.length > 0);
        uint tokenId = existingIds[x % existingIds.length];
        address target = npm.ownerOf(tokenId);

        uint beforeNFTBalance = npm.balanceOf(target);
        (, , , , , , , uint128 prevLiquidity, , , , ) = npm.positions(tokenId);

        (uint128 liquidity, , ) = automan.reinvest(
            INPM.IncreaseLiquidityParams({
                tokenId: tokenId,
                amount0Desired: 0,
                amount1Desired: 0,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            }),
            0,
            new bytes(0)
        );

        (, , , , , , , uint128 newLiquidity, , , , ) = npm.positions(tokenId);

        pnmLogs.push(
            LogInfo(
                4,
                beforeNFTBalance,
                0,
                0,
                0,
                npm.balanceOf(target),
                0,
                0,
                0,
                prevLiquidity,
                newLiquidity
            )
        );
    }

    function actionDecreaseLiquidity(uint x, uint128 targetLiquidity) public {
        vm.assume(existingIds.length > 0);
        uint tokenId = existingIds[x % existingIds.length];
        address target = npm.ownerOf(tokenId);

        (, , , , , , , uint128 prevLiquidity, , , , ) = npm.positions(tokenId);
        vm.assume(targetLiquidity > 0 && targetLiquidity < prevLiquidity);

        vm.startPrank(target);
        npm.setApprovalForAll(address(automan), true);

        uint beforeNFTBalance = npm.balanceOf(target);
        uint beforeToken0Balance = IERC20(token0).balanceOf(target);
        uint beforeToken1Balance = IERC20(token1).balanceOf(target);
        uint beforeEthBalance = target.balance;

        (uint __amount0, uint __amount1) = automan.decreaseLiquidity(
            INPM.DecreaseLiquidityParams({
                tokenId: tokenId,
                liquidity: targetLiquidity,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp + 1 hours
            }),
            0
        );

        vm.stopPrank();

        (, , , , , , , uint128 newLiquidity, , , , ) = npm.positions(tokenId);

        pnmLogs.push(
            LogInfo(
                5,
                beforeNFTBalance,
                beforeToken0Balance,
                beforeToken1Balance,
                beforeEthBalance,
                npm.balanceOf(target),
                IERC20(token0).balanceOf(target),
                IERC20(token1).balanceOf(target),
                target.balance,
                prevLiquidity,
                newLiquidity
            )
        );
    }

    function invariantDecreaseLiquidity() public {
        for (uint i = 0; i < pnmLogs.length; ++i) {
            LogInfo memory log = pnmLogs[i];
            if (log.typ == 5) {
                require(
                    log.nftBefore == log.nftAfter,
                    "decrease liquidity changed nft balance"
                );

                require(
                    log.prevLiquidity > log.newLiquidity,
                    "liquidity did not decrease when calling decrease"
                );

                delete pnmLogs[i];
            }
        }
    }

    function actionDecreaseLiquiditySingle(
        uint x,
        uint128 targetLiquidity,
        bool zeroForOne
    ) public {
        vm.assume(existingIds.length > 0);
        uint tokenId = existingIds[x % existingIds.length];
        address target = npm.ownerOf(tokenId);

        (, , , , , , , uint128 prevLiquidity, , , , ) = npm.positions(tokenId);
        vm.assume(targetLiquidity > 0 && targetLiquidity < prevLiquidity);

        vm.startPrank(target);
        npm.setApprovalForAll(address(automan), true);

        uint beforeNFTBalance = npm.balanceOf(target);
        uint beforeToken0Balance = IERC20(token0).balanceOf(target);
        uint beforeToken1Balance = IERC20(token1).balanceOf(target);
        uint beforeEthBalance = target.balance;

        automan.decreaseLiquiditySingle(
            INPM.DecreaseLiquidityParams({
                tokenId: tokenId,
                liquidity: targetLiquidity,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp + 1 hours
            }),
            zeroForOne,
            0,
            new bytes(0)
        );

        vm.stopPrank();

        (, , , , , , , uint128 newLiquidity, , , , ) = npm.positions(tokenId);

        pnmLogs.push(
            LogInfo(
                5,
                beforeNFTBalance,
                beforeToken0Balance,
                beforeToken1Balance,
                beforeEthBalance,
                npm.balanceOf(target),
                IERC20(token0).balanceOf(target),
                IERC20(token1).balanceOf(target),
                target.balance,
                prevLiquidity,
                newLiquidity
            )
        );
    }
}
