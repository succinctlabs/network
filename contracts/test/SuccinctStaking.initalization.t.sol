// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SuccinctStakingTest} from "./SuccinctStaking.t.sol";
import {SuccinctStaking} from "../src/SuccinctStaking.sol";
import {Initializable} from "../lib/openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";

contract SuccinctStakingInitalizationTests is SuccinctStakingTest {
    function test_RevertInitialize_WhenNotProxy() public {
        address stakingImpl = address(new SuccinctStaking());
        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        SuccinctStaking(stakingImpl).initialize(
            OWNER,
            GOVERNOR,
            VAPP,
            PROVE,
            I_PROVE,
            DISPENSER,
            MIN_STAKE_AMOUNT,
            MAX_UNSTAKE_REQUESTS,
            UNSTAKE_PERIOD,
            SLASH_CANCELLATION_PERIOD
        );
    }

    function test_RevertInitialize_WhenAlreadyInitialized() public {
        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        vm.prank(OWNER);
        SuccinctStaking(STAKING).initialize(
            OWNER,
            GOVERNOR,
            VAPP,
            PROVE,
            I_PROVE,
            DISPENSER,
            MIN_STAKE_AMOUNT,
            MAX_UNSTAKE_REQUESTS,
            UNSTAKE_PERIOD,
            SLASH_CANCELLATION_PERIOD
        );
    }
}
