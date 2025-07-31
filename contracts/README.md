# Succinct Prover Network Contracts

This folder contains the smart contracts for the Succinct Prover Network.

## Design

For design and architecture information, see [DESIGN.md](./DESIGN.md).

## Installation

To install the dependencies:

```sh
forge install
```

## Tests

To run the tests:

```sh
forge test
```

To run with additional fuzz runs:

```sh
FOUNDRY_PROFILE=fuzz forge test
```

## Gas Report

To generate a gas report (exclude fuzz tests for reproducibility):

```sh
FOUNDRY_PROFILE=deploy forge snapshot --no-match-test "Fuzz"
```

## Deployment

### Setup

First make a copy of the [.env.example](./.env.example):

```sh
cp .env.example .env
```

And then fill in your `.env` file with all the variables needed for configuring the contracts.

Also, set these terminal parameters needed to deploy to a specific chain:

```sh
export PRIVATE_KEY=
export ETH_RPC_URL=
export ETHERSCAN_API_KEY=
```

Then add a `{CHAIN_ID}.json` file in the [deployments](./deployments) directory for the chain you are deploying to. This command will automatically create it with an empty JSON `{}` if it doesn't exist:

```sh
CHAIN_ID=$(cast chain-id --rpc-url $ETH_RPC_URL); mkdir -p ./deployments && [ -f "./deployments/${CHAIN_ID}.json" ] || echo '{}' > "./deployments/${CHAIN_ID}.json"
```

Note: the production version of these contracts were deployed using foundry [v1.3.0](https://github.com/foundry-rs/foundry/releases/tag/v1.3.0).

### Bulk deployment

This should generally only be used for testing.

Deploy all contracts at once:

```sh
FOUNDRY_PROFILE=deploy forge script AllScript --private-key $PRIVATE_KEY --broadcast --rpc-url $ETH_RPC_URL
```

You can append `--verify --verifier etherscan --etherscan-api-key $ETHERSCAN_API_KEY` to the above commands to verify the contracts on Etherscan.

### Individual deployment

Instead of deploying all contracts at once, it's recommended to deploy each contract individually for production deployments.

#### Pre-deployed contracts

Fill out `{CHAIN_ID}.json` with any pre-deployed contracts. For example:

```json
{
  "PROVE": "0x6BEF15D938d4E72056AC92Ea4bDD0D76B1C4ad29",
  "VERIFIER": "0x397A5f7f3dBd538f23DE225B51f532c34448dA9B"
}
```

#### Deploy each contract

Deploy the SuccinctStaking contract:

```sh
FOUNDRY_PROFILE=deploy forge script SuccinctStakingScript --private-key $PRIVATE_KEY --broadcast --rpc-url $ETH_RPC_URL --verify --verifier etherscan --etherscan-api-key $ETHERSCAN_API_KEY
```

Note DOES NOT initalize the contract - this will be done in a later step once references to other contracts are available.

Deploy the $iPROVE contract (assumes $PROVE is already deployed):

```sh
FOUNDRY_PROFILE=deploy forge script IntermediateSuccinctScript --private-key $PRIVATE_KEY --broadcast --rpc-url $ETH_RPC_URL --verify --verifier etherscan --etherscan-api-key $ETHERSCAN_API_KEY
```

Deploy the SuccinctGovernor contract:

```sh
FOUNDRY_PROFILE=deploy forge script SuccinctGovernorScript --private-key $PRIVATE_KEY --broadcast --rpc-url $ETH_RPC_URL --verify --verifier etherscan --etherscan-api-key $ETHERSCAN_API_KEY
```

Deploy the SuccinctVApp contract (assumes verifier is already deployed):

```sh
FOUNDRY_PROFILE=deploy forge script SuccinctVAppScript --private-key $PRIVATE_KEY --broadcast --rpc-url $ETH_RPC_URL --verify --verifier etherscan --etherscan-api-key $ETHERSCAN_API_KEY
```
If the SP1VerifierGateway is not already deployed, follow steps in [sp1-contracts](https://github.com/succinctlabs/sp1-contracts) to deploy it and fill out the address in your `{CHAIN_ID}.json` file.

Initalize the SuccinctStaking contract:

```sh
FOUNDRY_PROFILE=deploy forge script SuccinctVAppScript --sig "initialize()" --private-key $PRIVATE_KEY --broadcast --rpc-url $ETH_RPC_URL
```

Run the integrity check:

```sh
TODO this should do `setUp` checks and make sure no vApp upgrades occured.
```

If that passes without reverting, the contracts have been successfully deployed and initalized. The addresses are in the `{CHAIN_ID}.json` file.

## Verification

If any of the contracts failed to verify on Etherscan, you can manually verify them by copying the the flatten source code and uploading it to Etherscan.

To do this, go to the address on Etherscan and click "Verify Contract". Choose:

* Compiler: "Solidity (Single File)"
* Compiler Version: "0.8.28"
* License: "MIT"

Then flatten the contract you're verifying, for example the SuccinctStaking contract:

```sh
forge flatten src/SuccinctStaking.sol
```

Copy the output into the "Contract Code" field.

Then enter the compiler settings from the [foundry.toml](./foundry.toml) file's `[profile.deploy]` section.

If any constructor arguements were used, use `cast abi-encode` with the appropriate signature to encode them, for example:

```sh
cast abi-encode "constructor(address)" 0xbD74E9B0Dcb0317E26505CA93757c29d564B533B
```

strip the `0x` prefix from this output and paste it into the "Constructor Arguments" field.