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

    // Test deadline (1 hour from now)
    uint256 public testDeadline;

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

        // Set test deadline to 1 hour from now.
        testDeadline = block.timestamp + 1 hours;
    }

    // Initial state should have no root and deadline should be 0.
    function test_Rewards_WhenInitialState() public view {
        // Rewards root should be empty initially.
        assertEq(SuccinctVApp(VAPP).rewardRoot(), bytes32(0));
        assertEq(SuccinctVApp(VAPP).rewardDeadline(), 0);
        assertEq(SuccinctVApp(VAPP).rewardClaimedCount(), 0);

        // Check that isClaimed returns false for any index with zero root.
        for (uint256 i = 0; i < rewardAccounts.length; i++) {
            assertEq(SuccinctVApp(VAPP).isClaimed(bytes32(0), i), false);
        }
    }

    // A valid proof should be able to claim a reward.
    function test_RewardClaim_WhenValid() public {
        // Set the rewards root as auctioneer.
        vm.prank(AUCTIONEER);
        vm.expectEmit(true, true, true, true, VAPP);
        emit ISuccinctVApp.RewardRootSet(rewardsMerkleRoot, testDeadline);
        SuccinctVApp(VAPP).setRewardRoot(rewardsMerkleRoot, testDeadline);

        // Verify the root and deadline were set correctly.
        assertEq(
            SuccinctVApp(VAPP).rewardRoot(), rewardsMerkleRoot, "Rewards root not set correctly"
        );
        assertEq(
            SuccinctVApp(VAPP).rewardDeadline(), testDeadline, "Rewards deadline not set correctly"
        );

        uint256 vappBalBefore = MockERC20(PROVE).balanceOf(VAPP);
        uint256 claimedCountBefore = SuccinctVApp(VAPP).rewardClaimedCount();

        for (uint256 i = 0; i < rewardAccounts.length; i++) {
            // Setup.
            address claimer = rewardAccounts[i];
            uint256 amount = rewardAmounts[i];
            bytes32[] memory proof = merkle.getProof(rewardLeaves, i);
            uint256 preClaimerBalance = MockERC20(PROVE).balanceOf(claimer);
            bool preIsClaimedState = SuccinctVApp(VAPP).isClaimed(rewardsMerkleRoot, i);

            // Check pre-claim state.
            assertEq(preClaimerBalance, 0);
            assertEq(preIsClaimedState, false);

            // Claim.
            vm.expectEmit(true, true, true, true, VAPP);
            emit ISuccinctVApp.RewardClaimed(rewardsMerkleRoot, i, claimer, amount);
            SuccinctVApp(VAPP).rewardClaim(i, claimer, amount, proof);

            // Check post-claim state.
            if (claimer == testProver) {
                // For provers, PROVE is converted to iPROVE and sent to prover vault.
                assertEq(MockERC20(I_PROVE).balanceOf(claimer), amount);
                assertEq(MockERC20(PROVE).balanceOf(claimer), 0);
            } else {
                // For regular accounts, PROVE is sent directly.
                assertEq(MockERC20(PROVE).balanceOf(claimer), amount);
            }
            vappBalBefore -= amount;
            assertEq(MockERC20(PROVE).balanceOf(VAPP), vappBalBefore);
            assertEq(SuccinctVApp(VAPP).isClaimed(rewardsMerkleRoot, i), true);

            // Check claimed count incremented.
            assertEq(SuccinctVApp(VAPP).rewardClaimedCount(), claimedCountBefore + i + 1);
        }

        // Final check that all rewards were counted.
        assertEq(SuccinctVApp(VAPP).rewardClaimedCount(), rewardAccounts.length);
    }

    // Not allowed to re-claim a reward.
    function test_RevertRewardClaim_WhenAlreadyClaimed() public {
        // Set the rewards root as auctioneer.
        vm.prank(AUCTIONEER);
        SuccinctVApp(VAPP).setRewardRoot(rewardsMerkleRoot, testDeadline);

        // Claim all rewards.
        for (uint256 i = 0; i < rewardAccounts.length; i++) {
            bytes32[] memory proof = merkle.getProof(rewardLeaves, i);
            SuccinctVApp(VAPP).rewardClaim(i, rewardAccounts[i], rewardAmounts[i], proof);
        }

        // Get claimed count after all claims.
        uint256 claimedCountAfterAll = SuccinctVApp(VAPP).rewardClaimedCount();
        assertEq(claimedCountAfterAll, rewardAccounts.length);

        // Attempt to claim again.
        for (uint256 i = 0; i < rewardAccounts.length; i++) {
            bytes32[] memory proof = merkle.getProof(rewardLeaves, i);
            vm.expectRevert(ISuccinctVApp.RewardAlreadyClaimed.selector);
            SuccinctVApp(VAPP).rewardClaim(i, rewardAccounts[i], rewardAmounts[i], proof);
        }

        // Verify count didn't change after failed attempts.
        assertEq(SuccinctVApp(VAPP).rewardClaimedCount(), claimedCountAfterAll);
    }

    // Not allowed to claim with an invalid proof.
    function test_RevertRewardClaim_WhenInvalidProof() public {
        // Set the rewards root as auctioneer.
        vm.prank(AUCTIONEER);
        SuccinctVApp(VAPP).setRewardRoot(rewardsMerkleRoot, testDeadline);

        // Setup.
        uint256 index = 0;
        uint256 invalidIndex = 1;
        address claimer = rewardAccounts[index];
        uint256 amount = rewardAmounts[index];
        bytes32[] memory invalidProof = merkle.getProof(rewardLeaves, invalidIndex);

        // Get claimed count before attempt.
        uint256 claimedCountBefore = SuccinctVApp(VAPP).rewardClaimedCount();

        // Attempt to claim with an invalid proof.
        vm.expectRevert(ISuccinctVApp.InvalidProof.selector);
        SuccinctVApp(VAPP).rewardClaim(index, claimer, amount, invalidProof);

        // Verify count didn't change.
        assertEq(SuccinctVApp(VAPP).rewardClaimedCount(), claimedCountBefore);
    }

    // Not allowed to claim when paused.
    function test_RevertRewardClaim_WhenPaused() public {
        // Set the rewards root as auctioneer.
        vm.prank(AUCTIONEER);
        SuccinctVApp(VAPP).setRewardRoot(rewardsMerkleRoot, testDeadline);

        // Pause the contract.
        vm.prank(OWNER);
        SuccinctVApp(VAPP).pause();

        // Setup test data.
        uint256 index = 0;
        address claimer = rewardAccounts[index];
        uint256 amount = rewardAmounts[index];
        bytes32[] memory proof = merkle.getProof(rewardLeaves, index);

        // Attempt to claim when paused.
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        SuccinctVApp(VAPP).rewardClaim(index, claimer, amount, proof);
    }

    // isClaimed should correctly track claimed rewards.
    function test_IsClaimed_BitMapLogic() public {
        // Set the rewards root as auctioneer.
        vm.prank(AUCTIONEER);
        SuccinctVApp(VAPP).setRewardRoot(rewardsMerkleRoot, testDeadline);

        // Test the bitmap logic for various indexes.
        assertEq(SuccinctVApp(VAPP).isClaimed(rewardsMerkleRoot, 0), false);
        assertEq(SuccinctVApp(VAPP).isClaimed(rewardsMerkleRoot, 255), false);
        assertEq(SuccinctVApp(VAPP).isClaimed(rewardsMerkleRoot, 256), false);
        assertEq(SuccinctVApp(VAPP).isClaimed(rewardsMerkleRoot, 512), false);

        // Claim index 0.
        bytes32[] memory proof = merkle.getProof(rewardLeaves, 0);
        SuccinctVApp(VAPP).rewardClaim(0, rewardAccounts[0], rewardAmounts[0], proof);
        assertEq(SuccinctVApp(VAPP).isClaimed(rewardsMerkleRoot, 0), true);
        assertEq(SuccinctVApp(VAPP).isClaimed(rewardsMerkleRoot, 1), false);
    }

    // Anyone is allowed to claim a reward for an account as long it's valid.
    function test_RewardClaim_WhenDifferentCaller() public {
        // Set the rewards root as auctioneer.
        vm.prank(AUCTIONEER);
        SuccinctVApp(VAPP).setRewardRoot(rewardsMerkleRoot, testDeadline);

        // Anyone should be able to call rewardClaim for any account.
        address randomCaller = makeAddr("RANDOM_CALLER");

        // Claim as a different caller.
        bytes32[] memory proof = merkle.getProof(rewardLeaves, 0);
        vm.prank(randomCaller);
        SuccinctVApp(VAPP).rewardClaim(0, rewardAccounts[0], rewardAmounts[0], proof);

        // Verify the reward went to the correct account.
        assertEq(MockERC20(PROVE).balanceOf(rewardAccounts[0]), rewardAmounts[0]);
        assertEq(MockERC20(PROVE).balanceOf(randomCaller), 0);
    }

    // Not allowed to claim with a wrong amount.
    function test_RevertRewardClaim_WhenWrongAmount() public {
        // Set the rewards root as auctioneer.
        vm.prank(AUCTIONEER);
        SuccinctVApp(VAPP).setRewardRoot(rewardsMerkleRoot, testDeadline);

        // Try to claim with wrong amount.
        bytes32[] memory proof = merkle.getProof(rewardLeaves, 0);
        uint256 wrongAmount = rewardAmounts[0] + 1;

        vm.expectRevert(ISuccinctVApp.InvalidProof.selector);
        SuccinctVApp(VAPP).rewardClaim(0, rewardAccounts[0], wrongAmount, proof);
    }

    // Not allowed to claim with a wrong account.
    function test_RevertRewardClaim_WhenWrongAccount() public {
        // Set the rewards root as auctioneer.
        vm.prank(AUCTIONEER);
        SuccinctVApp(VAPP).setRewardRoot(rewardsMerkleRoot, testDeadline);

        // Try to claim with wrong account.
        bytes32[] memory proof = merkle.getProof(rewardLeaves, 0);
        address wrongAccount = makeAddr("WRONG_ACCOUNT");

        vm.expectRevert(ISuccinctVApp.InvalidProof.selector);
        SuccinctVApp(VAPP).rewardClaim(0, wrongAccount, rewardAmounts[0], proof);
    }

    // Not allowed to claim with an empty proof.
    function test_RevertRewardClaim_WhenEmptyProof() public {
        // Set the rewards root as auctioneer.
        vm.prank(AUCTIONEER);
        SuccinctVApp(VAPP).setRewardRoot(rewardsMerkleRoot, testDeadline);

        // Try to claim with empty proof.
        bytes32[] memory emptyProof = new bytes32[](0);

        vm.expectRevert(ISuccinctVApp.InvalidProof.selector);
        SuccinctVApp(VAPP).rewardClaim(0, rewardAccounts[0], rewardAmounts[0], emptyProof);
    }

    // It's valid if only a subset of accounts claim within an epoch.
    function test_RewardClaim_WhenPartial() public {
        // Set the rewards root as auctioneer.
        vm.prank(AUCTIONEER);
        SuccinctVApp(VAPP).setRewardRoot(rewardsMerkleRoot, testDeadline);

        // Claim only some rewards (not all).
        uint256 totalClaimed = 0;
        for (uint256 i = 0; i < 3; i++) {
            bytes32[] memory proof = merkle.getProof(rewardLeaves, i);
            SuccinctVApp(VAPP).rewardClaim(i, rewardAccounts[i], rewardAmounts[i], proof);
            totalClaimed += rewardAmounts[i];
        }

        // Check claimed status.
        assertEq(SuccinctVApp(VAPP).isClaimed(rewardsMerkleRoot, 0), true);
        assertEq(SuccinctVApp(VAPP).isClaimed(rewardsMerkleRoot, 1), true);
        assertEq(SuccinctVApp(VAPP).isClaimed(rewardsMerkleRoot, 2), true);
        assertEq(SuccinctVApp(VAPP).isClaimed(rewardsMerkleRoot, 3), false);
        assertEq(SuccinctVApp(VAPP).isClaimed(rewardsMerkleRoot, 4), false);

        // Verify correct balances.
        uint256 expectedRemainingBalance = 100 ether - totalClaimed;
        assertEq(MockERC20(PROVE).balanceOf(VAPP), expectedRemainingBalance);
    }

    // Rewards should be transferred to the prover vault correctly: PROVE is sent to iPROVE,
    // and the iPROVE is sent to the prover.
    function test_RewardClaim_WhenToProverVault() public {
        // Set the rewards root as auctioneer.
        vm.prank(AUCTIONEER);
        SuccinctVApp(VAPP).setRewardRoot(rewardsMerkleRoot, testDeadline);

        // Get the prover index (last one in our array).
        uint256 proverIndex = rewardAccounts.length - 1;
        address proverVault = rewardAccounts[proverIndex];
        uint256 amount = rewardAmounts[proverIndex];

        // Verify it's recognized as a prover.
        assertEq(proverVault, testProver);

        // Check initial balances.
        uint256 initialVAppBalance = MockERC20(PROVE).balanceOf(VAPP);
        uint256 initialProverPROVEBalance = MockERC20(PROVE).balanceOf(proverVault);
        uint256 initialProveriPROVEBalance = MockERC20(I_PROVE).balanceOf(proverVault);
        assertEq(initialProverPROVEBalance, 0);
        assertEq(initialProveriPROVEBalance, 0);

        // Claim reward for prover.
        bytes32[] memory proof = merkle.getProof(rewardLeaves, proverIndex);
        vm.expectEmit(true, true, true, true, VAPP);
        emit ISuccinctVApp.RewardClaimed(rewardsMerkleRoot, proverIndex, proverVault, amount);
        SuccinctVApp(VAPP).rewardClaim(proverIndex, proverVault, amount, proof);

        // Verify the prover received iPROVE instead of PROVE.
        assertEq(MockERC20(PROVE).balanceOf(proverVault), 0);
        assertEq(MockERC20(I_PROVE).balanceOf(proverVault), amount);
        assertEq(MockERC20(PROVE).balanceOf(VAPP), initialVAppBalance - amount);
        assertEq(SuccinctVApp(VAPP).isClaimed(rewardsMerkleRoot, proverIndex), true);
    }

    // Rewards should be transferred to mixed prover vaults and EOAs correctly.
    function test_RewardClaim_WhenMixedAccountTypes() public {
        // Set the rewards root as auctioneer.
        vm.prank(AUCTIONEER);
        SuccinctVApp(VAPP).setRewardRoot(rewardsMerkleRoot, testDeadline);

        // Claim for regular account (index 0).
        bytes32[] memory proof0 = merkle.getProof(rewardLeaves, 0);
        SuccinctVApp(VAPP).rewardClaim(0, rewardAccounts[0], rewardAmounts[0], proof0);

        // Verify regular account received PROVE.
        assertEq(MockERC20(PROVE).balanceOf(rewardAccounts[0]), rewardAmounts[0]);
        assertEq(MockERC20(I_PROVE).balanceOf(rewardAccounts[0]), 0);

        // Claim for prover (last index).
        uint256 proverIndex = rewardAccounts.length - 1;
        bytes32[] memory proofProver = merkle.getProof(rewardLeaves, proverIndex);
        SuccinctVApp(VAPP).rewardClaim(
            proverIndex, testProver, rewardAmounts[proverIndex], proofProver
        );

        // Verify prover received iPROVE.
        assertEq(MockERC20(PROVE).balanceOf(testProver), 0);
        assertEq(MockERC20(I_PROVE).balanceOf(testProver), rewardAmounts[proverIndex]);
    }

    /*//////////////////////////////////////////////////////////////
                           NEW DEADLINE TESTS
    //////////////////////////////////////////////////////////////*/

    // Not allowed to claim after deadline.
    function test_RevertRewardClaim_WhenAfterDeadline() public {
        // Set the rewards root as auctioneer with a deadline in the past.
        uint256 pastDeadline = block.timestamp - 1;
        vm.prank(AUCTIONEER);
        SuccinctVApp(VAPP).setRewardRoot(rewardsMerkleRoot, pastDeadline);

        // Move time forward past the deadline.
        vm.warp(block.timestamp + 1);

        // Try to claim.
        bytes32[] memory proof = merkle.getProof(rewardLeaves, 0);
        vm.expectRevert(ISuccinctVApp.RewardRootExpired.selector);
        SuccinctVApp(VAPP).rewardClaim(0, rewardAccounts[0], rewardAmounts[0], proof);
    }

    // Auctioneer can't set new root before previous deadline.
    function test_RevertSetRewardRoot_WhenBeforeDeadline() public {
        // Set the rewards root as auctioneer.
        vm.prank(AUCTIONEER);
        SuccinctVApp(VAPP).setRewardRoot(rewardsMerkleRoot, testDeadline);

        // Try to set a new root before deadline.
        bytes32 newRoot = keccak256("NEW_ROOT");
        uint256 newDeadline = block.timestamp + 2 hours;

        vm.prank(AUCTIONEER);
        vm.expectRevert(ISuccinctVApp.RewardRootNotExpired.selector);
        SuccinctVApp(VAPP).setRewardRoot(newRoot, newDeadline);
    }

    // Auctioneer can set new root after deadline.
    function test_SetRewardRoot_WhenAfterDeadline() public {
        // Set the rewards root as auctioneer.
        vm.prank(AUCTIONEER);
        SuccinctVApp(VAPP).setRewardRoot(rewardsMerkleRoot, testDeadline);

        // Move time past deadline.
        vm.warp(testDeadline + 1);

        // Set new root.
        bytes32 newRoot = keccak256("NEW_ROOT");
        uint256 newDeadline = block.timestamp + 2 hours;

        vm.prank(AUCTIONEER);
        vm.expectEmit(true, true, true, true, VAPP);
        emit ISuccinctVApp.RewardRootSet(newRoot, newDeadline);
        SuccinctVApp(VAPP).setRewardRoot(newRoot, newDeadline);

        assertEq(SuccinctVApp(VAPP).rewardRoot(), newRoot);
        assertEq(SuccinctVApp(VAPP).rewardDeadline(), newDeadline);
    }

    // Only auctioneer can set reward root.
    function test_RevertSetRewardRoot_WhenNotAuctioneer() public {
        vm.expectRevert(ISuccinctVApp.NotAuctioneer.selector);
        SuccinctVApp(VAPP).setRewardRoot(rewardsMerkleRoot, testDeadline);

        vm.prank(OWNER);
        vm.expectRevert(ISuccinctVApp.NotAuctioneer.selector);
        SuccinctVApp(VAPP).setRewardRoot(rewardsMerkleRoot, testDeadline);
    }

    // Claims are tracked separately per root.
    function test_RewardClaim_MultipleRoots() public {
        // Set first root.
        vm.prank(AUCTIONEER);
        SuccinctVApp(VAPP).setRewardRoot(rewardsMerkleRoot, testDeadline);

        // Claim index 0 from first root.
        bytes32[] memory proof = merkle.getProof(rewardLeaves, 0);
        SuccinctVApp(VAPP).rewardClaim(0, rewardAccounts[0], rewardAmounts[0], proof);
        assertEq(SuccinctVApp(VAPP).isClaimed(rewardsMerkleRoot, 0), true);

        // Move time past deadline.
        vm.warp(testDeadline + 1);

        // Create new rewards data.
        address[] memory newAccounts = new address[](2);
        newAccounts[0] = makeAddr("NEW_REWARD_1");
        newAccounts[1] = makeAddr("NEW_REWARD_2");
        uint256[] memory newAmounts = new uint256[](2);
        newAmounts[0] = 10e18;
        newAmounts[1] = 20e18;

        bytes32[] memory newLeaves = new bytes32[](2);
        newLeaves[0] = keccak256(abi.encodePacked(uint256(0), newAccounts[0], newAmounts[0]));
        newLeaves[1] = keccak256(abi.encodePacked(uint256(1), newAccounts[1], newAmounts[1]));

        bytes32 newMerkleRoot = merkle.getRoot(newLeaves);
        uint256 newDeadline = block.timestamp + 2 hours;

        // Set new root.
        vm.prank(AUCTIONEER);
        SuccinctVApp(VAPP).setRewardRoot(newMerkleRoot, newDeadline);

        // Index 0 is not claimed in new root.
        assertEq(SuccinctVApp(VAPP).isClaimed(newMerkleRoot, 0), false);
        assertEq(SuccinctVApp(VAPP).isClaimed(rewardsMerkleRoot, 0), true);

        // Fund more for new claims.
        MockERC20(PROVE).mint(VAPP, 30e18);

        // Claim from new root.
        bytes32[] memory newProof = merkle.getProof(newLeaves, 0);
        SuccinctVApp(VAPP).rewardClaim(0, newAccounts[0], newAmounts[0], newProof);

        assertEq(SuccinctVApp(VAPP).isClaimed(newMerkleRoot, 0), true);
        assertEq(MockERC20(PROVE).balanceOf(newAccounts[0]), newAmounts[0]);
    }
}
