// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "../lib/forge-std/src/Test.sol";
import {Succinct} from "../src/tokens/Succinct.sol";
import {SuccinctStaking} from "../src/SuccinctStaking.sol";
import {SuccinctVApp} from "../src/SuccinctVApp.sol";
import {IntermediateSuccinct} from "../src/tokens/IntermediateSuccinct.sol";
import {IProver} from "../src/interfaces/IProver.sol";
import {IIntermediateSuccinct} from "../src/interfaces/IIntermediateSuccinct.sol";
import {ERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {IERC20Permit} from
    "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {IERC4626} from "../lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {FixtureLoader, Fixture, SP1ProofFixtureJson} from "./utils/FixtureLoader.sol";
import {MockVerifier} from "../src/mocks/MockVerifier.sol";
import {ISP1Verifier} from "../src/interfaces/ISP1Verifier.sol";
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

import {ERC1967Proxy} from "../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Tests the entire protocol end-to-end, using realistic values for parameters.
contract E2ETest is Test, FixtureLoader {
    // Constants
    uint256 public constant FEE_UNIT = 10000;
    uint256 public constant STAKING_PROVE_AMOUNT = 1000e18;
    uint256 public constant REQUESTER_PROVE_AMOUNT = 10e18;
    uint256 public constant STAKER_PROVE_AMOUNT = 10e18;
    uint256 public constant MIN_STAKE_AMOUNT = 1e12;
    uint256 public constant UNSTAKE_PERIOD = 21 days;
    uint256 public constant SLASH_PERIOD = 7 days;
    uint256 public constant DISPENSE_RATE = 1268391679; // ~4% yearly
    uint64 public constant MAX_ACTION_DELAY = 1 days;
    uint64 public constant FREEZE_DURATION = 1 days;
    uint256 public constant STAKER_FEE_BIPS = 1000; // 10%
    uint256 public constant PROTOCOL_FEE_BIPS = 30; // 0.3%

    // Fixtures
    SP1ProofFixtureJson public jsonFixture;
    PublicValuesStruct public fixture;

    // EOAs
    address public OWNER;
    address public REQUESTER;
    address public STAKER_1;
    uint256 public STAKER_1_PK;
    address public STAKER_2;
    uint256 public STAKER_2_PK;
    address public ALICE;
    address public BOB;

    // Contracts
    address public FEE_VAULT;
    address public VERIFIER;
    address public STAKING;
    address public VAPP;
    address public PROVE;
    address public I_PROVE;
    address public ALICE_PROVER;
    address public BOB_PROVER;

    function setUp() public virtual {
        // Create the owner
        OWNER = makeAddr("OWNER");

        // Create the requester
        REQUESTER = makeAddr("REQUESTER");

        // Create the staker
        (STAKER_1, STAKER_1_PK) = makeAddrAndKey("STAKER_1");
        (STAKER_2, STAKER_2_PK) = makeAddrAndKey("STAKER_2");

        // Create the provers
        ALICE = makeAddr("ALICE");
        BOB = makeAddr("BOB");

        // Load fixtures
        jsonFixture = loadFixture(vm, Fixture.Groth16);

        PublicValuesStruct memory _fixture =
            abi.decode(jsonFixture.publicValues, (PublicValuesStruct));
        fixture.oldRoot = _fixture.oldRoot;
        fixture.newRoot = _fixture.newRoot;
        for (uint256 i = 0; i < _fixture.actions.length; i++) {
            fixture.actions.push(_fixture.actions[i]);
        }

        // Deploy fee vault (just an EOA for testing)
        FEE_VAULT = makeAddr("FEE_VAULT");

        // Deploy Staking
        STAKING = address(new SuccinctStaking(OWNER));

        // Deploy PROVE
        PROVE = address(new Succinct(OWNER));

        // Deploy I_PROVE
        I_PROVE = address(new IntermediateSuccinct(PROVE, STAKING));

        // Deploy Verifier
        VERIFIER = address(new MockVerifier());

        // Deploy VApp
        address vappImpl = address(new SuccinctVApp());
        VAPP = address(new ERC1967Proxy(vappImpl, ""));

        // Initialize VApp
        SuccinctVApp(VAPP).initialize(
            OWNER,
            PROVE,
            STAKING,
            VERIFIER,
            FEE_VAULT,
            jsonFixture.vkey,
            MAX_ACTION_DELAY,
            FREEZE_DURATION,
            PROTOCOL_FEE_BIPS
        );

        // Initialize Staking
        vm.prank(OWNER);
        SuccinctStaking(STAKING).initialize(
            VAPP, PROVE, I_PROVE, MIN_STAKE_AMOUNT, UNSTAKE_PERIOD, SLASH_PERIOD, DISPENSE_RATE
        );

        // Mint some $PROVE for the staking contract
        deal(PROVE, STAKING, STAKING_PROVE_AMOUNT);

        // Mint some $PROVE for the requester
        deal(PROVE, REQUESTER, REQUESTER_PROVE_AMOUNT);

        // Deposit the $PROVE into the vApp
        vm.prank(REQUESTER);
        IERC20(PROVE).approve(VAPP, REQUESTER_PROVE_AMOUNT);
        vm.prank(REQUESTER);
        SuccinctVApp(VAPP).deposit(REQUESTER_PROVE_AMOUNT);

        // Create the provers
        vm.prank(ALICE);
        ALICE_PROVER = SuccinctStaking(STAKING).createProver(STAKER_FEE_BIPS);
        vm.prank(BOB);
        BOB_PROVER = SuccinctStaking(STAKING).createProver(STAKER_FEE_BIPS);

        // Mint some $PROVE for the stakers
        deal(PROVE, STAKER_1, STAKER_PROVE_AMOUNT);
        deal(PROVE, STAKER_2, STAKER_PROVE_AMOUNT);

        // Staker 1 stakes $PROVE to ALICE_PROVER
        _stake(STAKER_1, ALICE_PROVER, STAKER_PROVE_AMOUNT);
    }

    /// @dev For stack-too-deep workaround
    struct BalanceSnapshot {
        uint256 initialStakerBalance;
        uint256 proverStakedBefore;
        uint256 vappBalanceBefore;
        uint256 proverOwnerBalanceBefore;
        uint256 stakerBalanceBeforeUnstake;
        uint256 expectedUnstakeAmount;
        uint256 finalBalance;
    }

    function _takeSnapshot(bool isInitial) internal view returns (BalanceSnapshot memory) {
        if (isInitial) {
            return BalanceSnapshot({
                initialStakerBalance: IERC20(PROVE).balanceOf(STAKER_1),
                proverStakedBefore: SuccinctStaking(STAKING).proverStaked(ALICE_PROVER),
                vappBalanceBefore: IERC20(PROVE).balanceOf(VAPP),
                proverOwnerBalanceBefore: IERC20(PROVE).balanceOf(ALICE),
                stakerBalanceBeforeUnstake: 0,
                expectedUnstakeAmount: 0,
                finalBalance: 0
            });
        } else {
            return BalanceSnapshot({
                initialStakerBalance: 0,
                proverStakedBefore: 0,
                vappBalanceBefore: 0,
                proverOwnerBalanceBefore: 0,
                stakerBalanceBeforeUnstake: IERC20(PROVE).balanceOf(STAKER_1),
                expectedUnstakeAmount: SuccinctStaking(STAKING).staked(STAKER_1),
                finalBalance: 0
            });
        }
    }

    function _stake(address _staker, address _prover, uint256 _amount) internal {
        vm.prank(_staker);
        IERC20(PROVE).approve(STAKING, _amount);
        vm.prank(_staker);
        SuccinctStaking(STAKING).stake(_prover, _amount);
    }

    function _completeUnstake(address _staker, uint256 _amount) internal returns (uint256) {
        _requestUnstake(_staker, _amount);
        skip(UNSTAKE_PERIOD);
        return _finishUnstake(_staker);
    }

    function _requestUnstake(address _staker, uint256 _amount) internal {
        vm.prank(_staker);
        SuccinctStaking(STAKING).requestUnstake(_amount);
    }

    function _finishUnstake(address _staker) internal returns (uint256) {
        vm.prank(_staker);
        return SuccinctStaking(STAKING).finishUnstake();
    }

    function test_SetUp() public view {
        // Immutable variables
        assertEq(SuccinctStaking(STAKING).vapp(), VAPP);
        assertEq(SuccinctStaking(STAKING).prove(), PROVE);
        assertEq(SuccinctStaking(STAKING).iProve(), I_PROVE);
        assertEq(SuccinctStaking(STAKING).unstakePeriod(), UNSTAKE_PERIOD);
        assertEq(SuccinctStaking(STAKING).slashPeriod(), SLASH_PERIOD);
        assertEq(SuccinctVApp(VAPP).staking(), STAKING);
        assertEq(SuccinctVApp(VAPP).prove(), PROVE);
        assertEq(IIntermediateSuccinct(I_PROVE).staking(), STAKING);
        assertEq(IERC4626(I_PROVE).asset(), PROVE);

        // Prover checks
        assertEq(IProver(ALICE_PROVER).owner(), ALICE);
        assertEq(IProver(BOB_PROVER).owner(), BOB);
        assertEq(IProver(ALICE_PROVER).id(), 1);
        assertEq(IProver(BOB_PROVER).id(), 2);
        assertEq(ERC20(ALICE_PROVER).name(), "SuccinctProver-1");
        assertEq(ERC20(BOB_PROVER).name(), "SuccinctProver-2");
        assertEq(ERC20(ALICE_PROVER).symbol(), "PROVER-1");
        assertEq(ERC20(BOB_PROVER).symbol(), "PROVER-2");
        assertEq(SuccinctStaking(STAKING).proverCount(), 2);
        assertEq(SuccinctStaking(STAKING).ownerOf(ALICE_PROVER), ALICE);
        assertEq(SuccinctStaking(STAKING).ownerOf(BOB_PROVER), BOB);
        assertEq(SuccinctStaking(STAKING).isProver(ALICE_PROVER), true);
        assertEq(SuccinctStaking(STAKING).isProver(BOB_PROVER), true);
        assertEq(SuccinctStaking(STAKING).getProver(ALICE), ALICE_PROVER);
        assertEq(SuccinctStaking(STAKING).getProver(BOB), BOB_PROVER);
        assertEq(SuccinctStaking(STAKING).hasProver(ALICE), true);
        assertEq(SuccinctStaking(STAKING).hasProver(BOB), true);
    }

    // In this scenario:
    // - STAKER_1 stakes to ALICE_PROVER, such that ALICE_PROVER is above the minimum stake amount
    //   to particpate in offchain auctions.
    // - The REQUESTER (already deposited $PROVE), had a proof fulfilled offchain from ALICE_PROVER.
    // - Therefor, the VApp update should transfer $PROVE from the VApp REQUESTER's balance to the
    //   ALICE_PROVER vault. When STAKER_1 unstakes, they should have more $PROVE then the amount
    //   they staked.
    function test_E2E() public {
        uint256 rewardAmount = 5e18; // 5 PROVE tokens as reward (within the 10e18 available in VApp)

        // Take initial snapshot
        BalanceSnapshot memory snapshot = _takeSnapshot(true);

        // Prepare reward action for ALICE_PROVER
        bytes memory rewardData =
            abi.encode(RewardAction({prover: ALICE_PROVER, amount: rewardAmount}));

        PublicValuesStruct memory publicValues = PublicValuesStruct({
            actions: new Action[](1),
            oldRoot: SuccinctVApp(VAPP).root(), // Current root (should be bytes32(0) initially)
            newRoot: bytes32(uint256(0xbeef)), // New root after reward
            timestamp: uint64(block.timestamp)
        });

        publicValues.actions[0] = Action({
            action: ActionType.Reward,
            status: ReceiptStatus.Completed,
            receipt: 1, // Receipt ID for the reward action
            data: rewardData
        });

        // Execute the state update with reward
        SuccinctVApp(VAPP).updateState(abi.encode(publicValues), jsonFixture.proof);

        // Calculate expected reward splits
        uint256 protocolFee = (rewardAmount * PROTOCOL_FEE_BIPS) / FEE_UNIT;
        uint256 remainingAfterProtocol = rewardAmount - protocolFee;
        uint256 expectedStakerReward = (remainingAfterProtocol * STAKER_FEE_BIPS) / FEE_UNIT;
        uint256 expectedProverOwnerReward = remainingAfterProtocol - expectedStakerReward;

        // Verify the reward was processed correctly
        uint256 proverStakedAfter = SuccinctStaking(STAKING).proverStaked(ALICE_PROVER);
        assertEq(
            proverStakedAfter,
            snapshot.proverStakedBefore + expectedStakerReward,
            "Prover should have received staker portion of reward"
        );
        assertEq(
            IERC20(PROVE).balanceOf(VAPP),
            snapshot.vappBalanceBefore - rewardAmount,
            "VApp balance should decrease by full reward amount (protocol fee is transferred out)"
        );
        assertEq(
            IERC20(PROVE).balanceOf(ALICE),
            snapshot.proverOwnerBalanceBefore + expectedProverOwnerReward,
            "Prover owner should have received their portion of reward"
        );

        // Take snapshot before unstake
        BalanceSnapshot memory unstakeSnapshot = _takeSnapshot(false);

        // The staker should now have a share of the reward
        assertGt(
            unstakeSnapshot.expectedUnstakeAmount,
            STAKER_PROVE_AMOUNT,
            "Staker should have earned rewards"
        );

        // Complete the unstake process
        uint256 actualUnstakeAmount =
            _completeUnstake(STAKER_1, SuccinctStaking(STAKING).balanceOf(STAKER_1));

        // Verify final state
        assertEq(
            actualUnstakeAmount,
            unstakeSnapshot.expectedUnstakeAmount,
            "Unstake amount should match expected"
        );
        assertEq(
            IERC20(PROVE).balanceOf(STAKER_1),
            unstakeSnapshot.stakerBalanceBeforeUnstake + actualUnstakeAmount,
            "Staker should receive unstaked amount"
        );
        assertGt(
            IERC20(PROVE).balanceOf(STAKER_1),
            snapshot.initialStakerBalance,
            "Staker should have more PROVE than initially"
        );

        // Verify staker is no longer staked
        assertEq(
            SuccinctStaking(STAKING).stakedTo(STAKER_1),
            address(0),
            "Staker should no longer be staked to any prover"
        );
        assertEq(
            SuccinctStaking(STAKING).staked(STAKER_1), 0, "Staker should have no stake remaining"
        );

        // Calculate and verify the profit
        uint256 finalBalance = IERC20(PROVE).balanceOf(STAKER_1);
        uint256 profit = finalBalance - snapshot.initialStakerBalance - STAKER_PROVE_AMOUNT;

        // The profit should be the staker portion of the reward
        // Since STAKER_1 is the only staker to ALICE_PROVER, they should get the full staker reward
        assertApproxEqAbs(
            profit,
            expectedStakerReward,
            1e6,
            "Staker should receive the staker portion of the reward"
        );
    }

    function test_GasReward() public {
        // Prepare reward action for ALICE_PROVER
        uint256 rewardAmount = 5e18;
        bytes memory rewardData =
            abi.encode(RewardAction({prover: ALICE_PROVER, amount: rewardAmount}));

        PublicValuesStruct memory publicValues = PublicValuesStruct({
            actions: new Action[](1),
            oldRoot: SuccinctVApp(VAPP).root(),
            newRoot: bytes32(uint256(0xbeef)),
            timestamp: uint64(block.timestamp)
        });
        publicValues.actions[0] = Action({
            action: ActionType.Reward,
            status: ReceiptStatus.Completed,
            receipt: 1, // Receipt ID for the reward action
            data: rewardData
        });

        // Execute the state update with reward
        SuccinctVApp(VAPP).updateState(abi.encode(publicValues), jsonFixture.proof);
    }

    function test_GasReward_WhenTwoRewards() public {
        // Prepare reward action for ALICE_PROVER
        uint256 rewardAmount = 5e18;
        bytes memory rewardData =
            abi.encode(RewardAction({prover: ALICE_PROVER, amount: rewardAmount}));

        PublicValuesStruct memory publicValues = PublicValuesStruct({
            actions: new Action[](2),
            oldRoot: SuccinctVApp(VAPP).root(),
            newRoot: bytes32(uint256(0xbeef)),
            timestamp: uint64(block.timestamp)
        });
        publicValues.actions[0] = Action({
            action: ActionType.Reward,
            status: ReceiptStatus.Completed,
            receipt: 1, // Receipt ID for the reward action
            data: rewardData
        });
        publicValues.actions[1] = Action({
            action: ActionType.Reward,
            status: ReceiptStatus.Completed,
            receipt: 2, // Receipt ID for the reward action
            data: rewardData
        });

        // Execute the state update with reward
        SuccinctVApp(VAPP).updateState(abi.encode(publicValues), jsonFixture.proof);
    }
}
