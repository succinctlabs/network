# Design

This document describes the onchain Succinct Prover Network in detail.

## Contracts

The protocol consists of the following core contracts:

* [Succinct](./src/tokens/Succinct.sol) "Succinct (PROVE)" - The ERC20 primary liquid token.
* [IntermediateSuccinct](./src/tokens/IntermediateSuccinct.sol) "IntermediateSuccinct (iPROVE)" - The ERC4626 token with $PROVE as the underlying.
* [SuccinctProver](./src/tokens/SuccinctProver.sol) "Prover-N (PROVER-N)" - The ERC4626Rewards token with $iPROVE as the underlying. Each prover has their own deployment of this contract, and `N` is replaced with an incrementing number representing the prover's ID.
* [SuccinctStaking](./src/SuccinctStaking.sol) "StakedSuccinct (stPROVE)" - The ERC20 terminal receipt token, containing the logic for staking, unstaking, rewards, slashing, and dispensing. For the purposes of this document, $stPROVE treated as distinct from the staking contract logic.
* [SuccinctGovernor](./src/SuccinctGovernor.sol) - The governor for on-chain governance, using $stPROVE as the votes token.
* [VApp](./src/mocks/MockVApp.sol) - Handles settlement and is responsible for triggering rewards and slashing.

## Operations

The protocol contracts have several core operations that can occur:

* [Stake](./#stake)
* [Unstake](./#unstake)
* [Reward](./#reward)
* [Claim Rewards](./#claim-rewards)
* [Slash](./#slash)
* [Dispense](./#dispense)

In the diagrams below, protocol tokens/vaults are shown in red, protocol logic contracts are shown in green, reward tokens are shown in blue, and off-chain systems are shown in yellow.

### Stake

![Stake](./media/stake.png)

Triggered by a staker calling either [SuccinctStaking.stake()](./src/SuccinctStaking.sol#L169) or [SuccinctStaking.permitAndStake()](./src/SuccinctStaking.sol#L179), specifying the prover to stake to and the amount of $PROVE to stake.

This takes $PROVE from the staker and deposits it into the $iPROVE vault (minting $iPROVE), and then takes that $iPROVE and deposits it into the chosen $PROVER-N vault (minting $PROVER-N) as well as mints $stPROVE.

A staker can only stake to one prover at a time, and must fully unstake if they need to change provers.

After this operation, the staker receives a corresponding amount of $stPROVE and $PROVER-N.

### Unstake

![Unstake](./media/unstake.png)

Triggered by a staker calling [SuccinctStaking.requestUnstake()](./src/SuccinctStaking.sol#L192), waiting for [SuccinctStaking.unstakePeriod()](./src/SuccinctStaking.sol#L94) seconds to pass, and then calling [SuccinctStaking.finishUnstake()](./src/SuccinctStaking.sol#L237).

This takes $stPROVE from the staker and burns it, and then redeems the $iPROVE from the $PROVER-N vault (burning $PROVER-N), and then redeems the $PROVE from the $iPROVE vault (burning $iPROVE).

If fully unstaking, this will also automatically [claim](./#claim-rewards) any rewards accrued.

After this finishing this operation, the staker receives a corresponding amount of $PROVE.

### Reward

![Reward](./media/reward.png)

Triggered by the Auctioneer/VApp, and intended to be called when a prover fulfills a proof.

This transfers a portion of the $PROVE the requester paid into the prover's vault.

After this operation, the prover's stakers will have an increased [SuccinctStaking.staked()](./src/SuccinctStaking.sol#L127) amount.

### Slash

![Slash](./media/slash.png)

First triggered by the Auctioneer/VApp calling [SuccinctStaking.requestSlash()](./src/SuccinctStaking.sol#L291). Then, the [SuccinctStaking.owner()](./src/SuccinctStaking.sol#L54) can process the requested slash either by cancelling it via [SuccinctStaking.cancelSlash()](./src/SuccinctStaking.sol#L315) or, if [SuccinctStaking.slashPeriod()](./src/SuccinctStaking.sol#L99) seconds have passed, it can be finished via [SuccinctStaking.finishSlash()](./src/SuccinctStaking.sol#L334).

If the latter, burns the $PROVER-N vault's corresponding $iPROVE and corresponding $PROVE.

After finishing this operation, the prover's stakers will have a decreased amount of staked $PROVE.

### Dispense

![Dispense](./media/dispense.png)

Triggered by the [SuccinctStaking.owner()](./src/SuccinctStaking.sol#L54) calling [SuccinctStaking.dispense()](./src/SuccinctStaking.sol#L363), specifying the amount of $PROVE to dispense.

This moves $PROVE from the staking contract to the $iPROVE vault.

The maximum amount of dispense is defined as [SuccinctStaking.maxDispense()](./src/SuccinctStaking.sol#L176), which is bounded by the [dispenseRate](./src/SuccinctStaking.sol#L66). Dispense rate can also be changed by the owner via [SuccinctStaking.setDispenseRate()](./src/SuccinctStaking.sol#L383).

It is assumed that the staking contract has ownership of this much $PROVE. Operationally, $PROVE will need to be topped up to cover the dispense rate.

After this operation, all stakers will have an increased amount of withdrawable $PROVE, because the $iPROVE they they (indirectly) own has it's value increased relative to $PROVE.