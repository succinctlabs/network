// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "../lib/forge-std/src/Test.sol";
import {Succinct} from "../src/tokens/Succinct.sol";
import {SuccinctStaking} from "../src/SuccinctStaking.sol";
import {IntermediateSuccinct} from "../src/tokens/IntermediateSuccinct.sol";
import {IProver} from "../src/interfaces/IProver.sol";
import {IIntermediateSuccinct} from "../src/interfaces/IIntermediateSuccinct.sol";
import {MockVApp, FeeCalculator} from "../src/mocks/MockVApp.sol";
import {SuccinctGovernor} from "../src/SuccinctGovernor.sol";
import {ERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {IERC20Permit} from
    "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {IERC4626} from "../lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {ERC1967Proxy} from "../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Sets up the SuccinctStaking protocol for testing and exposes some useful helper functions.
contract SuccinctStakingTest is Test {
    // Constants
    uint256 public constant SCALAR = 1e27;
    uint256 public constant MIN_PROVER_PRICE_PER_SHARE = 1e9;
    uint256 public constant MIN_STAKE_AMOUNT = 1e16;
    uint256 public constant STAKER_PROVE_AMOUNT = 1000000e18; // >= PROPOSAL_THRESHOLD for governance tests
    uint256 public constant REQUESTER_PROVE_AMOUNT = 1_000_000e18;
    uint256 public constant DISPENSE_AMOUNT = 10_000_000e18;
    uint256 public constant DISPENSE_RATE = 63419583967529173; // 0.063 PROVE/s (20% APY assuming 10M staked)
    uint256 public constant MAX_UNSTAKE_REQUESTS = 10;
    uint256 public constant UNSTAKE_PERIOD = 21 days;
    uint256 public constant SLASH_CANCELLATION_PERIOD = 7 days;
    uint256 public constant STAKER_FEE_BIPS = 1000; // 10%
    uint256 public constant FEE_UNIT = 10000; // 100%
    uint256 public constant PROTOCOL_FEE_BIPS = 30; // 0.3%
    uint48 public constant VOTING_DELAY = 7200;
    uint32 public constant VOTING_PERIOD = 100800;
    uint256 public constant PROPOSAL_THRESHOLD = 1000000e18;
    uint256 public constant QUORUM_FRACTION = 20;

    // EOAs
    address public OWNER;
    address public DISPENSER;
    address public REQUESTER;
    address public STAKER_1;
    uint256 public STAKER_1_PK;
    address public STAKER_2;
    uint256 public STAKER_2_PK;
    address public ALICE;
    address public BOB;

    // Contracts
    address public TREASURY;
    address public STAKING;
    address public VAPP;
    address public PROVE;
    address public I_PROVE;
    address public GOVERNOR;
    address public ALICE_PROVER;
    address public BOB_PROVER;

    function setUp() public virtual {
        // Create the owner
        OWNER = makeAddr("OWNER");

        // Create the dispenser
        DISPENSER = makeAddr("DISPENSER");

        // Create the requester
        REQUESTER = makeAddr("REQUESTER");

        // Create the staker
        (STAKER_1, STAKER_1_PK) = makeAddrAndKey("STAKER_1");
        (STAKER_2, STAKER_2_PK) = makeAddrAndKey("STAKER_2");

        // Create the provers
        ALICE = makeAddr("ALICE");
        BOB = makeAddr("BOB");

        // Deploy fee vault (just an EOA for testing)
        TREASURY = makeAddr("TREASURY");

        // Deploy Succinct Staking
        address STAKING_IMPL = address(new SuccinctStaking());
        STAKING = address(new ERC1967Proxy(STAKING_IMPL, ""));

        // Deploy PROVE
        PROVE = address(new Succinct(OWNER));

        // Deploy I_PROVE
        I_PROVE = address(new IntermediateSuccinct(PROVE, STAKING));

        // Deploy VAPP
        VAPP = address(new MockVApp(STAKING, PROVE, I_PROVE, TREASURY, PROTOCOL_FEE_BIPS));

        // Deploy SuccinctGovernor with iPROVE as the voting token
        GOVERNOR = address(
            new SuccinctGovernor(
                I_PROVE, VOTING_DELAY, VOTING_PERIOD, PROPOSAL_THRESHOLD, QUORUM_FRACTION
            )
        );

        // Initialize Succinct Staking
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

        // Update the dispense rate
        vm.prank(OWNER);
        SuccinctStaking(STAKING).updateDispenseRate(DISPENSE_RATE);

        // Mint some $PROVE for the staking contract
        deal(PROVE, STAKING, DISPENSE_AMOUNT);

        // Mint some $PROVE for the requester
        deal(PROVE, REQUESTER, REQUESTER_PROVE_AMOUNT);

        // Deposit the $PROVE into the vApp
        vm.prank(REQUESTER);
        IERC20(PROVE).approve(VAPP, REQUESTER_PROVE_AMOUNT);
        vm.prank(REQUESTER);
        MockVApp(VAPP).deposit(REQUESTER_PROVE_AMOUNT);

        // Create the provers
        vm.prank(ALICE);
        ALICE_PROVER = SuccinctStaking(STAKING).createProver(STAKER_FEE_BIPS);
        vm.prank(BOB);
        BOB_PROVER = SuccinctStaking(STAKING).createProver(STAKER_FEE_BIPS);

        // Mint some $PROVE for the stakers
        deal(PROVE, STAKER_1, STAKER_PROVE_AMOUNT);
        deal(PROVE, STAKER_2, STAKER_PROVE_AMOUNT);
    }

    function _stake(address _staker, address _prover, uint256 _amount) internal returns (uint256) {
        vm.prank(_staker);
        IERC20(PROVE).approve(STAKING, _amount);
        vm.prank(_staker);
        return SuccinctStaking(STAKING).stake(_prover, _amount);
    }

    function _permitAndStake(address _staker, uint256 _stakerPK, address _prover, uint256 _amount)
        internal
        returns (uint256)
    {
        return _permitAndStake(_staker, _stakerPK, _prover, _amount, block.timestamp + 1 days);
    }

    function _permitAndStake(
        address _staker,
        uint256 _stakerPK,
        address _prover,
        uint256 _amount,
        uint256 _deadline
    ) internal returns (uint256) {
        (uint8 v, bytes32 r, bytes32 s) =
            _signPermit(_stakerPK, _staker, _prover, _amount, _deadline);
        return
            SuccinctStaking(STAKING).permitAndStake(_prover, _staker, _amount, _deadline, v, r, s);
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
        return SuccinctStaking(STAKING).finishUnstake(_staker);
    }

    function _completeSlash(address _prover, uint256 _amount) internal returns (uint256) {
        uint256 index = _requestSlash(_prover, _amount);
        return _finishSlash(_prover, index);
    }

    function _requestSlash(address _prover, uint256 _amount) internal returns (uint256) {
        return MockVApp(VAPP).processSlash(_prover, _amount);
    }

    function _finishSlash(address _prover, uint256 _index) internal returns (uint256) {
        vm.prank(OWNER);
        return SuccinctStaking(STAKING).finishSlash(_prover, _index);
    }

    function _dispense(uint256 _amount) internal {
        _waitRequiredDispenseTime(_amount);
        vm.prank(DISPENSER);
        SuccinctStaking(STAKING).dispense(_amount);
    }

    function _waitRequiredDispenseTime(uint256 _amount) internal {
        // Calculate time needed, ensuring at least 1 second for small amounts
        uint256 timeNeeded = (_amount + DISPENSE_RATE - 1) / DISPENSE_RATE;
        skip(timeNeeded);
    }

    function _signPermit(
        uint256 _pk,
        address _owner,
        address _prover,
        uint256 _amount,
        uint256 _deadline
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 PERMIT_TYPEHASH = keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );

        // Get the current nonce for the owner
        uint256 nonce = IERC20Permit(PROVE).nonces(_owner);

        // Construct the permit digest
        bytes32 structHash =
            keccak256(abi.encode(PERMIT_TYPEHASH, _owner, _prover, _amount, nonce, _deadline));
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", IERC20Permit(PROVE).DOMAIN_SEPARATOR(), structHash)
        );

        // Sign the digest
        return vm.sign(_pk, digest);
    }

    function _withdrawFromVApp(address _account, uint256 _amount) internal {
        MockVApp(VAPP).requestWithdraw(_account, _amount);
        MockVApp(VAPP).finishWithdraw(_account);
    }

    function _withdrawFullBalanceFromVApp(address _account) internal returns (uint256) {
        uint256 balance = MockVApp(VAPP).balances(_account);
        if (balance > 0) {
            MockVApp(VAPP).requestWithdraw(_account, balance);
            MockVApp(VAPP).finishWithdraw(_account);
        }
        return balance;
    }

    function _calculateStakerReward(uint256 _totalReward) internal pure returns (uint256) {
        (, uint256 stakerReward,) =
            FeeCalculator.calculateFeeSplit(_totalReward, PROTOCOL_FEE_BIPS, STAKER_FEE_BIPS);
        return stakerReward;
    }

    function _calculateOwnerReward(uint256 _totalReward) internal pure returns (uint256) {
        (,, uint256 ownerReward) =
            FeeCalculator.calculateFeeSplit(_totalReward, PROTOCOL_FEE_BIPS, STAKER_FEE_BIPS);
        return ownerReward;
    }

    function _calculateProtocolFee(uint256 _totalReward) internal pure returns (uint256) {
        (uint256 protocolFee,,) =
            FeeCalculator.calculateFeeSplit(_totalReward, PROTOCOL_FEE_BIPS, STAKER_FEE_BIPS);
        return protocolFee;
    }

    function _calculateRewardSplit(uint256 _totalReward)
        internal
        pure
        returns (uint256 stakerReward, uint256 ownerReward)
    {
        (, stakerReward, ownerReward) =
            FeeCalculator.calculateFeeSplit(_totalReward, PROTOCOL_FEE_BIPS, STAKER_FEE_BIPS);
    }

    function _calculateFullRewardSplit(uint256 _totalReward)
        internal
        pure
        returns (uint256 protocolFee, uint256 stakerReward, uint256 ownerReward)
    {
        (protocolFee, stakerReward, ownerReward) =
            FeeCalculator.calculateFeeSplit(_totalReward, PROTOCOL_FEE_BIPS, STAKER_FEE_BIPS);
    }

    /// @dev Get price-per-share for a prover. Returns assets per 1e18 shares.
    function _getProverPricePerShare(address _prover) internal view returns (uint256) {
        uint256 totalSupply = IERC20(_prover).totalSupply();
        if (totalSupply == 0) return 0;
        return IERC4626(_prover).previewRedeem(1e18);
    }
}

contract SuccinctStakingSetupTests is SuccinctStakingTest {
    function test_SetUp() public view {
        // Immutable variables
        assertEq(SuccinctStaking(STAKING).vapp(), VAPP);
        assertEq(SuccinctStaking(STAKING).prove(), PROVE);
        assertEq(SuccinctStaking(STAKING).iProve(), I_PROVE);
        assertEq(SuccinctStaking(STAKING).unstakePeriod(), UNSTAKE_PERIOD);
        assertEq(SuccinctStaking(STAKING).slashCancellationPeriod(), SLASH_CANCELLATION_PERIOD);
        assertEq(SuccinctStaking(STAKING).dispenseRate(), DISPENSE_RATE);
        assertEq(SuccinctStaking(STAKING).dispenseEarned(), 0);
        assertEq(SuccinctStaking(STAKING).dispenseDistributed(), 0);
        assertEq(SuccinctStaking(STAKING).dispenseRateTimestamp(), block.timestamp);
        assertEq(MockVApp(VAPP).staking(), STAKING);
        assertEq(MockVApp(VAPP).prove(), PROVE);
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
        assertEq(SuccinctStaking(STAKING).isProver(ALICE_PROVER), true);
        assertEq(SuccinctStaking(STAKING).isProver(BOB_PROVER), true);
        assertEq(SuccinctStaking(STAKING).isDeactivatedProver(ALICE_PROVER), false);
        assertEq(SuccinctStaking(STAKING).isDeactivatedProver(BOB_PROVER), false);
        assertEq(SuccinctStaking(STAKING).getProver(ALICE), ALICE_PROVER);
        assertEq(SuccinctStaking(STAKING).getProver(BOB), BOB_PROVER);
    }
}
