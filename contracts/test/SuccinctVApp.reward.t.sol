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
}
