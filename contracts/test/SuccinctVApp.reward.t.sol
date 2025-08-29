// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SuccinctVAppTest} from "./SuccinctVApp.t.sol";
import {SuccinctVApp} from "../src/SuccinctVApp.sol";
import {ISuccinctVApp} from "../src/interfaces/ISuccinctVApp.sol";
import {Merkle} from "../lib/murky/src/Merkle.sol";
import {MockERC20} from "./utils/MockERC20.sol";
import {MockStaking} from "../src/mocks/MockStaking.sol";
import {PausableUpgradeable} from
    "../lib/openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";

contract SuccinctVAppRewardsTest is SuccinctVAppTest {
    // Test data.
    address[] public rewardAccounts;
    uint256[] public rewardAmounts;
    bytes32[] public rewardLeaves;
    bytes32 public rewardsMerkleRoot;
    Merkle public merkle;

    // Prover for testing prover rewards.
    address public testProver;

    // Storage slot for rewardsRoot in SuccinctVApp (slot 11 based on contract layout).
    uint256 constant REWARDS_ROOT_SLOT = 11;

    function setUp() public override {
        super.setUp();

        // Create a test prover.
        vm.prank(ALICE);
        testProver = MockStaking(STAKING).createProver(ALICE, STAKER_FEE_BIPS);

        // Set up test rewards data (including a prover).
        rewardAccounts = [
            makeAddr("REWARD_1"),
            makeAddr("REWARD_2"),
            makeAddr("REWARD_3"),
            makeAddr("REWARD_4"),
            testProver // Include the prover in rewards
        ];
        rewardAmounts = [1e18, 2e18, 3e18, 4e18, 5e18];

        // Build the merkle tree.
        for (uint256 i = 0; i < rewardAccounts.length; i++) {
            rewardLeaves.push(keccak256(abi.encodePacked(i, rewardAccounts[i], rewardAmounts[i])));
        }
        merkle = new Merkle();
        rewardsMerkleRoot = merkle.getRoot(rewardLeaves);

        // Fund the VApp with $PROVE for rewards.
        MockERC20(PROVE).mint(VAPP, 100e18);
    }

    function _setRewardsRoot(bytes32 _root) internal {
        // Use vm.store to directly set the rewardsRoot in storage.
        vm.store(VAPP, bytes32(REWARDS_ROOT_SLOT), _root);
    }

    // Initial state should have no root and all indexes should be unclaimed.
    function test_Rewards_WhenInitialState() public view {
        // Rewards root should be empty initially.
        assertEq(SuccinctVApp(VAPP).rewardsRoot(), bytes32(0));

        // All indexes should be unclaimed.
        for (uint256 i = 0; i < rewardAccounts.length; i++) {
            assertEq(SuccinctVApp(VAPP).isClaimed(i), false);
        }
    }

    // // A valid proof should be able to claim a reward.
    // function test_RewardClaim_WhenValid() public {
    //     // Set the rewards root.
    //     _setRewardsRoot(rewardsMerkleRoot);

    //     // Verify the root was set correctly.
    //     assertEq(
    //         SuccinctVApp(VAPP).rewardsRoot(), rewardsMerkleRoot, "Rewards root not set correctly"
    //     );

    //     uint256 vappBalBefore = MockERC20(PROVE).balanceOf(VAPP);

    //     for (uint256 i = 0; i < rewardAccounts.length; i++) {
    //         // Setup.
    //         address claimer = rewardAccounts[i];
    //         uint256 amount = rewardAmounts[i];
    //         bytes32[] memory proof = merkle.getProof(rewardLeaves, i);
    //         uint256 preClaimerBalance = MockERC20(PROVE).balanceOf(claimer);
    //         bool preIsClaimedState = SuccinctVApp(VAPP).isClaimed(i);

    //         // Check pre-claim state.
    //         assertEq(preClaimerBalance, 0);
    //         assertEq(preIsClaimedState, false);

    //         // Claim.
    //         vm.expectEmit(true, true, true, true, VAPP);
    //         emit ISuccinctVApp.RewardClaimed(i, claimer, amount);
    //         SuccinctVApp(VAPP).rewardClaim(i, claimer, amount, proof);

    //         // Check post-claim state.
    //         if (claimer == testProver) {
    //             // For provers, PROVE is converted to iPROVE and sent to prover vault.
    //             assertEq(MockERC20(I_PROVE).balanceOf(claimer), amount);
    //             assertEq(MockERC20(PROVE).balanceOf(claimer), 0);
    //         } else {
    //             // For regular accounts, PROVE is sent directly.
    //             assertEq(MockERC20(PROVE).balanceOf(claimer), amount);
    //         }
    //         vappBalBefore -= amount;
    //         assertEq(MockERC20(PROVE).balanceOf(VAPP), vappBalBefore);
    //         assertEq(SuccinctVApp(VAPP).isClaimed(i), true);
    //     }
    // }

    // // Not allowed to re-claim a reward.
    // function test_RevertRewardClaim_WhenAlreadyClaimed() public {
    //     // Set the rewards root.
    //     _setRewardsRoot(rewardsMerkleRoot);

    //     // Claim all rewards.
    //     for (uint256 i = 0; i < rewardAccounts.length; i++) {
    //         bytes32[] memory proof = merkle.getProof(rewardLeaves, i);
    //         SuccinctVApp(VAPP).rewardClaim(i, rewardAccounts[i], rewardAmounts[i], proof);
    //     }

    //     // Attempt to claim again.
    //     for (uint256 i = 0; i < rewardAccounts.length; i++) {
    //         bytes32[] memory proof = merkle.getProof(rewardLeaves, i);
    //         vm.expectRevert(ISuccinctVApp.RewardAlreadyClaimed.selector);
    //         SuccinctVApp(VAPP).rewardClaim(i, rewardAccounts[i], rewardAmounts[i], proof);
    //     }
    // }

    // // Not allowed to claim with an invalid proof.
    // function test_RevertRewardClaim_WhenInvalidProof() public {
    //     // Set the rewards root.
    //     _setRewardsRoot(rewardsMerkleRoot);

    //     // Setup.
    //     uint256 index = 0;
    //     uint256 invalidIndex = 1;
    //     address claimer = rewardAccounts[index];
    //     uint256 amount = rewardAmounts[index];
    //     bytes32[] memory invalidProof = merkle.getProof(rewardLeaves, invalidIndex);

    //     // Attempt to claim with an invalid proof.
    //     vm.expectRevert(ISuccinctVApp.InvalidProof.selector);
    //     SuccinctVApp(VAPP).rewardClaim(index, claimer, amount, invalidProof);
    // }

    // // Not allowed to claim when paused.
    // function test_RevertRewardClaim_WhenPaused() public {
    //     // Pause the contract.
    //     vm.prank(OWNER);
    //     SuccinctVApp(VAPP).pause();

    //     // Setup test data.
    //     uint256 index = 0;
    //     address claimer = rewardAccounts[index];
    //     uint256 amount = rewardAmounts[index];
    //     bytes32[] memory proof = merkle.getProof(rewardLeaves, index);

    //     // Attempt to claim when paused.
    //     vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
    //     SuccinctVApp(VAPP).rewardClaim(index, claimer, amount, proof);
    // }

    // // isClaimed should correctly track claimed rewards.
    // function test_IsClaimed_BitMapLogic() public {
    //     // Set the rewards root.
    //     _setRewardsRoot(rewardsMerkleRoot);

    //     // Test the bitmap logic for various indexes.
    //     assertEq(SuccinctVApp(VAPP).isClaimed(0), false);
    //     assertEq(SuccinctVApp(VAPP).isClaimed(255), false);
    //     assertEq(SuccinctVApp(VAPP).isClaimed(256), false);
    //     assertEq(SuccinctVApp(VAPP).isClaimed(512), false);

    //     // Claim index 0.
    //     bytes32[] memory proof = merkle.getProof(rewardLeaves, 0);
    //     SuccinctVApp(VAPP).rewardClaim(0, rewardAccounts[0], rewardAmounts[0], proof);
    //     assertEq(SuccinctVApp(VAPP).isClaimed(0), true);
    //     assertEq(SuccinctVApp(VAPP).isClaimed(1), false);
    // }

    // // Anyone is allowed to claim a reward for an account as long it's valid.
    // function test_RewardClaim_WhenDifferentCaller() public {
    //     // Set the rewards root.
    //     _setRewardsRoot(rewardsMerkleRoot);

    //     // Anyone should be able to call rewardClaim for any account.
    //     address randomCaller = makeAddr("RANDOM_CALLER");

    //     // Claim as a different caller.
    //     bytes32[] memory proof = merkle.getProof(rewardLeaves, 0);
    //     vm.prank(randomCaller);
    //     SuccinctVApp(VAPP).rewardClaim(0, rewardAccounts[0], rewardAmounts[0], proof);

    //     // Verify the reward went to the correct account.
    //     assertEq(MockERC20(PROVE).balanceOf(rewardAccounts[0]), rewardAmounts[0]);
    //     assertEq(MockERC20(PROVE).balanceOf(randomCaller), 0);
    // }

    // // Not allowed to claim with a wrong amount.
    // function test_RevertRewardClaim_WhenWrongAmount() public {
    //     // Set the rewards root.
    //     _setRewardsRoot(rewardsMerkleRoot);

    //     // Try to claim with wrong amount.
    //     bytes32[] memory proof = merkle.getProof(rewardLeaves, 0);
    //     uint256 wrongAmount = rewardAmounts[0] + 1;

    //     vm.expectRevert(ISuccinctVApp.InvalidProof.selector);
    //     SuccinctVApp(VAPP).rewardClaim(0, rewardAccounts[0], wrongAmount, proof);
    // }

    // // Not allowed to claim with a wrong account.
    // function test_RevertRewardClaim_WhenWrongAccount() public {
    //     // Set the rewards root.
    //     _setRewardsRoot(rewardsMerkleRoot);

    //     // Try to claim with wrong account.
    //     bytes32[] memory proof = merkle.getProof(rewardLeaves, 0);
    //     address wrongAccount = makeAddr("WRONG_ACCOUNT");

    //     vm.expectRevert(ISuccinctVApp.InvalidProof.selector);
    //     SuccinctVApp(VAPP).rewardClaim(0, wrongAccount, rewardAmounts[0], proof);
    // }

    // // Not allowed to claim with an empty proof.
    // function test_RevertRewardClaim_WhenEmptyProof() public {
    //     // Set the rewards root.
    //     _setRewardsRoot(rewardsMerkleRoot);

    //     // Try to claim with empty proof.
    //     bytes32[] memory emptyProof = new bytes32[](0);

    //     vm.expectRevert(ISuccinctVApp.InvalidProof.selector);
    //     SuccinctVApp(VAPP).rewardClaim(0, rewardAccounts[0], rewardAmounts[0], emptyProof);
    // }

    // // It's valid if only a subset of accounts claim within an epoch.
    // function test_RewardClaim_WhenPartial() public {
    //     // Set the rewards root.
    //     _setRewardsRoot(rewardsMerkleRoot);

    //     // Claim only some rewards (not all).
    //     uint256 totalClaimed = 0;
    //     for (uint256 i = 0; i < 3; i++) {
    //         bytes32[] memory proof = merkle.getProof(rewardLeaves, i);
    //         SuccinctVApp(VAPP).rewardClaim(i, rewardAccounts[i], rewardAmounts[i], proof);
    //         totalClaimed += rewardAmounts[i];
    //     }

    //     // Check claimed status.
    //     assertEq(SuccinctVApp(VAPP).isClaimed(0), true);
    //     assertEq(SuccinctVApp(VAPP).isClaimed(1), true);
    //     assertEq(SuccinctVApp(VAPP).isClaimed(2), true);
    //     assertEq(SuccinctVApp(VAPP).isClaimed(3), false);
    //     assertEq(SuccinctVApp(VAPP).isClaimed(4), false);

    //     // Verify correct balances.
    //     uint256 expectedRemainingBalance = 100 ether - totalClaimed;
    //     assertEq(MockERC20(PROVE).balanceOf(VAPP), expectedRemainingBalance);
    // }

    // // Rewards should be transferred to the prover vault correctly: PROVE is sent to iPROVE,
    // // and the iPROVE is sent to the prover.
    // function test_RewardClaim_WhenToProverVault() public {
    //     // Set the rewards root.
    //     _setRewardsRoot(rewardsMerkleRoot);

    //     // Get the prover index (last one in our array).
    //     uint256 proverIndex = rewardAccounts.length - 1;
    //     address proverVault = rewardAccounts[proverIndex];
    //     uint256 amount = rewardAmounts[proverIndex];

    //     // Verify it's recognized as a prover.
    //     assertEq(proverVault, testProver);

    //     // Check initial balances.
    //     uint256 initialVAppBalance = MockERC20(PROVE).balanceOf(VAPP);
    //     uint256 initialProverPROVEBalance = MockERC20(PROVE).balanceOf(proverVault);
    //     uint256 initialProveriPROVEBalance = MockERC20(I_PROVE).balanceOf(proverVault);
    //     assertEq(initialProverPROVEBalance, 0);
    //     assertEq(initialProveriPROVEBalance, 0);

    //     // Claim reward for prover.
    //     bytes32[] memory proof = merkle.getProof(rewardLeaves, proverIndex);
    //     vm.expectEmit(true, true, true, true, VAPP);
    //     emit ISuccinctVApp.RewardClaimed(proverIndex, proverVault, amount);
    //     SuccinctVApp(VAPP).rewardClaim(proverIndex, proverVault, amount, proof);

    //     // Verify the prover received iPROVE instead of PROVE.
    //     assertEq(MockERC20(PROVE).balanceOf(proverVault), 0);
    //     assertEq(MockERC20(I_PROVE).balanceOf(proverVault), amount);
    //     assertEq(MockERC20(PROVE).balanceOf(VAPP), initialVAppBalance - amount);
    //     assertEq(SuccinctVApp(VAPP).isClaimed(proverIndex), true);
    // }

    // // Rewards should be transferred to mixed prover vaults and EOAs correctly.
    // function test_RewardClaim_WhenMixedAccountTypes() public {
    //     // Set the rewards root.
    //     _setRewardsRoot(rewardsMerkleRoot);

    //     // Claim for regular account (index 0).
    //     bytes32[] memory proof0 = merkle.getProof(rewardLeaves, 0);
    //     SuccinctVApp(VAPP).rewardClaim(0, rewardAccounts[0], rewardAmounts[0], proof0);

    //     // Verify regular account received PROVE.
    //     assertEq(MockERC20(PROVE).balanceOf(rewardAccounts[0]), rewardAmounts[0]);
    //     assertEq(MockERC20(I_PROVE).balanceOf(rewardAccounts[0]), 0);

    //     // Claim for prover (last index).
    //     uint256 proverIndex = rewardAccounts.length - 1;
    //     bytes32[] memory proofProver = merkle.getProof(rewardLeaves, proverIndex);
    //     SuccinctVApp(VAPP).rewardClaim(
    //         proverIndex, testProver, rewardAmounts[proverIndex], proofProver
    //     );

    //     // Verify prover received iPROVE.
    //     assertEq(MockERC20(PROVE).balanceOf(testProver), 0);
    //     assertEq(MockERC20(I_PROVE).balanceOf(testProver), rewardAmounts[proverIndex]);
    // }
}
