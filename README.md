# Aperture Core Contracts

[![Prettier](https://github.com/Aperture-Finance/core-contracts/actions/workflows/prettier.yml/badge.svg)](https://github.com/Aperture-Finance/core-contracts/actions/workflows/prettier.yml)
[![Test](https://github.com/Aperture-Finance/core-contracts/actions/workflows/test.yml/badge.svg)](https://github.com/Aperture-Finance/core-contracts/actions/workflows/test.yml)

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
GOERLI_RPC_URL="" # if using ethereum goerli.
MAINNET_RPC_URL="" # if using ethereum mainnet.
ARBITRUM_RPC_URL="" # if using arbitrum mainnet.
OPTIMISM_RPC_URL="" # if using optimism mainnet.
```

## Testing

First, the unit tests interact with Optimism mainnet where relevant contracts are deployed; you need to provide an rpc
node (preferably Alchemy's) in a `.env` file placed in the root directory of this repository.

Template:

```
OPTIMISM_RPC_URL="https://opt-mainnet.g.alchemy.com/v2/${ALCHEMY_API_KEY}"
```

Second, install Yarn and run `yarn` to install dependencies.

Third, install [Foundry](https://github.com/foundry-rs/foundry). Install git submodules

```shell
forge install
```

By default `via_ir` is enabled in [`foundry.toml`](foundry.toml). It takes one to two minutes to compile the project via
the IR pipeline. For faster compilation and testing, the lite profile can be enabled by setting the environment
variable `FOUNDRY_PROFILE` to `lite` which shortens the compilation time to about 10 seconds.

```shell
FOUNDRY_PROFILE="lite"
forge test
```

The tests may take anywhere between seconds to minutes to complete depending on whether contract storage slots in scope
are cached.

## Scripting

To simulate scripts, we can pass in `--fork-url <network>` to `forge script`. The `network` can be an
`rpc_endpoints` defined in [`foundry.toml`](foundry.toml) or an url to a node.

```shell
forge script DeployAutoman --fork-url goerli -vvvv
```

To run broadcast transactions on-chain, use:

```shell
forge script DeployAutoman --rpc-url goerli --broadcast -vvvv
```

## Verification

Generate the standard JSON input and verify the contract on Etherscan with it:

```shell
forge verify-contract 0x00000000Ede6d8D217c60f93191C060747324bca UniV3Automan --optimizer-runs 4194304 --constructor-args 0x000000000000000000000000c36442b4a4522e871399cd717abdd847ab11fe88000000000000000000000000beef63ae5a2102506e8a352a5bb32aa8b30b3112 --show-standard-json-input > etherscan.json
```

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
