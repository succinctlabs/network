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

    function test_AddToken_WhenValid() public {
        address token = address(99);

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.TokenWhitelist(token, true);
        SuccinctVApp(VAPP).addToken(token);

        assertTrue(SuccinctVApp(VAPP).whitelistedTokens(token));
    }

    function test_RevertAddToken_WhenNotOwner() public {
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, REQUESTER_1)
        );
        vm.prank(REQUESTER_1);
        SuccinctVApp(VAPP).addToken(address(99));
    }

    function test_RevertAddToken_WhenZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(ISuccinctVApp.ZeroAddress.selector));
        vm.prank(OWNER);
        SuccinctVApp(VAPP).addToken(address(0));
    }

    function test_RevertAddToken_WhenAlreadyWhitelisted() public {
        address token = address(99);
        vm.prank(OWNER);
        SuccinctVApp(VAPP).addToken(token);

        vm.expectRevert(abi.encodeWithSelector(ISuccinctVApp.TokenAlreadyWhitelisted.selector));
        vm.prank(OWNER);
        SuccinctVApp(VAPP).addToken(token);
    }

    function test_RemoveToken_WhenValid() public {
        address token = address(99);
        vm.prank(OWNER);
        SuccinctVApp(VAPP).addToken(token);

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.TokenWhitelist(token, false);
        vm.prank(OWNER);
        SuccinctVApp(VAPP).removeToken(token);

        assertFalse(SuccinctVApp(VAPP).whitelistedTokens(token));
    }

    function test_RevertRemoveToken_WhenNotOwner() public {
        address token = address(99);
        SuccinctVApp(VAPP).addToken(token);

        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, REQUESTER_1)
        );
        vm.prank(REQUESTER_1);
        SuccinctVApp(VAPP).removeToken(token);
    }

    function test_RevertRemoveToken_WhenNotWhitelisted() public {
        address token = address(99);

        vm.expectRevert(abi.encodeWithSelector(ISuccinctVApp.TokenNotWhitelisted.selector));
        vm.prank(OWNER);
        SuccinctVApp(VAPP).removeToken(token);
    }

    function test_SetDepositBelowMinimum_WhenValid() public {
        address token = PROVE;
        uint256 minAmount = 10e6; // 10 PROVE

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.DepositBelowMinimumUpdated(token, minAmount);
        vm.prank(OWNER);
        SuccinctVApp(VAPP).setMinimumDeposit(token, minAmount);

        assertEq(SuccinctVApp(VAPP).minAmounts(token), minAmount);

        // Update to a different value
        uint256 newDepositBelowMinimum = 20e6; // 20 PROVE

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.DepositBelowMinimumUpdated(token, newDepositBelowMinimum);
        SuccinctVApp(VAPP).setMinimumDeposit(token, newDepositBelowMinimum);

        assertEq(SuccinctVApp(VAPP).minAmounts(token), newDepositBelowMinimum);

        // Set to zero to disable minimum check
        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.DepositBelowMinimumUpdated(token, 0);
        SuccinctVApp(VAPP).setMinimumDeposit(token, 0);

        assertEq(SuccinctVApp(VAPP).minAmounts(token), 0);
    }

    function test_RevertSetMinimumDeposit_WhenZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(ISuccinctVApp.ZeroAddress.selector));
        SuccinctVApp(VAPP).setMinimumDeposit(address(0), 10e6);
    }

    function test_RevertSetMinimumDeposit_WhenNotOwner() public {
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, REQUESTER_1)
        );
        vm.prank(REQUESTER_1);
        SuccinctVApp(VAPP).setMinimumDeposit(PROVE, 10e6);
    }
}
