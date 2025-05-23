// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SuccinctVAppTest} from "./SuccinctVApp.t.sol";
import {SuccinctVApp} from "../src/SuccinctVApp.sol";
import {ISuccinctVApp} from "../src/interfaces/ISuccinctVApp.sol";
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
import {Ownable} from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";

// Tests onlyOwner / setter functions.
contract SuccinctVAppOwnerTest is SuccinctVAppTest {
    function test_UpdateStaking_WhenValid() public {
        address newStaking = address(1);

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.UpdatedStaking(newStaking);
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
        address newVerifier = address(1);

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.UpdatedVerifier(newVerifier);
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

    function test_UpdateActionDelay_WhenValid() public {
        uint64 newDelay = 2 days;

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.UpdatedMaxActionDelay(newDelay);
        vm.prank(OWNER);
        SuccinctVApp(VAPP).updateActionDelay(newDelay);

        assertEq(SuccinctVApp(VAPP).maxActionDelay(), newDelay);
    }

    function test_RevertUpdateActionDelay_WhenNotOwner() public {
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, REQUESTER_1)
        );
        vm.prank(REQUESTER_1);
        SuccinctVApp(VAPP).updateActionDelay(2 days);
    }

    function test_UpdateFreezeDuration() public {
        uint64 newDuration = 3 days;

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.UpdatedFreezeDuration(newDuration);
        vm.prank(OWNER);
        SuccinctVApp(VAPP).updateFreezeDuration(newDuration);

        assertEq(SuccinctVApp(VAPP).freezeDuration(), newDuration);
    }

    function test_RevertUpdateFreezeDuration_WhenNotOwner() public {
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, REQUESTER_1)
        );
        vm.prank(REQUESTER_1);
        SuccinctVApp(VAPP).updateFreezeDuration(3 days);
    }

    function test_SetDepositBelowMinimum_WhenValid() public {
        uint256 minAmount = 10e6; // 10 PROVE

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.MinimumDepositUpdated(minAmount);
        vm.prank(OWNER);
        SuccinctVApp(VAPP).setMinimumDeposit(minAmount);

        assertEq(SuccinctVApp(VAPP).minimumDeposit(), minAmount);

        // Update to a different value
        uint256 newDepositBelowMinimum = 20e6; // 20 PROVE

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.MinimumDepositUpdated(newDepositBelowMinimum);
        SuccinctVApp(VAPP).setMinimumDeposit(newDepositBelowMinimum);

        assertEq(SuccinctVApp(VAPP).minimumDeposit(), newDepositBelowMinimum);

        // Set to zero to disable minimum check
        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.MinimumDepositUpdated(0);
        SuccinctVApp(VAPP).setMinimumDeposit(0);

        assertEq(SuccinctVApp(VAPP).minimumDeposit(), 0);
    }

    function test_RevertSetMinimumDeposit_WhenNotOwner() public {
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, REQUESTER_1)
        );
        vm.prank(REQUESTER_1);
        SuccinctVApp(VAPP).setMinimumDeposit(10e6);
    }
}
