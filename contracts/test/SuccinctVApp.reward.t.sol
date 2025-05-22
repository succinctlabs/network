// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SuccinctVAppTest} from "./SuccinctVApp.t.sol";
import {SuccinctVApp} from "../src/SuccinctVApp.sol";
import {ISuccinctVApp} from "../src/interfaces/ISuccinctVApp.sol";
import {Actions} from "../src/libraries/Actions.sol";
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
import {MockERC20} from "./utils/MockERC20.sol";
import {ERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ISuccinctStaking} from "../src/interfaces/ISuccinctStaking.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {MockStaking} from "../src/mocks/MockStaking.sol";

contract SuccinctVAppRewardTest is SuccinctVAppTest {
    function test_Reward_WhenValid() public {
        address proverToReward = REQUESTER_1;
        uint256 rewardAmount = 100e18; // 100 PROVE tokens (assuming 18 decimals)
        uint256 initialVappProveBalance = 200e18;

        // Mint PROVE tokens to VAPP contract, as it's the source of rewards
        MockERC20(PROVE).mint(address(VAPP), initialVappProveBalance);
        assertEq(MockERC20(PROVE).balanceOf(address(VAPP)), initialVappProveBalance);
        assertEq(MockERC20(PROVE).balanceOf(proverToReward), 0);

        // Set VAPP address in MockStaking
        MockStaking(STAKING).setVApp(address(VAPP));

        // Set up approval from VAPP to STAKING for reward amount
        vm.prank(address(VAPP));
        MockERC20(PROVE).approve(STAKING, rewardAmount);

        // Prepare PublicValues for updateState
        bytes memory rewardData =
            abi.encode(RewardAction({prover: proverToReward, amount: rewardAmount}));

        PublicValuesStruct memory publicValues = PublicValuesStruct({
            actions: new Action[](1),
            oldRoot: SuccinctVApp(VAPP).root(), // Should be bytes32(0) initially
            newRoot: bytes32(uint256(0xbeef)), // Arbitrary new root
            timestamp: uint64(block.timestamp) // Current block timestamp
        });
        publicValues.actions[0] = Action({
            action: ActionType.Reward,
            status: ReceiptStatus.Completed,
            receipt: 1, // Rewards don't create pending receipts, this is an ID for the completed action
            data: rewardData
        });

        // Mock verifier call
        mockCall(true);

        // Expect VAPP to call STAKING.reward(proverToReward, rewardAmount)
        // The MockStaking contract's reward function should execute transferFrom(VAPP, proverToReward, rewardAmount)
        vm.expectCall(
            STAKING,
            abi.encodeWithSelector(ISuccinctStaking.reward.selector, proverToReward, rewardAmount),
            1 // Expected number of calls
        );

        // Expect VAPP to approve STAKING contract to spend VAPP's PROVE tokens
        vm.expectEmit(true, false, false, true); // address, bool, bool, address
        emit IERC20.Approval(address(VAPP), STAKING, rewardAmount);

        // Expect PROVE tokens to be transferred from VAPP to proverToReward (via STAKING contract)
        vm.expectEmit(true, true, false, true); // address, address, bool, address
        emit IERC20.Transfer(address(VAPP), proverToReward, rewardAmount);

        // Expect ReceiptCompleted event for the reward
        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.ReceiptCompleted(1, ActionType.Reward, rewardData);

        // Expect Block event
        uint64 expectedBlockNumber = SuccinctVApp(VAPP).blockNumber() + 1;
        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.Block(expectedBlockNumber, publicValues.newRoot, publicValues.oldRoot);

        // Perform the state update
        SuccinctVApp(VAPP).updateState(abi.encode(publicValues), jsonFixture.proof);

        // Assert final state
        assertEq(MockERC20(PROVE).balanceOf(address(VAPP)), initialVappProveBalance - rewardAmount);
        assertEq(MockERC20(PROVE).balanceOf(proverToReward), rewardAmount);
        assertEq(SuccinctVApp(VAPP).finalizedReceipt(), 1);
        assertEq(SuccinctVApp(VAPP).blockNumber(), expectedBlockNumber);
        assertEq(SuccinctVApp(VAPP).root(), publicValues.newRoot);
        assertEq(SuccinctVApp(VAPP).timestamp(), publicValues.timestamp);
    }
}
