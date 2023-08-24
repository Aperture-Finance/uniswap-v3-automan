// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Script.sol";
import "../src/UniV3Automan.sol";
import "../src/RouterProxy.sol";

contract DeployAutoman is Script {
    struct DeployParams {
        address controller;
        UniV3Automan.FeeConfig feeConfig;
        INPM npm;
        address owner;
    }

    // https://github.com/pcaversaccio/create2deployer
    Create2Deployer internal constant create2deployer = Create2Deployer(0x13b0D85CcB8bf860b6b79AF3029fCA081AE9beF2);
    bytes32 internal constant salt = 0x5e05bd683b7817ee2a6b1d3cd7d8a34df4ee1696cf39a2a08878c523116daae7;

    // https://book.getfoundry.sh/tutorials/best-practices#scripts
    function readInput(string memory input) internal view returns (string memory) {
        string memory inputDir = string.concat(vm.projectRoot(), "/script/input/");
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
        bytes memory initCode = bytes.concat(type(UniV3Automan).creationCode, encodedArguments);
        bytes32 initCodeHash = keccak256(initCode);
        console2.log("Automan initCodeHash:");
        console2.logBytes32(initCodeHash);
        // Compute the address of the contract to be deployed
        UniV3Automan automan = UniV3Automan(payable(create2deployer.computeAddress(salt, initCodeHash)));

        if (address(automan).code.length != 0) {
            console2.log("Automan already deployed at: %s", address(automan));
            bytes32 routerSalt = 0x862e41240a461e611c6c023e3cf74c29b2ab80b8e2b2539de1b8b1f096922723;
            RouterProxy routerProxy = RouterProxy(
                create2deployer.computeAddress(routerSalt, keccak256(type(RouterProxy).creationCode))
            );
            // Deploy routerProxy
            create2deployer.deploy(0, routerSalt, type(RouterProxy).creationCode);
            console2.log("RouterProxy deployed at: %s", address(routerProxy));
            vm.stopBroadcast();
            return;
        }
        // Deploy automan
        create2deployer.deploy(0, salt, initCode);

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
            "UniV3Automan deployed at: %s with owner %s and controller %s",
            address(automan),
            automan.owner(),
            address(params.controller)
        );

        // Deployment completed.
        vm.stopBroadcast();
    }
}

interface Create2Deployer {
    /**
     * @dev Deploys a contract using `CREATE2`. The address where the
     * contract will be deployed can be known in advance via {computeAddress}.
     *
     * The bytecode for a contract can be obtained from Solidity with
     * `type(contractName).creationCode`.
     *
     * Requirements:
     * - `bytecode` must not be empty.
     * - `salt` must have not been used for `bytecode` already.
     * - the factory must have a balance of at least `value`.
     * - if `value` is non-zero, `bytecode` must have a `payable` constructor.
     */
    function deploy(uint256 value, bytes32 salt, bytes memory code) external;

    /**
     * @dev Returns the address where a contract will be stored if deployed via {deploy}.
     * Any change in the `bytecodeHash` or `salt` will result in a new destination address.
     */
    function computeAddress(bytes32 salt, bytes32 codeHash) external view returns (address);
}
