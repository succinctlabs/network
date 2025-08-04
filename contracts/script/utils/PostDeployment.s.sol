// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "../../lib/forge-std/src/Test.sol";
import {BaseScript} from "../utils/Base.s.sol";
import {SuccinctVApp} from "../../src/SuccinctVApp.sol";
import {SuccinctStaking} from "../../src/SuccinctStaking.sol";
import {SuccinctGovernor} from "../../src/SuccinctGovernor.sol";
import {IIntermediateSuccinct} from "../../src/tokens/IntermediateSuccinct.sol";
import {IERC4626} from "../../lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/// @notice Reverts if any deployment invariant is violated or the contracts are not in the
///         expected state after deployment.
contract PostDeploymentScript is BaseScript, Test {
    /// EIP‑1967 implementation slot: bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1)
    bytes32 private constant _IMPL_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    function run() external view {
        address VAPP = readAddress("VAPP");
        address VAPP_IMPL = readAddress("VAPP_IMPL");
        address STAKING = readAddress("STAKING");
        address STAKING_IMPL = readAddress("STAKING_IMPL");
        address PROVE = readAddress("PROVE");
        address I_PROVE = readAddress("I_PROVE");
        address GOVERNOR = readAddress("GOVERNOR");

        _checkVAppImpl(VAPP, VAPP_IMPL);
        _checkVApp(VAPP, STAKING, PROVE, I_PROVE);
        _checkStakingImpl(STAKING, STAKING_IMPL);
        _checkStaking(STAKING, VAPP, PROVE, I_PROVE);
        _checkGovernor(GOVERNOR, I_PROVE);
        _checkIProve(I_PROVE, STAKING, PROVE);
        _checkProve(PROVE, STAKING, VAPP, I_PROVE);
    }

    function _checkVAppImpl(address _vapp, address _vappImpl) internal view {
        bytes32 implRaw = vm.load(_vapp, _IMPL_SLOT);
        address currentImpl = address(uint160(uint256(implRaw)));
        assertEq(
            currentImpl, _vappImpl, "vApp implementation address mismatch (may have been upgraded)"
        );
    }

    function _checkVApp(address _vapp, address _staking, address _prove, address _iProve)
        internal
        view
    {
        address OWNER = readAddress("OWNER");
        address AUCTIONEER = readAddress("AUCTIONEER");
        address VERIFIER = readAddress("VERIFIER");
        uint256 MIN_DEPOSIT = readUint256("MIN_DEPOSIT_AMOUNT");
        bytes32 VKEY = readBytes32("VKEY");
        bytes32 GENESIS = readBytes32("GENESIS_STATE_ROOT");

        SuccinctVApp vapp = SuccinctVApp(payable(_vapp));

        assertEq(vapp.owner(), OWNER);
        assertEq(vapp.vkey(), VKEY);
        assertEq(vapp.prove(), _prove);
        assertEq(vapp.iProve(), _iProve);
        assertEq(vapp.auctioneer(), AUCTIONEER);
        assertEq(vapp.staking(), _staking);
        assertEq(vapp.verifier(), VERIFIER);
        assertEq(vapp.minDepositAmount(), MIN_DEPOSIT);
        assertEq(vapp.blockNumber(), 0);
        assertEq(vapp.currentOnchainTxId(), 0);
        assertEq(vapp.finalizedOnchainTxId(), 0);
        assertEq(vapp.root(), GENESIS);
        assertEq(vapp.timestamp(), 0);
    }

    function _checkStakingImpl(address _staking, address _stakingImpl) internal view {
        bytes32 implRaw = vm.load(_staking, _IMPL_SLOT);
        address currentImpl = address(uint160(uint256(implRaw)));
        assertEq(
            currentImpl,
            _stakingImpl,
            "staking implementation address mismatch (may have been upgraded)"
        );
    }

    function _checkStaking(address _staking, address _vapp, address _prove, address _iProve)
        internal
        view
    {
        address OWNER = readAddress("OWNER");
        address DISPENSER = readAddress("DISPENSER");
        uint256 MIN_STAKE_AMOUNT = readUint256("MIN_STAKE_AMOUNT");
        uint256 MAX_UNSTAKE_REQUESTS = readUint256("MAX_UNSTAKE_REQUESTS");
        uint256 UNSTAKE_PERIOD = readUint256("UNSTAKE_PERIOD");
        uint256 SLASH_CANCELLATION = readUint256("SLASH_CANCELLATION_PERIOD");
        // uint256 DISPENSE_RATE = readUint256("DISPENSE_RATE");

        SuccinctStaking staking = SuccinctStaking(_staking);

        assertEq(staking.owner(), OWNER);
        assertEq(staking.vapp(), _vapp);
        assertEq(staking.prove(), _prove);
        assertEq(staking.iProve(), _iProve);
        assertEq(staking.dispenser(), DISPENSER);
        assertEq(staking.minStakeAmount(), MIN_STAKE_AMOUNT);
        assertEq(staking.maxUnstakeRequests(), MAX_UNSTAKE_REQUESTS);
        assertEq(staking.unstakePeriod(), UNSTAKE_PERIOD);
        assertEq(staking.slashCancellationPeriod(), SLASH_CANCELLATION);
        // assertEq(staking.dispenseRate(), DISPENSE_RATE);
        assertEq(staking.dispenseEarned(), 0);
        assertEq(staking.dispenseDistributed(), 0);
        assertLe(staking.dispenseRateTimestamp(), block.timestamp);
        assertEq(staking.proverCount(), 0);
        assertEq(staking.totalSupply(), 0);
    }

    function _checkGovernor(address _governor, address _iProve) internal view {
        uint256 VOTE_DELAY = readUint256("VOTING_DELAY");
        uint256 VOTE_PERIOD = readUint256("VOTING_PERIOD");
        uint256 PROP_THRESH = readUint256("PROPOSAL_THRESHOLD");
        uint256 QUORUM = readUint256("QUORUM_FRACTION");

        SuccinctGovernor governor = SuccinctGovernor(payable(_governor));
        assertEq(address(governor.token()), _iProve);
        assertEq(governor.votingDelay(), VOTE_DELAY);
        assertEq(governor.votingPeriod(), VOTE_PERIOD);
        assertEq(governor.proposalThreshold(), PROP_THRESH);
        assertEq(governor.quorumNumerator(), QUORUM);
        assertGt(governor.clock(), 0);
        assertEq(governor.CLOCK_MODE(), "mode=timestamp");
    }

    function _checkIProve(address _iProve, address _staking, address _prove) internal view {
        assertEq(IIntermediateSuccinct(_iProve).staking(), _staking);
        assertEq(IERC4626(_iProve).asset(), _prove);
        assertEq(IERC20(_iProve).totalSupply(), 0);
    }

    function _checkProve(address _prove, address _staking, address _vapp, address _iProve)
        internal
        view
    {
        assertEq(IERC20(_prove).allowance(_staking, _iProve), type(uint256).max);
        assertEq(IERC20(_prove).allowance(_vapp, _iProve), type(uint256).max);
    }
}
