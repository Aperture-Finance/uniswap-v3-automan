import "@nomicfoundation/hardhat-toolbox";
import "@nomiclabs/hardhat-solhint";
import "hardhat-abi-exporter";
import "hardhat-docgen";
import "hardhat-tracer";
import { HardhatUserConfig } from "hardhat/config";
import { NetworksUserConfig, SolidityUserConfig } from "hardhat/types/config";
import { AbiExporterUserConfig } from "hardhat-abi-exporter";

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.18",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  } as SolidityUserConfig,
  networks: {
    mainnet: mainnetNetworkConfig(),
    goerli: goerliNetworkConfig(),
    bscMainnet: bscMainnetNetworkConfig(),
    bscTestnet: bscTestnetNetworkConfig(),
  } as NetworksUserConfig,
  abiExporter: {
    path: "./abi",
    clear: true,
    flat: false,
    spacing: 2,
    pretty: true,
    runOnCompile: true,
  } as AbiExporterUserConfig,
  docgen: {
    path: "./docs",
    clear: true,
    runOnCompile: true,
  },
  gasReporter: {
    currency: "USD",
  },
  etherscan: {
    apiKey: getEtherscanApiKey(),
  },
};

export default config;

function mainnetNetworkConfig() {
  let url = "https://mainnet.infura.io/v3/";
  let accountPrivateKey =
    "0x0000000000000000000000000000000000000000000000000000000000000000";
  if (process.env.MAINNET_ENDPOINT) {
    url = `${process.env.MAINNET_ENDPOINT}`;
  }

  if (process.env.MAINNET_PRIVATE_KEY) {
    accountPrivateKey = `${process.env.MAINNET_PRIVATE_KEY}`;
  }

  return {
    url: url,
    accounts: [accountPrivateKey],
  };
}

function goerliNetworkConfig() {
  let url = "https://goerli.infura.io/v3/";
  let accountPrivateKey =
    "0x0000000000000000000000000000000000000000000000000000000000000000";
  if (process.env.GOERLI_ENDPOINT) {
    url = `${process.env.GOERLI_ENDPOINT}`;
  }

  if (process.env.GOERLI_PRIVATE_KEY) {
    accountPrivateKey = `${process.env.GOERLI_PRIVATE_KEY}`;
  }

  return {
    url: url,
    accounts: [accountPrivateKey],
  };
}

function bscMainnetNetworkConfig() {
  let url = "https://data-seed-prebsc-1-s1.binance.org:8545/";
  let accountPrivateKey =
    "0x0000000000000000000000000000000000000000000000000000000000000000";
  if (process.env.BSC_MAINNET_ENDPOINT) {
    url = `${process.env.BSC_MAINNET_ENDPOINT}`;
  }

  if (process.env.BSC_MAINNET_PRIVATE_KEY) {
    accountPrivateKey = `${process.env.BSC_MAINNET_PRIVATE_KEY}`;
  }

  return {
    url: url,
    accounts: [accountPrivateKey],
  };
}

function bscTestnetNetworkConfig() {
  let url = "https://data-seed-prebsc-1-s1.binance.org:8545/";
  let accountPrivateKey =
    "0x0000000000000000000000000000000000000000000000000000000000000000";
  if (process.env.BSC_TESTNET_ENDPOINT) {
    url = `${process.env.BSC_TESTNET_ENDPOINT}`;
  }

  if (process.env.BSC_TESTNET_PRIVATE_KEY) {
    accountPrivateKey = `${process.env.BSC_TESTNET_PRIVATE_KEY}`;
  }

  return {
    url: url,
    accounts: [accountPrivateKey],
  };
}

function getEtherscanApiKey() {
  let apiKey = "";
  if (process.env.ETHERSCAN_API_KEY) {
    apiKey = `${process.env.ETHERSCAN_API_KEY}`;
  }
  return apiKey;
}
