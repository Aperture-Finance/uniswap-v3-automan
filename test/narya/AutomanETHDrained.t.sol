pragma solidity ^0.8.19;

import {Base} from "./Base.t.sol";

import {PoolAddress} from "@aperture_finance/uni-v3-lib/src/PoolAddress.sol";
import {INonfungiblePositionManager as INPM} from "@aperture_finance/uni-v3-lib/src/interfaces/INonfungiblePositionManager.sol";
import {UniV3Automan} from "../../src/UniV3Automan.sol";
import "solady/src/utils/SafeTransferLib.sol";
import "@aperture_finance/uni-v3-lib/src/PoolCaller.sol";

contract AutomanETHDrained is Base {
    using SafeTransferLib for address;

    address owner;
    address feeCollector; 

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

        vm.stopPrank();

        vm.label(address(automan), "UniV3Automan");
    }

    function testDrainETH() public {
        (, , int24 tickLower, int24 tickUpper) = fixedInputs();
        (uint256 amount0, uint256 amount1) = prepAmountsForLiquidity(
            V3PoolCallee.wrap(pool).liquidity() / 10000,
            tickLower,
            tickUpper
        );

        vm.deal(address(automan), amount1);
        deal(amount0, 0);

        token0.safeApprove(address(automan), type(uint256).max);
        token1.safeApprove(address(automan), type(uint256).max);

        vm.expectRevert();
        automan.mint(
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
                recipient: address(this),
                deadline: block.timestamp
            })
        );

        require(address(automan).balance > 0, "Automan was drained ETH !");
    }
}
