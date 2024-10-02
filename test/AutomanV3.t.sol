// SPDX-License-Identifier: MIT
// FOUNDRY_PROFILE=lite forge test --watch --match-contract=UniV3AutomanV3Test -vvvvv
// FOUNDRY_PROFILE=lite forge test --fork-url https://arbitrum-mainnet.infura.io/v3/170610b86c1543818b8cd1548e44ad0d --fork-block-number 259388336 --watch --match-contract=UniV3AutomanV3Test -vvvvv
pragma solidity ^0.8.0;

import {console} from "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";
import "src/UniV3Automan.sol";
import {IUniV3Automan} from "src/interfaces/IAutoman.sol";

/// @dev Test contract for UniV3AutomanV3
contract UniV3AutomanV3Test is Test {
    // the identifiers of the forks
    uint256 arbitrumFork;

    // https://book.getfoundry.sh/forge/fork-testing
    function setUp() public {
        vm.createSelectFork("arbitrum_one", 259388336);
    }

    // function testMintOptimal() public {
    //     address myWalletAddress = address(0x1fFd5d818187917E0043522C3bE583A393c2BbF7);
    //     address arbitrumUsdcAddress = address(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);
    //     address arbitrumWethAddress = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    //     address automanOwner = address(0x145304a5cfEc1B616Cf035C43f084CE1233d9Ea7);
    //     address npmAddress = address(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
    //     address controller = address(0x1Dd333d27746D2283D01C5a759cB04A0eAD821D4);
    //     address optimalSwapRouter = address(0x00000000063E0E1E06A0FE61e16bE8Bdec1BEA31);
    //     uint256 amount = 300000000000000;
    //     console.log("this address ", address(this));
    //     IERC20 usdc = IERC20(arbitrumUsdcAddress);
    //     IERC20 weth = IERC20(arbitrumWethAddress);
    //     INPM npm = INPM(npmAddress);
    //     UniV3Automan uniV3Automan = new UniV3Automan(npm, address(this));
    //     console.log("uniV3Automan.owner() ", uniV3Automan.owner());
    //     uniV3Automan.setFeeConfig(
    //         IAutomanCommon.FeeConfig({feeLimitPips: 200000000000000000, feeCollector: automanOwner})
    //     );
    //     address[] memory controllers = new address[](1);
    //     controllers[0] = controller;
    //     bool[] memory statuses = new bool[](1);
    //     statuses[0] = true;
    //     uniV3Automan.setControllers(controllers, statuses);
    //     address[] memory swapRouters = new address[](1);
    //     swapRouters[0] = optimalSwapRouter;
    //     uniV3Automan.setSwapRouters(swapRouters, statuses);
    //     console.log("automan address:", address(uniV3Automan));
    //     console.log("tommyzhao usdc allowance", usdc.allowance(myWalletAddress, address(uniV3Automan)));
    //     console.log("tommyzhao weth allowance", weth.allowance(myWalletAddress, address(uniV3Automan)));
    //     vm.prank(myWalletAddress);
    //     console.log("usdc approve, ", usdc.approve(address(uniV3Automan), amount));
    //     vm.prank(myWalletAddress);
    //     console.log("weth approve, ", weth.approve(address(uniV3Automan), amount));
    //     console.log("tommyzhao usdc allowance", usdc.allowance(myWalletAddress, address(uniV3Automan)));
    //     console.log("tommyzhao weth allowance", weth.allowance(myWalletAddress, address(uniV3Automan)));
    //     vm.prank(myWalletAddress);
    //     console.log("tommyzhao usdc balance", usdc.balanceOf(myWalletAddress));
    //     vm.prank(myWalletAddress);
    //     console.log("tommyzhao weth balance", weth.balanceOf(myWalletAddress));
    //     // UniV3Automan uniV3Automan = UniV3Automan(payable(address(0x18DBd37AC2EDF21Dd0944D2B5F19C6f711523080)));
    //     vm.prank(myWalletAddress);
    //     uniV3Automan.mintOptimal(
    //         IUniV3NPM.MintParams({
    //             token0: arbitrumWethAddress,
    //             token1: arbitrumUsdcAddress,
    //             fee: 500,
    //             tickLower: -199200,
    //             tickUpper: -197190,
    //             amount0Desired: 0, //300000000000000, // 0.0003 weth
    //             amount1Desired: 3000,
    //             amount0Min: 0,
    //             amount1Min: 0,
    //             recipient: myWalletAddress,
    //             deadline: 1757816150
    //         }),
    //         new bytes(0),
    //         /* token0FeeAmount= */ 0,
    //         /* token1FeeAmount= */ 0,
    //         /* sqrtPriceX96= */ 0
    //     );
    //     vm.prank(myWalletAddress);
    //     console.log("tommyzhao usdc balance", usdc.balanceOf(myWalletAddress));
    //     vm.prank(myWalletAddress);
    //     console.log("tommyzhao weth balance", weth.balanceOf(myWalletAddress));
    // }

    function testMintOptimalCreatePool() public {
        address myWalletAddress = address(0x1fFd5d818187917E0043522C3bE583A393c2BbF7);
        address arbitrumEthAddress = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
        address arbitrumWethAddress = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
        address arbitrumUsdcAddress = address(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);
        address arbitrumAaveAddress = address(0xba5DdD1f9d7F570dc94a51479a000E3BCE967196);
        address automanOwner = address(0x145304a5cfEc1B616Cf035C43f084CE1233d9Ea7);
        address npmAddress = address(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
        address controller = address(0x1Dd333d27746D2283D01C5a759cB04A0eAD821D4);
        address optimalSwapRouter = address(0x00000000063E0E1E06A0FE61e16bE8Bdec1BEA31);
        uint256 amount = 300000000000000;
        console.log("this address ", address(this));
        IERC20 weth = IERC20(arbitrumWethAddress);
        IERC20 usdc = IERC20(arbitrumUsdcAddress);
        IERC20 aave = IERC20(arbitrumAaveAddress);
        INPM npm = INPM(npmAddress);
        UniV3Automan uniV3Automan = new UniV3Automan(npm, address(this));
        console.log("uniV3Automan.owner() ", uniV3Automan.owner());
        uniV3Automan.setFeeConfig(
            IAutomanCommon.FeeConfig({feeLimitPips: 200000000000000000, feeCollector: automanOwner})
        );
        address[] memory controllers = new address[](1);
        controllers[0] = controller;
        bool[] memory statuses = new bool[](1);
        statuses[0] = true;
        uniV3Automan.setControllers(controllers, statuses);
        address[] memory swapRouters = new address[](1);
        swapRouters[0] = optimalSwapRouter;
        uniV3Automan.setSwapRouters(swapRouters, statuses);
        console.log("automan address:", address(uniV3Automan));
        console.log("tommyzhao usdc allowance", usdc.allowance(myWalletAddress, address(uniV3Automan)));
        console.log("tommyzhao aave allowance", aave.allowance(myWalletAddress, address(uniV3Automan)));
        vm.prank(myWalletAddress);
        console.log("usdc approve, ", usdc.approve(address(uniV3Automan), amount));
        vm.prank(myWalletAddress);
        console.log("aave approve, ", aave.approve(address(uniV3Automan), amount));
        console.log("tommyzhao usdc allowance", usdc.allowance(myWalletAddress, address(uniV3Automan)));
        console.log("tommyzhao aave allowance", aave.allowance(myWalletAddress, address(uniV3Automan)));
        deal(arbitrumWethAddress, myWalletAddress, 10000000000000 ether);
        vm.prank(myWalletAddress);
        console.log("tommyzhao weth balance", weth.balanceOf(myWalletAddress));
        vm.prank(myWalletAddress);
        console.log("tommyzhao usdc balance", usdc.balanceOf(myWalletAddress));
        vm.prank(myWalletAddress);
        console.log("tommyzhao aave balance", aave.balanceOf(myWalletAddress));
        vm.pauseGasMetering();
        // UniV3Automan uniV3Automan = UniV3Automan(payable(address(0x18DBd37AC2EDF21Dd0944D2B5F19C6f711523080)));
        vm.prank(myWalletAddress);
        uniV3Automan.mintOptimal(
            IUniV3NPM.MintParams({
                token0: arbitrumUsdcAddress,
                token1: arbitrumAaveAddress ,
                fee: 100,
                tickLower: 227000,
                tickUpper: 227100,
                amount0Desired: 3000,
                amount1Desired: 0,
                amount0Min: 0,
                amount1Min: 0,
                recipient: myWalletAddress,
                deadline: 1757816150
            }),
            new bytes(0),
            /* token0FeeAmount= */ 0,
            /* token1FeeAmount= */ 0,
            /* sqrtPriceX96= */ 9703428600000000000000000000
        );
        vm.prank(myWalletAddress);
        console.log("tommyzhao usdc balance", usdc.balanceOf(myWalletAddress));
        vm.prank(myWalletAddress);
        console.log("tommyzhao aave balance", aave.balanceOf(myWalletAddress));
    }
}
