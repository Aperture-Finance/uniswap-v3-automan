// pragma solidity ^0.8.19;

// import {Base} from "./Base.t.sol";

// import {PoolAddress} from "../../src/libraries/uniswap/PoolAddress.sol";
// import {INonfungiblePositionManager as INPM} from "../../src/interfaces/INonfungiblePositionManager.sol";
// import {UniV3Automan} from "../../src/UniV3Automan.sol";

// contract ArbitraryCall is Base {
//     address owner; 
//     address feeCollector;
//     NaryaRouter naryaRouter;

//     function setUp() public { 
//         vm.createSelectFork(
//             "https://eth-mainnet.g.alchemy.com/v2/FArizTRkkhtDtVJNNeoWld_SDLWyW1hw",
//             17000000
//         );
//         USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

//         initAfterFork();
//         vm.label(address(npm), "npm");
//         vm.label(pool, "pool");

//         owner = makeAddr("Owner");
//         feeCollector = makeAddr("Collector");

//         UniV3Automan.FeeConfig memory feeConfig = UniV3Automan.FeeConfig(
//             5e16,
//             feeCollector
//         );

//         vm.startPrank(owner);

//         automan = new UniV3Automan(
//             npm,
//             owner,
//             owner, // controller
//             feeConfig
//         );

//         naryaRouter = new NaryaRouter();

//         address[] memory addresses = new address[](1);
//         addresses[0] = address(naryaRouter);

//         bool[] memory statuses = new bool[](1);
//         statuses[0] = true;

//         automan.setSwapRouters(addresses, statuses);

//         vm.stopPrank();

//         vm.label(address(automan), "UniV3Automan");
//     }

//     /*  
//     function testArbitraryCall() public {
//         invariantArbitraryCall();
//     } 
//     */

//     // invariant is that we assume this function call will fail
//     // if it doesn't fail and return a precise message
//     // then it is an controllable arbitrary function call
//     /*
//     function invariantArbitraryCall() public {
//         uint tokenId = npm.tokenByIndex(0);
//         // console.log("id", tokenId);

//         (uint96 nonce, address operator, address _token0, address _token1, uint24 _fee, int24 tickLower, int24 tickUpper, uint128 liquidity, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128, uint128 tokensOwed0, uint128 tokensOwed1) = npm.positions(tokenId);

//         // console.log("token0", _token0);
//         // console.log("token1", _token1);
//         // console.log("fee", _fee);

//         INPM.MintParams memory params;
//         params.amount0Desired = 0;
//         params.amount1Desired = 0;
//         params.token0 = _token0;
//         params.token1 = _token1;
//         params.fee = _fee;
//         params.tickLower = tickLower;
//         params.tickUpper = tickUpper;
//         params.deadline = block.timestamp + 1 hours;

//         address router = address(naryaRouter);
        
//         bytes memory swapData = abi.encodePacked(
//             router,
//             abi.encodeWithSelector(NaryaRouter.arbitraryCall.selector, 42)
//         );

//         try automan.mintOptimal(params, swapData) returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) {

//         } catch Error(string memory reason) {
//             if (keccak256(abi.encodePacked(reason)) == keccak256(abi.encodePacked("arbitrary call"))) {
//                 require(false, "arbitrary call inside NaryaRouter was called");
//             }
//         }
//     }
//     */
// }

// contract NaryaRouter {
//     function arbitraryCall(uint256 a) external {
//         require(a != 42, "arbitrary call");
//     }
// }
