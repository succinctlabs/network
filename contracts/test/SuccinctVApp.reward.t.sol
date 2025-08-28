// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SuccinctVAppTest} from "./SuccinctVApp.t.sol";
import {SuccinctVApp} from "../src/SuccinctVApp.sol";
import {ISuccinctVApp} from "../src/interfaces/ISuccinctVApp.sol";
import {Merkle} from "../lib/murky/src/Merkle.sol";
import {MockERC20} from "./utils/MockERC20.sol";
import {PausableUpgradeable} from
    "../lib/openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";

contract SuccinctVAppRewardsTest is SuccinctVAppTest {
    // Test data.
    address[] public rewardAccounts;
    uint256[] public rewardAmounts;
    bytes32[] public rewardLeaves;
    bytes32 public rewardsMerkleRoot;
    Merkle public merkle;

    // Storage slot for rewardsRoot in SuccinctVApp (slot 11 based on contract layout).
    uint256 constant REWARDS_ROOT_SLOT = 11;

    // Events.
    event RewardClaimed(uint256 indexed index, address indexed account, uint256 amount);

    function setUp() public override {
        super.setUp();

        // Set up test rewards data.
        rewardAccounts = [
            makeAddr("REWARD_1"),
            makeAddr("REWARD_2"),
            makeAddr("REWARD_3"),
            makeAddr("REWARD_4"),
            makeAddr("REWARD_5")
        ];
        rewardAmounts = [1 ether, 2 ether, 3 ether, 4 ether, 5 ether];

        // Build the merkle tree.
        for (uint256 i = 0; i < rewardAccounts.length; i++) {
            rewardLeaves.push(keccak256(abi.encodePacked(i, rewardAccounts[i], rewardAmounts[i])));
        }
        merkle = new Merkle();
        rewardsMerkleRoot = merkle.getRoot(rewardLeaves);

        // Fund the VApp with $PROVE for rewards.
        MockERC20(PROVE).mint(VAPP, 100 ether);
    }

    function _setRewardsRoot(bytes32 _root) internal {
        // Use vm.store to directly set the rewardsRoot in storage.
        vm.store(VAPP, bytes32(REWARDS_ROOT_SLOT), _root);
    }

    function test_RewardsInitialState() public view {
        // Rewards root should be empty initially.
        assertEq(SuccinctVApp(VAPP).rewardsRoot(), bytes32(0));

        // All indexes should be unclaimed.
        for (uint256 i = 0; i < rewardAccounts.length; i++) {
            assertEq(SuccinctVApp(VAPP).isClaimed(i), false);
        }
    }

    function test_RewardClaim_WithValidProof() public {
        // Set the rewards root.
        _setRewardsRoot(rewardsMerkleRoot);

        // Verify the root was set correctly.
        assertEq(
            SuccinctVApp(VAPP).rewardsRoot(), rewardsMerkleRoot, "Rewards root not set correctly"
        );

        uint256 vappBalBefore = MockERC20(PROVE).balanceOf(VAPP);

        for (uint256 i = 0; i < rewardAccounts.length; i++) {
            // Setup.
            address claimer = rewardAccounts[i];
            uint256 amount = rewardAmounts[i];
            bytes32[] memory proof = merkle.getProof(rewardLeaves, i);
            uint256 preClaimerBalance = MockERC20(PROVE).balanceOf(claimer);
            bool preIsClaimedState = SuccinctVApp(VAPP).isClaimed(i);

            // Check pre-claim state.
            assertEq(preClaimerBalance, 0);
            assertEq(preIsClaimedState, false);

            // Claim.
            vm.expectEmit(true, true, true, true, VAPP);
            emit RewardClaimed(i, claimer, amount);
            SuccinctVApp(VAPP).rewardClaim(i, claimer, amount, proof);

            // Check post-claim state.
            assertEq(MockERC20(PROVE).balanceOf(claimer), amount);
            vappBalBefore -= amount;
            assertEq(MockERC20(PROVE).balanceOf(VAPP), vappBalBefore);
            assertEq(SuccinctVApp(VAPP).isClaimed(i), true);
        }
    }

    function test_RevertRewardClaim_AlreadyClaimed() public {
        // Set the rewards root.
        _setRewardsRoot(rewardsMerkleRoot);

        // Claim all rewards.
        for (uint256 i = 0; i < rewardAccounts.length; i++) {
            bytes32[] memory proof = merkle.getProof(rewardLeaves, i);
            SuccinctVApp(VAPP).rewardClaim(i, rewardAccounts[i], rewardAmounts[i], proof);
        }

        // Attempt to claim again.
        for (uint256 i = 0; i < rewardAccounts.length; i++) {
            bytes32[] memory proof = merkle.getProof(rewardLeaves, i);
            vm.expectRevert(ISuccinctVApp.RewardAlreadyClaimed.selector);
            SuccinctVApp(VAPP).rewardClaim(i, rewardAccounts[i], rewardAmounts[i], proof);
        }
    }

    function test_RevertRewardClaim_InvalidProof() public {
        // Set the rewards root.
        _setRewardsRoot(rewardsMerkleRoot);

        // Setup.
        uint256 index = 0;
        uint256 invalidIndex = 1;
        address claimer = rewardAccounts[index];
        uint256 amount = rewardAmounts[index];
        bytes32[] memory invalidProof = merkle.getProof(rewardLeaves, invalidIndex);

        // Attempt to claim with an invalid proof.
        vm.expectRevert(ISuccinctVApp.InvalidProof.selector);
        SuccinctVApp(VAPP).rewardClaim(index, claimer, amount, invalidProof);
    }

    function test_RevertRewardClaim_WhenPaused() public {
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

    function test_IsClaimed_BitMapLogic() public {
        // Set the rewards root.
        _setRewardsRoot(rewardsMerkleRoot);

        // Test the bitmap logic for various indexes.
        assertEq(SuccinctVApp(VAPP).isClaimed(0), false);
        assertEq(SuccinctVApp(VAPP).isClaimed(255), false);
        assertEq(SuccinctVApp(VAPP).isClaimed(256), false);
        assertEq(SuccinctVApp(VAPP).isClaimed(512), false);

        // Claim index 0.
        bytes32[] memory proof = merkle.getProof(rewardLeaves, 0);
        SuccinctVApp(VAPP).rewardClaim(0, rewardAccounts[0], rewardAmounts[0], proof);
        assertEq(SuccinctVApp(VAPP).isClaimed(0), true);
        assertEq(SuccinctVApp(VAPP).isClaimed(1), false);

        // Test boundary cases for bitmap.
        // These would need proper merkle tree setup to actually claim at boundary indexes,
        // but the bitmap logic is tested above by checking various indexes.
    }

    function test_RewardClaim_TransfersPROVE() public {
        // Set the rewards root.
        _setRewardsRoot(rewardsMerkleRoot);

        // Check initial balances.
        uint256 initialVAppBalance = MockERC20(PROVE).balanceOf(VAPP);
        uint256 initialClaimerBalance = MockERC20(PROVE).balanceOf(rewardAccounts[0]);
        assertEq(initialClaimerBalance, 0);

        // Claim reward.
        bytes32[] memory proof = merkle.getProof(rewardLeaves, 0);
        SuccinctVApp(VAPP).rewardClaim(0, rewardAccounts[0], rewardAmounts[0], proof);

        // Verify transfer occurred.
        assertEq(MockERC20(PROVE).balanceOf(rewardAccounts[0]), rewardAmounts[0]);
        assertEq(MockERC20(PROVE).balanceOf(VAPP), initialVAppBalance - rewardAmounts[0]);
    }

    function test_RewardClaim_DifferentCaller() public {
        // Set the rewards root.
        _setRewardsRoot(rewardsMerkleRoot);

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

    function test_RevertRewardClaim_WrongAmount() public {
        // Set the rewards root.
        _setRewardsRoot(rewardsMerkleRoot);

        // Try to claim with wrong amount.
        bytes32[] memory proof = merkle.getProof(rewardLeaves, 0);
        uint256 wrongAmount = rewardAmounts[0] + 1;

        vm.expectRevert(ISuccinctVApp.InvalidProof.selector);
        SuccinctVApp(VAPP).rewardClaim(0, rewardAccounts[0], wrongAmount, proof);
    }

    function test_RevertRewardClaim_WrongAccount() public {
        // Set the rewards root.
        _setRewardsRoot(rewardsMerkleRoot);

        // Try to claim with wrong account.
        bytes32[] memory proof = merkle.getProof(rewardLeaves, 0);
        address wrongAccount = makeAddr("WRONG_ACCOUNT");

        vm.expectRevert(ISuccinctVApp.InvalidProof.selector);
        SuccinctVApp(VAPP).rewardClaim(0, wrongAccount, rewardAmounts[0], proof);
    }

    function test_RevertRewardClaim_EmptyProof() public {
        // Set the rewards root.
        _setRewardsRoot(rewardsMerkleRoot);

        // Try to claim with empty proof.
        bytes32[] memory emptyProof = new bytes32[](0);

        vm.expectRevert(ISuccinctVApp.InvalidProof.selector);
        SuccinctVApp(VAPP).rewardClaim(0, rewardAccounts[0], rewardAmounts[0], emptyProof);
    }

    function test_PartialRewardClaims() public {
        // Set the rewards root.
        _setRewardsRoot(rewardsMerkleRoot);

        // Claim only some rewards (not all).
        uint256 totalClaimed = 0;
        for (uint256 i = 0; i < 3; i++) {
            bytes32[] memory proof = merkle.getProof(rewardLeaves, i);
            SuccinctVApp(VAPP).rewardClaim(i, rewardAccounts[i], rewardAmounts[i], proof);
            totalClaimed += rewardAmounts[i];
        }

        // Check claimed status.
        assertEq(SuccinctVApp(VAPP).isClaimed(0), true);
        assertEq(SuccinctVApp(VAPP).isClaimed(1), true);
        assertEq(SuccinctVApp(VAPP).isClaimed(2), true);
        assertEq(SuccinctVApp(VAPP).isClaimed(3), false);
        assertEq(SuccinctVApp(VAPP).isClaimed(4), false);

        // Verify correct balances.
        uint256 expectedRemainingBalance = 100 ether - totalClaimed;
        assertEq(MockERC20(PROVE).balanceOf(VAPP), expectedRemainingBalance);
    }
}
