# Contract Design

This document describes the Succinct Prover Network contracts in detail.

## Contracts

The protocol consists of the following core contracts:

* [Succinct](./src/tokens/Succinct.sol) "Succinct ($PROVE)" - The primary ERC20 token.
* [IntermediateSuccinct](./src/tokens/IntermediateSuccinct.sol) "IntermediateSuccinct ($iPROVE)" - The ERC4626 token with $PROVE as the underlying. This is a shared vault for all stakers, which allows dispense to distribute $PROVE proportionally. This token is also used as the governance token. Non-transferable outside of staking operations.
* [SuccinctProver](./src/tokens/SuccinctProver.sol) "Prover-N ($PROVER-N)" - The ERC4626 token with $iPROVE as the underlying. Each prover has their own deployment of this contract, and `N` is replaced with an incrementing number representing the prover's ID. Since $iPROVE is the underlying and is the governance votes token, this allows prover owners to particpate in governance utilizing the `onlyOwner` functions on the vault. Non-transferable outside of staking operations.
* [SuccinctStaking](./src/SuccinctStaking.sol) "StakedSuccinct ($stPROVE)" - The staking receipt ERC20 token, containing the logic for prover creation, staking, unstaking, slashing, and dispensing. Non-fungible since the amount of $iPROVE and therefor $PROVE recieved is dependent on which particular prover it represents staking for. For the purposes of this document, $stPROVE treated as distinct from the staking contract logic, but they are actually combined into a single contract. Non-transferable outside of staking operations.
* [SuccinctVApp](./src/SuccinctVApp.sol) - Handles settlement of the verifiable application (VApp) onchain and offchain transactions. Onchain transactions include the creation of new provers and deposits. Offchain transactions include clears (when a proof has been fulfilled), transfers, withdrawals, and slashing.
* [SuccinctGovernor](./src/SuccinctGovernor.sol) - The governor for onchain governance, using $iPROVE as the votes token.

## Operations

The SuccinctStaking contract has these core operations that can occur:

* [Stake](./#stake)
* [Unstake](./#unstake)
* [Slash](./#slash)
* [Dispense](./#dispense)

The SuccinctVApp contract has these core operations that can occur:

* Deposit
* Withdraw
* CreateProver

The SuccinctGovernor contract has these core operations that can occur:

* Propose
* Vote
* Execute

In the diagrams below, tokens/vaults are shown in red, logic contracts are shown in green, and off-chain systems are shown in yellow.

### Stake

![Stake](./media/stake.png)

Triggered by a staker calling either [SuccinctStaking.stake()](./src/SuccinctStaking.sol#L244) or [SuccinctStaking.permitAndStake()](./src/SuccinctStaking.sol#L257), specifying the prover to stake to and the amount of $PROVE to stake.

This deposits $PROVE from the staker into the $iPROVE vault (minting $iPROVE), and then takes that $iPROVE and deposits it into the chosen $PROVER-N vault (minting $PROVER-N). The staking contract escrows this $PROVER-N, while minting $stPROVE to the staker (which acts as the receipt token for staking).

A staker can only stake to one prover at a time, and must fully unstake if they need to change provers.

After this operation, the staker receives a corresponding amount of $stPROVE.

### Unstake

![Unstake](./media/unstake.png)

Triggered by a staker calling [SuccinctStaking.requestUnstake()](./src/SuccinctStaking.sol#L280), waiting for [SuccinctStaking.unstakePeriod()](./src/SuccinctStaking.sol#L52) seconds to pass, and then calling [SuccinctStaking.finishUnstake()](./src/SuccinctStaking.sol#L326).

This burns the staker's $stPROVE, and then withdraws the $iPROVE from the $PROVER-N vault (burning $PROVER-N), and then withdraws the $PROVE from the $iPROVE vault (burning $iPROVE).

This will also automatically withdraw any rewards that the prover has accrued, and finish that withdrawal before the unstaking occurs.

After this finishing this operation, the staker receives a corresponding amount of $PROVE.

### Slash

![Slash](./media/slash.png)

First triggered by the Auctioneer/VApp calling [SuccinctStaking.requestSlash()](./src/SuccinctStaking.sol#L362). Then, the SuccinctStaking.owner() can process the requested slash either by cancelling it via [SuccinctStaking.cancelSlash()](./src/SuccinctStaking.sol#L387) or, if [SuccinctStaking.slashCancellationPeriod()](./src/SuccinctStaking.sol#L55) seconds have passed, it can be finished via [SuccinctStaking.finishSlash()](./src/SuccinctStaking.sol#L421).

If the latter, burns the selected prover vault's corresponding $iPROVE and $PROVE.

After finishing this operation, the prover's stakers will have a decreased amount of staked $PROVE.

### Dispense

![Dispense](./media/dispense.png)

Triggered by the SuccinctStaking.owner() calling [SuccinctStaking.dispense()](./src/SuccinctStaking.sol#L491), specifying the amount of $PROVE to dispense.

This moves $PROVE from the staking contract to the $iPROVE vault, effectively distributing the $PROVE to all stakers.

The maximum amount of dispense is defined as [SuccinctStaking.maxDispense()](./src/SuccinctStaking.sol#L229), which is bounded by the [SuccinctStaking.dispenseRate()](./src/SuccinctStaking.sol#L58). Dispense rate can also be changed by the owner via [SuccinctStaking.updateDispenseRate()](./src/SuccinctStaking.sol#L519).

It is assumed that the staking contract has ownership of this much $PROVE. Operationally, the staking contract will need to be periodically topped up with $PROVE to cover the dispense rate.

After this operation, all stakers will have an increased amount of withdrawable $PROVE.