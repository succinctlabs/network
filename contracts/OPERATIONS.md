# Contract Operations

This document contains commands to interact with the deployed contracts.

To run these cast commands, you need to set the environment variables to the addresses of the contracts you deployed, by looking at the [deployments](./deployments) directory.

This can be automatically done with the following command:

```sh
CHAIN_ID=$(cast chain-id --rpc-url "$ETH_RPC_URL") && export $(jq -r 'to_entries|map("\(.key)=\(.value)")|.[]' ./deployments/${CHAIN_ID}.json) >/dev/null
```

## Staking

### Create a Prover

```sh
cast send $STAKING "createProver(uint256)" 1000 --private-key $PRIVATE_KEY --rpc-url $ETH_RPC_URL
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

## vApp

### Deposit

```sh
cast send $PROVE "approve(address,uint256)" $VAPP 10000000e18 --private-key $PRIVATE_KEY --rpc-url $ETH_RPC_URL
```

```sh
cast send $VAPP "deposit(uint256)" 10000000e18 --private-key $PRIVATE_KEY --rpc-url $ETH_RPC_URL
```

## View


### Check stake balances

Staker:

```sh
cast to-dec $(cast call $STAKING "staked(address)" $(cast wallet address --private-key $PRIVATE_KEY) --rpc-url $ETH_RPC_URL)
```

Prover:

```sh
cast to-dec $(cast call $STAKING "proverStaked(address)" $PROVER --rpc-url $ETH_RPC_URL)
```
