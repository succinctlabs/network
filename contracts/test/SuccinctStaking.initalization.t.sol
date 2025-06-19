// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SuccinctStakingTest} from "./SuccinctStaking.t.sol";
import {SuccinctStaking} from "../src/SuccinctStaking.sol";
import {Ownable} from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {Initializable} from "../lib/openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";

contract SuccinctStakingInitalizationTests is SuccinctStakingTest {
    function test_RevertInitialize_WhenNotOwner() public {
        address staking2 = address(new SuccinctStaking(makeAddr("NOT_OWNER")));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, OWNER));
        vm.prank(OWNER);
        SuccinctStaking(staking2).initialize(
            GOVERNOR,
            VAPP,
            PROVE,
            I_PROVE,
            MIN_STAKE_AMOUNT,
            UNSTAKE_PERIOD,
            SLASH_PERIOD,
            DISPENSE_RATE
        );
    }

    function test_RevertInitialize_WhenAlreadyInitialized() public {
        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        vm.prank(OWNER);
        SuccinctStaking(STAKING).initialize(
            GOVERNOR,
            VAPP,
            PROVE,
            I_PROVE,
            MIN_STAKE_AMOUNT,
            UNSTAKE_PERIOD,
            SLASH_PERIOD,
            DISPENSE_RATE
        );
    }
}
