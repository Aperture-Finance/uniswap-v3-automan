// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Script.sol";
import "./ICreate2Deployer.sol";
import "../src/UniV3OptimalSwapRouter.sol";
import {UniV3Automan} from "../src/UniV3Automan.sol";

contract DeployUniV3Automan is Script {
    struct DeployParams {
        // Has to be alphabetically ordered per https://book.getfoundry.sh/cheatcodes/parse-json
        address controller;
        UniV3Automan.FeeConfig feeConfig;
        INPM npm;
        address optimalSwapRouter; // Deploy optimal swap router if parsed as address(0).
        address owner;
    }

    // https://github.com/pcaversaccio/create2deployer
    Create2Deployer internal constant create2deployer = Create2Deployer(0x13b0D85CcB8bf860b6b79AF3029fCA081AE9beF2);
    bytes32 internal constant automanSalt = 0xbeef63ae5a2102506e8a352a5bb32aa8b30b3112e429609defd54e2600050000; // mainnet, arbitrum_one, optimism, and polygon
    // bytes32 internal constant automanSalt = 0xbeef63ae5a2102506e8a352a5bb32aa8b30b31126da13df7e082a0874b020028; // base
    // bytes32 internal constant automanSalt = 0xbeef63ae5a2102506e8a352a5bb32aa8b30b3112350766a71aff01bd0a000040; // bnb
    // bytes32 internal constant automanSalt = 0xbeef63ae5a2102506e8a352a5bb32aa8b30b31129e5100c6f38046891d010080; // avalanche
    // bytes32 internal constant automanSalt = 0xbeef63ae5a2102506e8a352a5bb32aa8b30b31127d2397bf1d3d45097b00002c; // scroll
    // bytes32 internal constant automanSalt = 0xbeef63ae5a2102506e8a352a5bb32aa8b30b311279cd7418ade4641cb50000e0; // manta
    bytes32 internal constant optimalSwapSalt = 0xbeef63ae5a2102506e8a352a5bb32aa8b30b31127dfc30de0987800003da9a65;
    bytes32 internal constant routerProxySalt = 0xbeef63ae5a2102506e8a352a5bb32aa8b30b3112bc2281f12f80c0000280f6fd;

    // https://book.getfoundry.sh/tutorials/best-practices#scripts
    function readInput(string memory input) internal view returns (string memory) {
        string memory inputDir = string.concat(vm.projectRoot(), "/script/UniV3Automan_input/");
        // Read chain id from the current node connection.
        string memory chainDir = string.concat(vm.toString(block.chainid), "/");
        string memory file = string.concat(input, ".json");
        return vm.readFile(string.concat(inputDir, chainDir, file));
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Start broadcasting transactions with the deployer as tx origin.
        vm.startBroadcast(deployerPrivateKey);

        // Fetch deployer address.
        (, address msgSender, address txOrigin) = vm.readCallers();
        console2.log("Deploying on chain id %d, using MsgSender: %s TxOrigin: %s", block.chainid, msgSender, txOrigin);

        // Load configuration from `automan_params.json`.
        string memory json = readInput("automan_params");
        console.log("Deploying automan with params: %s", json);
        DeployParams memory params = abi.decode(vm.parseJson(json), (DeployParams));

        // Conditionally deploy optimalSwapRouter.
        bytes memory initCode;
        bytes32 initCodeHash;
        if (params.optimalSwapRouter == address(0)) {
            initCode = bytes.concat(type(UniV3OptimalSwapRouter).creationCode, abi.encode(params.npm));
            initCodeHash = keccak256(initCode);
            console2.log("OptimalSwapRouter initCodeHash:");
            console2.logBytes32(initCodeHash);
            UniV3OptimalSwapRouter optimalSwapRouter = UniV3OptimalSwapRouter(
                payable(create2deployer.computeAddress(optimalSwapSalt, initCodeHash))
            );
            if (address(optimalSwapRouter).code.length == 0) {
                // Deploy optimalSwapRouter
                create2deployer.deploy(0, optimalSwapSalt, initCode);
                console2.log("UniV3OptimalSwapRouter deployed at: %s", address(optimalSwapRouter));
            }
            params.optimalSwapRouter = address(optimalSwapRouter);
        }

        // Encode constructor arguments
        bytes memory encodedArguments = abi.encode(params.npm, msgSender);
        // Concatenate init code with encoded arguments
        initCode = bytes.concat(type(UniV3Automan).creationCode, encodedArguments);
        initCodeHash = keccak256(initCode);
        console2.log("UniV3Automan initCodeHash:");
        console2.logBytes32(initCodeHash);
        // Compute the address of the contract to be deployed
        UniV3Automan automan = UniV3Automan(payable(create2deployer.computeAddress(automanSalt, initCodeHash)));

        if (address(automan).code.length == 0) {
            // Deploy automan
            create2deployer.deploy(0, automanSalt, initCode);

            // Set up automan
            automan.setFeeConfig(params.feeConfig);
            bool[] memory statuses = new bool[](1);
            statuses[0] = true;
            address[] memory controllers = new address[](1);
            controllers[0] = params.controller;
            automan.setControllers(controllers, statuses);
            address[] memory swapRouters = new address[](1);
            swapRouters[0] = params.optimalSwapRouter;
            automan.setSwapRouters(swapRouters, statuses);

            // Transfer ownership to the owner
            automan.transferOwnership(params.owner);

            console2.log(
                "UniV3Automan deployed at: %s with owner %s and controller %s",
                address(automan),
                automan.owner(),
                address(params.controller)
            );
        }

        // Deployment completed.
        vm.stopBroadcast();
    }
}
