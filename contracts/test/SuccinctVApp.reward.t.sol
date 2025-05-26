// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SuccinctVAppTest} from "./SuccinctVApp.t.sol";
import {SuccinctVApp} from "../src/SuccinctVApp.sol";
import {ISuccinctVApp} from "../src/interfaces/ISuccinctVApp.sol";
import {Actions} from "../src/libraries/Actions.sol";
import {
    PublicValuesStruct,
    ReceiptStatus,
    Action,
    ActionType,
    DepositAction,
    WithdrawAction,
    AddSignerAction,
    RemoveSignerAction,
    SlashAction,
    RewardAction
} from "../src/libraries/PublicValues.sol";
import {ISuccinctVApp} from "../src/interfaces/ISuccinctVApp.sol";
import {MockERC20} from "./utils/MockERC20.sol";
import {ERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ISuccinctStaking} from "../src/interfaces/ISuccinctStaking.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {MockStaking} from "../src/mocks/MockStaking.sol";
import {SuccinctProver} from "../src/tokens/SuccinctProver.sol";
import {IProver} from "../src/interfaces/IProver.sol";

contract SuccinctVAppRewardTest is SuccinctVAppTest {
    function test_Reward_WhenValid() public {
        address prover = address(new SuccinctProver(PROVE, STAKING, ALICE, 1, 1000));

        // Give the VAPP some initial balance (simulates some existing deposits) so that it can reward
        uint256 vappInitialBalance = 1000e18; // 1000 PROVE tokens
        MockERC20(PROVE).mint(VAPP, vappInitialBalance);

        uint256 rewardAmount = 100e18 / 2; // Reward half of VApp's balance

        // Record initial balances
        uint256 initialProverBalance = IERC20(PROVE).balanceOf(prover);
        uint256 initialAliceBalance = IERC20(PROVE).balanceOf(ALICE);

        // Verify VApp has the tokens
        assertEq(MockERC20(PROVE).balanceOf(VAPP), vappInitialBalance);
        assertEq(MockERC20(PROVE).balanceOf(prover), 0);

        // Set VAPP address in MockStaking
        MockStaking(STAKING).setVApp(VAPP);

        // Set up approval from VAPP to STAKING for staker reward portion only
        // VApp will transfer owner reward directly, and staker reward to staking
        uint256 stakerFeeBips = IProver(prover).stakerFeeBips();
        uint256 stakerReward = (rewardAmount * stakerFeeBips) / 10000;
        uint256 ownerReward = rewardAmount - stakerReward;

        vm.prank(VAPP);
        MockERC20(PROVE).approve(STAKING, stakerReward);

        // Prepare PublicValues for updateState
        bytes memory rewardData = abi.encode(RewardAction({prover: prover, amount: rewardAmount}));

        PublicValuesStruct memory publicValues = PublicValuesStruct({
            actions: new Action[](1),
            oldRoot: SuccinctVApp(VAPP).root(), // Should be bytes32(0) initially
            newRoot: bytes32(uint256(0xbeef)), // Arbitrary new root
            timestamp: uint64(block.timestamp) // Current block timestamp
        });
        publicValues.actions[0] = Action({
            action: ActionType.Reward,
            status: ReceiptStatus.Completed,
            receipt: 1, // Rewards don't create pending receipts, this is an ID for the completed action
            data: rewardData
        });

        // Mock verifier call
        mockCall(true);

        // Expect VAPP to call STAKING.reward(prover, stakerReward) - only the staker portion
        vm.expectCall(
            STAKING,
            abi.encodeWithSelector(ISuccinctStaking.reward.selector, prover, stakerReward),
            1 // Expected number of calls
        );

        // Expect PROVE tokens to be transferred from VAPP to ALICE (owner reward)
        vm.expectEmit(true, true, false, true);
        emit IERC20.Transfer(VAPP, ALICE, ownerReward);

        // Expect PROVE tokens to be transferred from VAPP to STAKING (staker reward)
        vm.expectEmit(true, true, false, true);
        emit IERC20.Transfer(VAPP, STAKING, stakerReward);

        // Expect PROVE tokens to be transferred from VAPP to prover (via STAKING contract)
        vm.expectEmit(true, true, false, true);
        emit IERC20.Transfer(VAPP, prover, stakerReward);

        // Expect ReceiptCompleted event for the reward
        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.ReceiptCompleted(1, ActionType.Reward, rewardData);

        // Expect Block event
        uint64 expectedBlockNumber = SuccinctVApp(VAPP).blockNumber() + 1;
        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.Block(expectedBlockNumber, publicValues.newRoot, publicValues.oldRoot);

        // Perform the state update
        SuccinctVApp(VAPP).updateState(abi.encode(publicValues), jsonFixture.proof);

        // Assert final state
        // Note: MockStaking transfers the full staker reward amount to the prover,
        // so VApp loses: ownerReward + stakerReward + stakerReward = 90 + 10 + 10 = 110 PROVE
        assertEq(
            MockERC20(PROVE).balanceOf(VAPP), vappInitialBalance - ownerReward - (stakerReward * 2)
        );
        assertEq(SuccinctVApp(VAPP).finalizedReceipt(), 1);
        assertEq(SuccinctVApp(VAPP).blockNumber(), expectedBlockNumber);
        assertEq(SuccinctVApp(VAPP).root(), publicValues.newRoot);
        assertEq(SuccinctVApp(VAPP).timestamp(), publicValues.timestamp);

        // Verify prover properties
        assertEq(IProver(prover).owner(), ALICE, "Prover owner should be ALICE");
        assertEq(IProver(prover).staking(), STAKING, "Prover staking should be set correctly");
        assertEq(IProver(prover).stakerFeeBips(), 1000, "Prover staker fee should be 10%");

        // Verify the fee splitting worked correctly:
        // VApp should split rewards: 90% to prover owner (ALICE), 10% to stakers (via prover contract)

        // Assert ALICE (prover owner) received 90% of the reward
        assertEq(
            MockERC20(PROVE).balanceOf(ALICE),
            initialAliceBalance + ownerReward,
            "Prover owner (ALICE) should receive 90% of the reward"
        );

        // Assert prover contract received 10% of the reward (staker portion via MockStaking)
        assertEq(
            MockERC20(PROVE).balanceOf(prover),
            initialProverBalance + stakerReward,
            "Prover contract should receive 10% of the reward (staker portion)"
        );

        // Verify the math
        assertEq(
            ownerReward,
            (rewardAmount * (10000 - stakerFeeBips)) / 10000,
            "Owner reward should be calculated correctly"
        );
        assertEq(
            stakerReward,
            (rewardAmount * stakerFeeBips) / 10000,
            "Staker reward should be calculated correctly"
        );
        assertEq(ownerReward + stakerReward, rewardAmount, "Rewards should sum to total");

        // After reward distribution:
        // - ownerReward goes to ALICE (prover owner fee)
        // - stakerReward goes to MockStaking (staker fee)
        // - stakerReward goes to SuccinctProver (MockStaking transfers full amount to prover)
        // So VApp should have vappInitialBalance - ownerReward - stakerReward - stakerReward remaining
        assertEq(
            MockERC20(PROVE).balanceOf(address(VAPP)),
            vappInitialBalance - ownerReward - (stakerReward * 2)
        );
    }
}
