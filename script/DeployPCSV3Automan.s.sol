// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Script.sol";
import "./ICreate2Deployer.sol";
import "../src/PCSV3OptimalSwapRouter.sol";
import "../src/PCSV3Automan.sol";

contract DeployPCSV3Automan is Script {
    struct DeployParams {
        address controller;
        PCSV3Automan.FeeConfig feeConfig;
        INPM npm;
        address owner;
    }

    // https://github.com/pcaversaccio/create2deployer
    Create2Deployer internal constant create2deployer = Create2Deployer(0x13b0D85CcB8bf860b6b79AF3029fCA081AE9beF2);
    bytes32 internal constant automanSalt = 0xbeef63ae5a2102506e8a352a5bb32aa8b30b3112aea04f28065924aabf21000c;
    bytes32 internal constant optimalSwapSalt = 0xbeef63ae5a2102506e8a352a5bb32aa8b30b31128393bd6e0c8355c768030028;

    // https://book.getfoundry.sh/tutorials/best-practices#scripts
    function readInput(string memory input) internal view returns (string memory) {
        string memory inputDir = string.concat(vm.projectRoot(), "/script/PCSV3Automan_input/");
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

        // Encode constructor arguments
        bytes memory encodedArguments = abi.encode(params.npm, msgSender);
        // Concatenate init code with encoded arguments
        bytes memory initCode = bytes.concat(type(PCSV3Automan).creationCode, encodedArguments);
        bytes32 initCodeHash = keccak256(initCode);
        console2.log("PCSV3Automan initCodeHash:");
        console2.logBytes32(initCodeHash);
        // Compute the address of the contract to be deployed
        PCSV3Automan automan = PCSV3Automan(payable(create2deployer.computeAddress(automanSalt, initCodeHash)));

        if (address(automan).code.length == 0) {
            // Deploy automan
            create2deployer.deploy(0, automanSalt, initCode);

            // Set up automan
            automan.setFeeConfig(params.feeConfig);
            address[] memory controllers = new address[](1);
            controllers[0] = params.controller;
            bool[] memory statuses = new bool[](1);
            statuses[0] = true;
            automan.setControllers(controllers, statuses);
            // Transfer ownership to the owner
            automan.transferOwnership(params.owner);

            console2.log(
                "PCSV3Automan deployed at: %s with owner %s and controller %s",
                address(automan),
                automan.owner(),
                address(params.controller)
            );
        }

        initCode = bytes.concat(type(PCSV3OptimalSwapRouter).creationCode, abi.encode(params.npm));
        initCodeHash = keccak256(initCode);
        console2.log("OptimalSwapRouter initCodeHash:");
        console2.logBytes32(initCodeHash);
        PCSV3OptimalSwapRouter optimalSwapRouter = PCSV3OptimalSwapRouter(
            payable(create2deployer.computeAddress(optimalSwapSalt, initCodeHash))
        );
        if (address(optimalSwapRouter).code.length == 0) {
            // Deploy optimalSwapRouter
            create2deployer.deploy(0, optimalSwapSalt, initCode);
            console2.log("PCSV3OptimalSwapRouter deployed at: %s", address(optimalSwapRouter));
        }

        // Deployment completed.
        vm.stopBroadcast();
    }
}
