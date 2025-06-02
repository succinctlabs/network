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

## Gas Report

To generate a gas report:

```sh
FOUNDRY_PROFILE=deploy forge snapshot
```

## Deployment

To deploy the contracts, first make a copy of the [.env.example](./.env.example):

```sh
cp .env.example .env
```

And then configure your `.env` file with all the variables.

Then, add a `{CHAIN_ID}.json` file in the [deployments](./deployments) directory for the chain you are deploying to (if it doesn't already exist). Create it with an empty JSON `{}`.

All contracts:

```sh
FOUNDRY_PROFILE=deploy forge script AllScript --private-key $PRIVATE_KEY --broadcast --rpc-url $ETH_RPC_URL --verify --verifier etherscan
```

## Operations

### Deposit

```sh
cast send $PROVE "mint(address,uint256)" $(cast wallet address --private-key $PRIVATE_KEY) 10000e18 --private-key $PRIVATE_KEY --rpc-url $ETH_RPC_URL
```

```sh
cast send $PROVE "approve(address,uint256)" $VAPP 50e18 --private-key $PRIVATE_KEY --rpc-url $ETH_RPC_URL
```

```sh
cast send $VAPP "deposit(uint256)" 50e18 --private-key $PRIVATE_KEY --rpc-url $ETH_RPC_URL
```

### Create a Prover

```sh
cast send $STAKING "createProver()" $(cast wallet address --private-key $PRIVATE_KEY) --private-key $PRIVATE_KEY --rpc-url $ETH_RPC_URL
```

Note: Check which address was created by looking at the internal transaction. Set $PROVER to that address.

### Stake

```sh
cast send $PROVE "mint(address,uint256)" $(cast wallet address --private-key $PRIVATE_KEY) 10000e18 --private-key $PRIVATE_KEY --rpc-url $ETH_RPC_URL
```

```sh
cast send $PROVE "approve(address,uint256)" $STAKING 10e18 --private-key $PRIVATE_KEY --rpc-url $ETH_RPC_URL
```

```sh
cast send $STAKING "stake(address,uint256)" $PROVER 10e18 --private-key $PRIVATE_KEY --rpc-url $ETH_RPC_URL
```

### Reward

Send some $PROVE to the $VAPP contract (simulates the fee for requesting a proof):

```sh
cast send $PROVE "mint(address,uint256)" $VAPP 1000e18 --private-key $PRIVATE_KEY --rpc-url $ETH_RPC_URL
```

Then send the reward to the prover (simulates the proof being fulfilled):

```sh
cast send $VAPP "processFulfillment(address,uint256)" $PROVER 100e18 --private-key $PRIVATE_KEY --rpc-url $ETH_RPC_URL
```

### Slash

Request a slashing for the prover:

```sh
cast send $VAPP "processSlash(address,uint256)" $PROVER 10e5 --private-key $PRIVATE_KEY --rpc-url $ETH_RPC_URL
```

### Dispense

Send some $PROVE to the $STAKING contract:

```sh
cast send $PROVE "transfer(address,uint256)" $STAKING 10e18 --private-key $PRIVATE_KEY --rpc-url $ETH_RPC_URL
```

Dispense some $PROVE:

```sh
cast send $STAKING "dispense(uint256)" 10e18 --private-key $PRIVATE_KEY --rpc-url $ETH_RPC_URL
```

### Unstake

```sh
cast send $STAKING "requestUnstake(uint256)" 2000e18 --private-key $PRIVATE_KEY --rpc-url $ETH_RPC_URL
```

```sh
cast send $STAKING "finishUnstake()" --private-key $PRIVATE_KEY --rpc-url $ETH_RPC_URL
```

### Check stake balances

Staker:

```sh
cast to-dec $(cast call $STAKING "staked(address)" $(cast wallet address --private-key $PRIVATE_KEY) --rpc-url $ETH_RPC_URL)
```

Prover:

```sh
cast to-dec $(cast call $STAKING "proverStaked(address)" $PROVER --rpc-url $ETH_RPC_URL)
```
