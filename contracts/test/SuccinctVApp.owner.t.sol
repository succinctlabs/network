// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SuccinctVAppTest} from "./SuccinctVApp.t.sol";
import {SuccinctVApp} from "../src/SuccinctVApp.sol";
import {ISuccinctVApp} from "../src/interfaces/ISuccinctVApp.sol";
import {Ownable} from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {PausableUpgradeable} from
    "../lib/openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";

// Tests onlyOwner / setter functions.
contract SuccinctVAppOwnerTest is SuccinctVAppTest {
    function test_Fork_WhenValid() public {
        bytes32 oldVkey = SuccinctVApp(VAPP).vkey();
        bytes32 newVkey = bytes32(uint256(1));
        bytes32 newRoot = bytes32(uint256(2));

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.Fork(1, oldVkey, newVkey);
        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.Block(1, fixture.oldRoot, newRoot);

        vm.prank(OWNER);
        SuccinctVApp(VAPP).fork(newVkey, newRoot);
    }

    function test_RevertFork_WhenNotOwner() public {
        bytes32 newVkey = bytes32(uint256(1));
        bytes32 newRoot = bytes32(uint256(2));

        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, REQUESTER_1)
        );
        vm.prank(REQUESTER_1);
        SuccinctVApp(VAPP).fork(newVkey, newRoot);
    }

    function test_UpdateAuctioneer_WhenValid() public {
        address oldAuctioneer = ISuccinctVApp(VAPP).auctioneer();
        address newAuctioneer = address(1);

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.AuctioneerUpdate(oldAuctioneer, newAuctioneer);
        vm.prank(OWNER);
        SuccinctVApp(VAPP).updateAuctioneer(newAuctioneer);

        assertEq(SuccinctVApp(VAPP).auctioneer(), newAuctioneer);
    }

    function test_RevertUpdateAuctioneer_WhenNotOwner() public {
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, REQUESTER_1)
        );
        vm.prank(REQUESTER_1);
        SuccinctVApp(VAPP).updateAuctioneer(address(1));
    }

    function test_UpdateStaking_WhenValid() public {
        address oldStaking = ISuccinctVApp(VAPP).staking();
        address newStaking = address(1);

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.StakingUpdate(oldStaking, newStaking);
        vm.prank(OWNER);
        SuccinctVApp(VAPP).updateStaking(newStaking);

        assertEq(SuccinctVApp(VAPP).staking(), newStaking);
    }

    function test_RevertUpdateStaking_WhenNotOwner() public {
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, REQUESTER_1)
        );
        vm.prank(REQUESTER_1);
        SuccinctVApp(VAPP).updateStaking(address(1));
    }

    function test_UpdateVerifier_WhenValid() public {
        address oldVerifier = ISuccinctVApp(VAPP).verifier();
        address newVerifier = address(1);

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.VerifierUpdate(oldVerifier, newVerifier);
        vm.prank(OWNER);
        SuccinctVApp(VAPP).updateVerifier(newVerifier);

        assertEq(SuccinctVApp(VAPP).verifier(), newVerifier);
    }

    function test_RevertUpdateVerifier_WhenNotOwner() public {
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, REQUESTER_1)
        );
        vm.prank(REQUESTER_1);
        SuccinctVApp(VAPP).updateVerifier(address(1));
    }

    function test_SetTransferBelowMinimum_WhenValid() public {
        uint256 oldMinAmount = ISuccinctVApp(VAPP).minDepositAmount();
        uint256 newMinAmount = 10e6; // 10 PROVE

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.MinDepositAmountUpdate(oldMinAmount, newMinAmount);
        vm.prank(OWNER);
        SuccinctVApp(VAPP).updateMinDepositAmount(newMinAmount);

        assertEq(SuccinctVApp(VAPP).minDepositAmount(), newMinAmount);

        // Update to a different value
        uint256 newTransferBelowMinimum = 20e6; // 20 PROVE

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.MinDepositAmountUpdate(newMinAmount, newTransferBelowMinimum);
        vm.prank(OWNER);
        SuccinctVApp(VAPP).updateMinDepositAmount(newTransferBelowMinimum);

        assertEq(SuccinctVApp(VAPP).minDepositAmount(), newTransferBelowMinimum);

        // Set to zero to disable minimum check
        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.MinDepositAmountUpdate(newTransferBelowMinimum, 0);
        vm.prank(OWNER);
        SuccinctVApp(VAPP).updateMinDepositAmount(0);

        assertEq(SuccinctVApp(VAPP).minDepositAmount(), 0);
    }

    function test_RevertSetminDepositAmount_WhenNotOwner() public {
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, REQUESTER_1)
        );
        vm.prank(REQUESTER_1);
        SuccinctVApp(VAPP).updateMinDepositAmount(10e6);
    }

    function test_Pause_WhenValid() public {
        vm.expectEmit(true, true, true, true);
        emit PausableUpgradeable.Paused(OWNER);
        vm.prank(OWNER);
        SuccinctVApp(VAPP).pause();

        assertEq(PausableUpgradeable(VAPP).paused(), true);
    }

    function test_RevertPause_WhenNotOwner() public {
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, REQUESTER_1)
        );
        vm.prank(REQUESTER_1);
        SuccinctVApp(VAPP).pause();
    }

    function test_Unpause_WhenValid() public {
        vm.prank(OWNER);
        SuccinctVApp(VAPP).pause();

        vm.expectEmit(true, true, true, true);
        emit PausableUpgradeable.Unpaused(OWNER);
        vm.prank(OWNER);
        SuccinctVApp(VAPP).unpause();

        assertEq(PausableUpgradeable(VAPP).paused(), false);
    }

    function test_RevertUnpause_WhenNotOwner() public {
        vm.prank(OWNER);
        SuccinctVApp(VAPP).pause();

        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, REQUESTER_1)
        );
        vm.prank(REQUESTER_1);
        SuccinctVApp(VAPP).unpause();
    }
}
