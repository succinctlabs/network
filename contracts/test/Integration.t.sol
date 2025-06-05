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
import {SP1VerifierGateway} from "../lib/sp1-contracts/contracts/src/SP1VerifierGateway.sol";
import {SP1Verifier} from "../lib/sp1-contracts/contracts/src/v4.0.0-rc.3/SP1VerifierGroth16.sol";
import {ISP1Verifier} from "../lib/sp1-contracts/contracts/src/ISP1Verifier.sol";
import {
    PublicValuesStruct,
    TransactionStatus,
    Receipt as VAppReceipt,
    TransactionVariant,
    DepositTransaction,
    WithdrawTransaction,
    CreateProverTransaction
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
    uint256 public constant STAKER_FEE_BIPS = 1000; // 10%

    // Fixtures
    SP1ProofFixtureJson public jsonFixture;
    PublicValuesStruct public fixture;

    // EOAs
    address public OWNER;
    address public REQUESTER_1;
    uint256 public REQUESTER_1_PK;
    address public REQUESTER_2;
    uint256 public REQUESTER_2_PK;
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
        (REQUESTER_1, REQUESTER_1_PK) = makeAddrAndKey("REQUESTER_1");
        (REQUESTER_2, REQUESTER_2_PK) = makeAddrAndKey("REQUESTER_2");

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

        for (uint256 i = 0; i < _fixture.receipts.length; i++) {
            fixture.receipts.push(_fixture.receipts[i]);
        }

		bytes32 vkey = bytes32(0x002124aeceb145cb3e4d4b50f94571ab92fc27c165ccc4ac41d930bc86595088);
        bytes32 genesisStateRoot =
            bytes32(0xa11f4a6c98ad88ce1f707acc85018b1ee2ac1bc5e8dd912c8273400b7e535beb);
        uint64 genesisTimestamp = 0;

		// Deploy the SP1VerifierGatway
        VERIFIER = address(new SP1VerifierGateway(OWNER));
        address groth16 = address(new SP1Verifier());
        vm.prank(OWNER);
        SP1VerifierGateway(VERIFIER).addRoute(groth16);

        // Deploy Staking
        STAKING = address(new SuccinctStaking(OWNER));

        // Deploy PROVE
        PROVE = address(new Succinct(OWNER));

        // Deploy I_PROVE
        I_PROVE = address(new IntermediateSuccinct(PROVE, STAKING));

        // Deploy VApp
        address vappImpl = address(new SuccinctVApp());
        VAPP = address(new ERC1967Proxy(vappImpl, ""));

        // Initialize VApp
        SuccinctVApp(VAPP).initialize(
            OWNER,
            PROVE,
			I_PROVE,
            STAKING,
            VERIFIER,
            // jsonFixture.vkey,
			vkey,
            0,
            genesisStateRoot,
            genesisTimestamp
        );

        // Initialize Staking
        vm.prank(OWNER);
        SuccinctStaking(STAKING).initialize(
            VAPP, PROVE, I_PROVE, MIN_STAKE_AMOUNT, UNSTAKE_PERIOD, SLASH_PERIOD, DISPENSE_RATE
        );

        // Mint some $PROVE for the staking contract
        deal(PROVE, STAKING, STAKING_PROVE_AMOUNT);

        // Mint some $PROVE for the requester
        deal(PROVE, REQUESTER_1, REQUESTER_PROVE_AMOUNT);
        deal(PROVE, REQUESTER_2, REQUESTER_PROVE_AMOUNT);

        // Mint some $PROVE for the stakers
        deal(PROVE, STAKER_1, STAKER_PROVE_AMOUNT);
        deal(PROVE, STAKER_2, STAKER_PROVE_AMOUNT);

		// // Deposit the $PROVE into the vApp
        // vm.prank(REQUESTER_1);
        // IERC20(PROVE).approve(VAPP, REQUESTER_PROVE_AMOUNT);
        // vm.prank(REQUESTER_1);
        // SuccinctVApp(VAPP).deposit(REQUESTER_PROVE_AMOUNT);

		// // Create the provers
        // vm.prank(ALICE);
        // ALICE_PROVER = SuccinctStaking(STAKING).createProver(STAKER_FEE_BIPS);
        // vm.prank(BOB);
        // BOB_PROVER = SuccinctStaking(STAKING).createProver(STAKER_FEE_BIPS);
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
        assertEq(SuccinctStaking(STAKING).proverCount(), 0);
    }

    // In this scenario:
    // - STAKER_1 stakes to ALICE_PROVER, such that ALICE_PROVER is above the minimum stake amount
    //   to particpate in offchain auctions.
    // - The REQUESTER (already deposited $PROVE), had a proof fulfilled offchain from ALICE_PROVER.
    // - Therefor, the VApp update should transfer $PROVE from the VApp REQUESTER's balance to the
    //   ALICE_PROVER vault. When STAKER_1 unstakes, they should have more $PROVE then the amount
    //   they staked.
    function test_E2E() public {
		// Prover owners create the provers
        vm.prank(ALICE);
        ALICE_PROVER = SuccinctStaking(STAKING).createProver(STAKER_FEE_BIPS);
        vm.prank(BOB);
        BOB_PROVER = SuccinctStaking(STAKING).createProver(STAKER_FEE_BIPS);

		// Stakers stake to the provers
		_stake(STAKER_1, ALICE_PROVER, SuccinctStaking(STAKING).minStakeAmount());
		_stake(STAKER_2, BOB_PROVER, SuccinctStaking(STAKING).minStakeAmount());
		
		// Requesters deposit into the vApp
        vm.prank(REQUESTER_1);
        IERC20(PROVE).approve(VAPP, SuccinctVApp(VAPP).minDepositAmount());
        vm.prank(REQUESTER_1);
        SuccinctVApp(VAPP).deposit(SuccinctVApp(VAPP).minDepositAmount());


    }
}