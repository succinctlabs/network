// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// import {SuccinctVAppTest} from "./SuccinctVApp.t.sol";
// import {SuccinctVApp} from "../src/SuccinctVApp.sol";
// import {ISuccinctVApp} from "../src/interfaces/ISuccinctVApp.sol";
// import {Actions} from "../src/libraries/Actions.sol";
// import {
//     PublicValuesStruct,
//     ReceiptStatus,
//     Action,
//     ActionType,
//     DepositAction,
//     WithdrawAction,
//     AddSignerAction
// } from "../src/libraries/PublicValues.sol";
// import {ISuccinctVApp} from "../src/interfaces/ISuccinctVApp.sol";
// import {MockERC20} from "./utils/MockERC20.sol";
// import {ERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
// import {ISuccinctStaking} from "../src/interfaces/ISuccinctStaking.sol";
// import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
// import {MockStaking} from "../src/mocks/MockStaking.sol";
// import {SuccinctProver} from "../src/tokens/SuccinctProver.sol";
// import {IProver} from "../src/interfaces/IProver.sol";

// contract SuccinctVAppRewardTest is SuccinctVAppTest {
//     /// @dev For stack-too-deep workaround
//     struct RewardTestData {
//         address prover;
//         uint256 vappInitialBalance;
//         uint256 rewardAmount;
//         uint256 initialProverBalance;
//         uint256 initialAliceBalance;
//         uint256 stakerFeeBips;
//         uint256 protocolFeeBips;
//         uint256 protocolReward;
//         uint256 remainingAfterProtocol;
//         uint256 stakerReward;
//         uint256 ownerReward;
//         bytes rewardData;
//         uint64 expectedBlockNumber;
//     }

//     function test_Reward_WhenValid() public {
//         RewardTestData memory data;

//         data.prover = address(new SuccinctProver(PROVE, STAKING, ALICE, 1, 1000));
//         data.vappInitialBalance = 1000e18; // 1000 PROVE tokens
//         data.rewardAmount = 100e18 / 2; // Reward half of VApp's balance

//         // Give the VAPP some initial balance (simulates some existing deposits) so that it can reward
//         MockERC20(PROVE).mint(VAPP, data.vappInitialBalance);

//         // Record initial balances
//         data.initialProverBalance = IERC20(PROVE).balanceOf(data.prover);
//         data.initialAliceBalance = IERC20(PROVE).balanceOf(ALICE);

//         // Verify VApp has the tokens
//         assertEq(MockERC20(PROVE).balanceOf(VAPP), data.vappInitialBalance);
//         assertEq(MockERC20(PROVE).balanceOf(data.prover), 0);

//         // Set VAPP address in MockStaking
//         MockStaking(STAKING).setVApp(VAPP);

//         // Calculate rewards with protocol fee logic
//         data.stakerFeeBips = IProver(data.prover).stakerFeeBips();
//         data.protocolFeeBips = SuccinctVApp(VAPP).protocolFeeBips();
//         data.protocolReward = (data.rewardAmount * data.protocolFeeBips) / 10000;
//         data.remainingAfterProtocol = data.rewardAmount - data.protocolReward;
//         data.stakerReward = (data.remainingAfterProtocol * data.stakerFeeBips) / 10000;
//         data.ownerReward = data.remainingAfterProtocol - data.stakerReward;

//         vm.prank(VAPP);
//         MockERC20(PROVE).approve(STAKING, data.stakerReward);

//         // Prepare PublicValues for updateState
//         data.rewardData = abi.encode(RewardAction({prover: data.prover, amount: data.rewardAmount}));

//         PublicValuesStruct memory publicValues = PublicValuesStruct({
//             actions: new Action[](1),
//             oldRoot: SuccinctVApp(VAPP).root(), // Should be bytes32(0) initially
//             newRoot: bytes32(uint256(0xbeef)), // Arbitrary new root
//             timestamp: uint64(block.timestamp) // Current block timestamp
//         });
//         publicValues.actions[0] = Action({
//             action: ActionType.Reward,
//             status: ReceiptStatus.Completed,
//             receipt: 1, // Rewards don't create pending receipts, this is an ID for the completed action
//             data: data.rewardData
//         });

//         // Mock verifier call
//         mockCall(true);

//         // Expect VAPP to call STAKING.reward(prover, stakerReward) - only the staker portion
//         vm.expectCall(
//             STAKING,
//             abi.encodeWithSelector(ISuccinctStaking.reward.selector, data.prover, data.stakerReward),
//             1 // Expected number of calls
//         );

//         // Expect PROVE tokens to be transferred from VAPP to FEE_VAULT (protocol fee)
//         vm.expectEmit(true, true, false, true);
//         emit IERC20.Transfer(VAPP, FEE_VAULT, data.protocolReward);

//         // Expect PROVE tokens to be transferred from VAPP to STAKING (staker reward)
//         vm.expectEmit(true, true, false, true);
//         emit IERC20.Transfer(VAPP, STAKING, data.stakerReward);

//         // Expect PROVE tokens to be transferred from VAPP to ALICE (owner reward)
//         vm.expectEmit(true, true, false, true);
//         emit IERC20.Transfer(VAPP, ALICE, data.ownerReward);

//         // Expect ReceiptCompleted event for the reward
//         vm.expectEmit(true, true, true, true);
//         emit ISuccinctVApp.ReceiptCompleted(1, ActionType.Reward, data.rewardData);

//         // Expect Block event
//         data.expectedBlockNumber = SuccinctVApp(VAPP).blockNumber() + 1;
//         vm.expectEmit(true, true, true, true);
//         emit ISuccinctVApp.Block(
//             data.expectedBlockNumber, publicValues.newRoot, publicValues.oldRoot
//         );

//         // Perform the state update
//         SuccinctVApp(VAPP).updateState(abi.encode(publicValues), jsonFixture.proof);

//         // Assert final state
//         // VApp transfers out: protocolReward + ownerReward + stakerReward
//         assertEq(
//             MockERC20(PROVE).balanceOf(VAPP),
//             data.vappInitialBalance - data.protocolReward - data.ownerReward - data.stakerReward
//         );
//         assertEq(SuccinctVApp(VAPP).finalizedReceipt(), 1);
//         assertEq(SuccinctVApp(VAPP).blockNumber(), data.expectedBlockNumber);
//         assertEq(SuccinctVApp(VAPP).root(), publicValues.newRoot);
//         assertEq(SuccinctVApp(VAPP).timestamp(), publicValues.timestamp);

//         // Verify prover properties
//         assertEq(IProver(data.prover).owner(), ALICE, "Prover owner should be ALICE");
//         assertEq(IProver(data.prover).staking(), STAKING, "Prover staking should be set correctly");
//         assertEq(IProver(data.prover).stakerFeeBips(), 1000, "Prover staker fee should be 10%");

//         // Verify the fee splitting worked correctly:
//         // VApp should split rewards: remainder to prover owner (ALICE), staker portion to staking contract

//         // Assert ALICE (prover owner) received the owner reward portion
//         assertEq(
//             MockERC20(PROVE).balanceOf(ALICE),
//             data.initialAliceBalance + data.ownerReward,
//             "Prover owner (ALICE) should receive the owner reward portion"
//         );

//         // Assert prover contract balance remains unchanged (staker rewards go to staking contract)
//         assertEq(
//             MockERC20(PROVE).balanceOf(data.prover),
//             data.initialProverBalance,
//             "Prover contract balance should remain unchanged"
//         );

//         // Verify the math
//         assertEq(
//             data.ownerReward,
//             (data.remainingAfterProtocol * (10000 - data.stakerFeeBips)) / 10000,
//             "Owner reward should be calculated correctly"
//         );
//         assertEq(
//             data.stakerReward,
//             (data.remainingAfterProtocol * data.stakerFeeBips) / 10000,
//             "Staker reward should be calculated correctly"
//         );
//         assertEq(
//             data.ownerReward + data.stakerReward,
//             data.remainingAfterProtocol,
//             "Rewards should sum to remaining after protocol fee"
//         );

//         // After reward distribution:
//         // - protocolReward goes to FEE_VAULT
//         // - ownerReward goes to ALICE (prover owner)
//         // - stakerReward goes to STAKING (for distribution to stakers)
//         // So VApp should have vappInitialBalance - protocolReward - ownerReward - stakerReward remaining
//         assertEq(
//             MockERC20(PROVE).balanceOf(VAPP),
//             data.vappInitialBalance - data.protocolReward - data.ownerReward - data.stakerReward
//         );
//     }
// }
