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
    RemoveSignerAction
} from "../src/libraries/PublicValues.sol";
import {ISuccinctVApp} from "../src/interfaces/ISuccinctVApp.sol";
import {Ownable} from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";

// Tests onlyOwner / setter functions.
contract SuccinctVAppOwnerTest is SuccinctVAppTest {
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

    function test_UpdateActionDelay_WhenValid() public {
        uint64 oldDelay = ISuccinctVApp(VAPP).maxActionDelay();
        uint64 newDelay = 2 days;

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.MaxActionDelayUpdate(oldDelay, newDelay);
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
        SuccinctVApp(VAPP).updateMinDepositAmount(newTransferBelowMinimum);

        assertEq(SuccinctVApp(VAPP).minDepositAmount(), newTransferBelowMinimum);

        // Set to zero to disable minimum check
        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.MinDepositAmountUpdate(newTransferBelowMinimum, 0);
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

    function test_SetProtocolFeeBips_WhenValid() public {
        uint256 oldProtocolFeeBips = ISuccinctVApp(VAPP).protocolFeeBips();
        uint256 newProtocolFeeBips = PROTOCOL_FEE_BIPS + 1; // 10%

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.ProtocolFeeBipsUpdate(oldProtocolFeeBips, newProtocolFeeBips);
        vm.prank(OWNER);
        SuccinctVApp(VAPP).updateProtocolFeeBips(newProtocolFeeBips);

        assertEq(SuccinctVApp(VAPP).protocolFeeBips(), newProtocolFeeBips);
    }

    function test_RevertSetProtocolFeeBips_WhenNotOwner() public {
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, REQUESTER_1)
        );
        vm.prank(REQUESTER_1);
        SuccinctVApp(VAPP).updateProtocolFeeBips(1000);
    }
}
