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
        uint256 protocolFeeBips = SuccinctVApp(VAPP).protocolFeeBips();
        
        // Calculate rewards with protocol fee logic
        uint256 protocolFee = (rewardAmount * protocolFeeBips) / 10000;
        uint256 remainingAfterProtocol = rewardAmount - protocolFee;
        uint256 stakerReward = (remainingAfterProtocol * stakerFeeBips) / 10000;
        uint256 ownerReward = remainingAfterProtocol - stakerReward;

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

        // Expect PROVE tokens to be transferred from VAPP to STAKING (staker reward)
        vm.expectEmit(true, true, false, true);
        emit IERC20.Transfer(VAPP, STAKING, stakerReward);

        // Expect PROVE tokens to be transferred from VAPP to ALICE (owner reward)
        vm.expectEmit(true, true, false, true);
        emit IERC20.Transfer(VAPP, ALICE, ownerReward);

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
        // VApp transfers out: ownerReward + stakerReward, keeps protocolFee
        assertEq(
            MockERC20(PROVE).balanceOf(VAPP), vappInitialBalance - ownerReward - stakerReward
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
        // VApp should split rewards: remainder to prover owner (ALICE), staker portion to staking contract

        // Assert ALICE (prover owner) received the owner reward portion
        assertEq(
            MockERC20(PROVE).balanceOf(ALICE),
            initialAliceBalance + ownerReward,
            "Prover owner (ALICE) should receive the owner reward portion"
        );

        // Assert prover contract balance remains unchanged (staker rewards go to staking contract)
        assertEq(
            MockERC20(PROVE).balanceOf(prover),
            initialProverBalance,
            "Prover contract balance should remain unchanged"
        );

        // Verify the math
        assertEq(
            ownerReward,
            (remainingAfterProtocol * (10000 - stakerFeeBips)) / 10000,
            "Owner reward should be calculated correctly"
        );
        assertEq(
            stakerReward,
            (remainingAfterProtocol * stakerFeeBips) / 10000,
            "Staker reward should be calculated correctly"
        );
        assertEq(ownerReward + stakerReward, remainingAfterProtocol, "Rewards should sum to remaining after protocol fee");

        // After reward distribution:
        // - protocolFee stays in VApp
        // - ownerReward goes to ALICE (prover owner)
        // - stakerReward goes to MockStaking (for distribution to stakers)
        // So VApp should have vappInitialBalance - ownerReward - stakerReward remaining
        assertEq(
            MockERC20(PROVE).balanceOf(address(VAPP)),
            vappInitialBalance - ownerReward - stakerReward
        );
    }
}
