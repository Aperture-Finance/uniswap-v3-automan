# Aperture UniV3 Automan

[![License: BUSL-1.1](https://img.shields.io/badge/License-BUSL--1.1-yellow.svg)](https://opensource.org/licenses/BUSL-1.1)
[![Prettier](https://github.com/Aperture-Finance/uniswap-v3-automan/actions/workflows/prettier.yml/badge.svg)](https://github.com/Aperture-Finance/uniswap-v3-automan/actions/workflows/prettier.yml)
[![Test](https://github.com/Aperture-Finance/uniswap-v3-automan/actions/workflows/test.yml/badge.svg)](https://github.com/Aperture-Finance/uniswap-v3-automan/actions/workflows/test.yml)

This repository contains the UniV3Automan contract, serving Aperture's Uniswap V3 liquidity position automation product.

The automation product allows UniV3 liquidity position holders to schedule the following actions when certain conditions
are met:

- Close an existing position.
- Rebalance a position to another price range.
- Reinvest a position, i.e., collect accrued fees and add to the position's liquidity.

Example of a supported condition: when ETH price remains above $2000 for at least 72 hours, according to Coingecko price
feed.

Aperture's automation service keeps track of scheduled tasks, periodically check whether user-specified conditions are
met, and trigger actions on-chain when conditions become satisfied.

The [`UniV3Automan`](./src/UniV3Automan.sol) contract exposes external functions that allow Aperture's automation
service to trigger the three supported actions. Note that 'rebalance' may involve the need to perform a swap such that
the ratio of the two tokens meets the requirement of the new position's price range; similarly, 'reinvest' involves a
swap among the collected fees such that the two tokens' ratio matches what's in the liquidity position in order to add
liquidity. The [`OptimalSwap`](./src/libraries/OptimalSwap.sol) library makes use of a closed form solution that finds
the optimal amount of token to swap in order to achieve a specified outcome of the two token's ratio, taking into
account the effect of the swap on the token amounts in the liquidity position.

## Environment Setup

Include an `.env` file at the root directory and consider adding the following environment variables:

```shell
PRIVATE_KEY="" # used as the contract deployer.
MAINNET_RPC_URL="" # used to test UniV3 and PCSV3
BASE_RPC_URL="" # used to test Aerodrome SlipStream
```

## Testing

First, the unit tests interact with Ethereum and Base mainnet where relevant contracts are deployed; you need to provide rpc
nodes (preferably Alchemy's) in a `.env` file placed in the root directory of this repository.

Template:

```
MAINNET_RPC_URL="https://eth-mainnet.g.alchemy.com/v2/${ALCHEMY_API_KEY}"
BASE_RPC_URL="https://base-mainnet.g.alchemy.com/v2/${ALCHEMY_API_KEY}"
```

Second, install Yarn and run `yarn` to install dependencies.

Third, install [Foundry](https://github.com/foundry-rs/foundry). Install git submodules

```shell
forge install
```

When `via_ir` is enabled in [`foundry.toml`](foundry.toml), it takes one to two minutes to compile the project via
the IR pipeline. For faster compilation and testing, the lite profile can be enabled by setting the environment
variable `FOUNDRY_PROFILE` to `lite` which shortens the compilation time to about 10 seconds.

```shell
FOUNDRY_PROFILE=lite forge test
```

The tests may take anywhere between seconds to minutes to complete depending on whether contract storage slots in scope
are cached.

In case of mysterious failures such as "failed to set up invariant testing environment", it may be caused by a Foundry issue. Try again with the following commands:

```shell
forge clean
forge build
forge test
```

## Scripting

To simulate scripts, we can pass in `--fork-url <network>` to `forge script`. The `network` can be an
`rpc_endpoints` defined in [`foundry.toml`](foundry.toml) or an url to a node.

```shell
forge script DeployUniV3Automan --fork-url [NETWORK_NAME] -vvvv
```

To run broadcast transactions on-chain, use:

```shell
forge script DeployUniV3Automan --rpc-url [NETWORK_NAME] --broadcast -vvvv
```

## Deployment

We use https://github.com/pcaversaccio/create2deployer to deploy contracts. If the network we want to deploy to doesn't currently have a `create2deployer` deployment then we need to first contact the owner to deploy that.

First, dry-run the deployment script on a local fork to get the `initCodeHash` of `UniV3Automan` contract:

```shell
forge script DeployUniV3Automan --fork-url [NETWORK_NAME] -vvvv
```

The output of the above command should contain text like "Automan initCodeHash: 0xbafd4e1d1ff7f7979102d9e80884c2a93d0e1160dae77b5f88e9bca95eb5e4d0".

Second, use the initCodeHash obtained above to mine a vanity address using the following commands:

```shell
git clone https://github.com/0age/create2crunch
cd create2crunch
export FACTORY="0x13b0D85CcB8bf860b6b79AF3029fCA081AE9beF2"
export CALLER="[DEPLOYER_ADDRESS_GOES_HERE]"
export INIT_CODE_HASH="[INIT_CODE_HASH_GOES_HERE]"
cargo run --release $FACTORY $CALLER $INIT_CODE_HASH
```

You should see rows like
```
0xbeef63ae5a2102506e8a352a5bb32aa8b30b3112f9d02aa0154b2000061fb0dd => 0x00006C2eEC8d3AC8720D65e400fe0079C32eee5A => 2
0xbeef63ae5a2102506e8a352a5bb32aa8b30b3112f9d02aa0154b6000064122f4 => 0x0000000054D52974711c14aB458780886579167F => 256
```
being generated. The bytes starting with "0xbeef" are salts, and the corresponding contract addresses are shown to their right. When a desired address has been mined, stop the create2crunch script and update `script/DeployUniV3Automan.s.sol` with the mined salt.

Re-simulate `DeployUniV3Automan` with a dry-run to verify that the deployment address matches expectation, and broadcast the transaction on-chain.


## Verification

Generate the standard JSON input and verify the contract on Etherscan with it:

```shell
forge verify-contract 0x0000003858948F29A38C6c3Ca09a1cD53a58DC34 UniV3Automan --optimizer-runs 4194304 --constructor-args 0x000000000000000000000000c36442b4a4522e871399cd717abdd847ab11fe88000000000000000000000000beef63ae5a2102506e8a352a5bb32aa8b30b3112 --show-standard-json-input > UniV3Automan.json
forge verify-contract 0x00000004D523574c93021f52E520ec4fb2FFA564 UniV3OptimalSwapRouter --optimizer-runs 4194304 --constructor-args 0x000000000000000000000000c36442b4a4522e871399cd717abdd847ab11fe88 --show-standard-json-input > UniV3OptimalSwapRouter.json
```

Constructor args can be encoded easily using an online ABI tool like https://abi.hashex.org. The above example shows `UniV3Automan` constructor args consisting of the nonfungible position manager contract address followed by the deployer address as the temporary Automan owner during deployment.

When verifying contracts on etherscan, omit '0x' from Constructor Arguments ABI-encoded.

**Deployed Contracts**

* [Mainnet](https://etherscan.io/address/0x00000000ede6d8d217c60f93191c060747324bca)
* [Arbitrum](https://arbiscan.io/address/0x00000000ede6d8d217c60f93191c060747324bca)

## Common Usage

### Updating dependencies

See example [here](https://book.getfoundry.sh/projects/dependencies?highlight=update#updating-dependencies).

```shell
forge update lib/<deps package> # e.g. forge update lib/forge-std
```

## Audits

Narya.ai has performed a security audit of the `UniV3Automan` contract on May 8, 2023, at
commit [2a8975e9](https://github.com/Aperture-Finance/core-contracts/commit/2a8975e91e1371fa23b268b30c8959f95027dafb).
The audit report can be
found [here](https://github.com/NaryaAI/publications/blob/1468e568712d5e2aa9b0ecde0a16d3f9f1d715ef/Aperture%20UniV3Automan%20Report.pdf).

## Licensing

The primary license for Aperture UniV3 Automan contract is the Business Source License 1.1 (`BUSL-1.1`),
see [`LICENSE`](./LICENSE). However, some files are dual-licensed under `GPL-2.0-or-later` or `MIT`:

- Several files in `src/base/` may also be licensed under `GPL-2.0-or-later` (as indicated in their SPDX headers).
- All files in `src/interfaces/` may also be licensed under `MIT` (as indicated in their SPDX headers).
- Several files in `src/libraries/` may also be licensed under `MIT` (as indicated in their SPDX headers).

## Other Exceptions

- All files in `test/` are licensed under `MIT`.
