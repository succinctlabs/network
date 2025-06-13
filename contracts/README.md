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

### Run the scripts

Deploy all contracts:

```sh
FOUNDRY_PROFILE=deploy forge script AllScript --private-key $PRIVATE_KEY --broadcast --rpc-url $ETH_RPC_URL
```

Then mint some $PROVE tokens (assuming you made the $OWNER the same as the $PRIVATE_KEY address):

```sh
FOUNDRY_PROFILE=deploy forge script MintScript --private-key $PRIVATE_KEY --broadcast --rpc-url $ETH_RPC_URL
```

Then create a prover and stake:

```sh
FOUNDRY_PROFILE=deploy forge script CreateProverAndStakeScript --private-key $PRIVATE_KEY --broadcast --rpc-url $ETH_RPC_URL
```

You can append `--verify --verifier etherscan --etherscan-api-key $ETHERSCAN_API_KEY` to the above commands to verify the contracts on Etherscan.

## Other Operations

To run cast commands, you need to set the environment variables to the addresses of the contracts you deployed, by looking at the [deployments](./deployments) directory.

```sh
CHAIN_ID=$(cast chain-id --rpc-url "$ETH_RPC_URL") && export $(jq -r 'to_entries|map("\(.key)=\(.value)")|.[]' ./deployments/${CHAIN_ID}.json) >/dev/null
```

### Deposit

```sh
cast send $PROVE "approve(address,uint256)" $VAPP 10000000e18 --private-key $PRIVATE_KEY --rpc-url $ETH_RPC_URL
```

```sh
cast send $VAPP "deposit(uint256)" 10000000e18 --private-key $PRIVATE_KEY --rpc-url $ETH_RPC_URL
```

### Withdraw

```sh
cast send $VAPP "requestWithdraw(address,uint256)" $(cast wallet address --private-key $PRIVATE_KEY) 100e18 --private-key $PRIVATE_KEY --rpc-url $ETH_RPC_URL
```

You need to wait for the withdrawal to be processed before you can finish it:

```sh
if [ $(cast call $VAPP "claimableWithdrawal(address)" $(cast wallet address --private-key $PRIVATE_KEY) --rpc-url $ETH_RPC_URL) -gt 0 ]; then
 cast send $VAPP "finishWithdraw()" --private-key $PRIVATE_KEY --rpc-url $ETH_RPC_URL
fi
```

### Create a Prover

```sh
cast send $STAKING "createProver()" $(cast wallet address --private-key $PRIVATE_KEY) --private-key $PRIVATE_KEY --rpc-url $ETH_RPC_URL
```

### Stake

```sh
cast send $PROVE "approve(address,uint256)" $STAKING 10000e18 --private-key $PRIVATE_KEY --rpc-url $ETH_RPC_URL
```

```sh
cast send $STAKING "stake(address,uint256)" $PROVER 9990e18 --private-key $PRIVATE_KEY --rpc-url $ETH_RPC_URL
```

### Unstake

```sh
cast send $STAKING "requestUnstake(uint256)" 2000e18 --private-key $PRIVATE_KEY --rpc-url $ETH_RPC_URL
```

```sh
cast send $STAKING "finishUnstake()" --private-key $PRIVATE_KEY --rpc-url $ETH_RPC_URL
```

### Dispense

Figure out the maximum amount of $PROVE that can be dispensed:

```sh
export DISPENSE_AMOUNT=$(cast call $STAKING "maxDispense()" --rpc-url $ETH_RPC_URL)
```

Send some $PROVE to the $STAKING contract (assumes your balance is enough):

```sh
cast send $PROVE "transfer(address,uint256)" $STAKING $DISPENSE_AMOUNT --private-key $PRIVATE_KEY --rpc-url $ETH_RPC_URL
```

Dispense it:

```sh
cast send $STAKING "dispense(uint256)" $DISPENSE_AMOUNT --private-key $PRIVATE_KEY --rpc-url $ETH_RPC_URL
```

OR just simply dispense the maximum amount:

```sh
cast send $STAKING "dispense(uint256)" $(cast max-uint) --private-key $PRIVATE_KEY --rpc-url $ETH_RPC_URL
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
