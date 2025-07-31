// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.28;

import {BaseScript} from "../utils/Base.s.sol";

import {SuccinctVApp} from "../../src/SuccinctVApp.sol";
import {SuccinctStaking} from "../../src/SuccinctStaking.sol";
import {SuccinctGovernor} from "../../src/SuccinctGovernor.sol";
import {IIntermediateSuccinct} from "../../src/tokens/IntermediateSuccinct.sol";
import {IERC4626} from "../../lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

import "forge-std/Test.sol";

/// @notice Reverts if any deployment invariant is violated or the contracts are
///         not in the expected state after deployment.
contract PostDeploymentScript is BaseScript, Test {
    /// EIP‑1967 implementation slot: bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1)
    bytes32 private constant _IMPL_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    function run() external view {
        address VAPP = readAddress("VAPP");
        address VAPP_IMPL = readAddress("VAPP_IMPL");
        address STAKING = readAddress("STAKING");
        address PROVE = readAddress("PROVE");
        address I_PROVE = readAddress("I_PROVE");
        address GOVERNOR = readAddress("GOVERNOR");

        _checkVAppImpl(VAPP, VAPP_IMPL);
        _checkStaking(STAKING, VAPP, PROVE, I_PROVE);
        _checkVApp(VAPP, STAKING, PROVE);
        _checkIProve(I_PROVE, STAKING, PROVE);
        _checkGovernor(GOVERNOR);
    }

    function _checkVAppImpl(address _vapp, address _vappImpl) internal view {
        bytes32 implRaw = vm.load(_vapp, _IMPL_SLOT);
        address currentImpl = address(uint160(uint256(implRaw)));
        assertEq(
            currentImpl, _vappImpl, "vApp implementation address mismatch (may have been upgraded)"
        );
    }

    function _checkStaking(address _staking, address _vapp, address _prove, address _iProve)
        internal
        view
    {
        address OWNER = readAddress("OWNER");
        uint256 UNSTAKE_PERIOD = readUint256("UNSTAKE_PERIOD");
        uint256 SLASH_CANCELLATION_PERIOD = readUint256("SLASH_CANCELLATION_PERIOD");
        uint256 DISPENSE_RATE = readUint256("DISPENSE_RATE");

        SuccinctStaking staking = SuccinctStaking(_staking);
        assertEq(staking.owner(), OWNER);
        assertEq(staking.vapp(), _vapp);
        assertEq(staking.prove(), _prove);
        assertEq(staking.iProve(), _iProve);
        assertEq(staking.unstakePeriod(), UNSTAKE_PERIOD);
        assertEq(staking.slashCancellationPeriod(), SLASH_CANCELLATION_PERIOD);
        assertEq(staking.dispenseRate(), DISPENSE_RATE);
        assertEq(staking.dispenseEarned(), 0);
        assertEq(staking.dispenseDistributed(), 0);
        assertLe(
            staking.dispenseRateTimestamp(), block.timestamp, "dispenseRateTimestamp in future"
        );
    }

    function _checkVApp(address _vapp, address _staking, address _prove) internal view {
        address OWNER = readAddress("OWNER");
        uint256 MIN_DEPOSIT_AMOUNT = readUint256("MIN_DEPOSIT_AMOUNT");

        SuccinctVApp vapp = SuccinctVApp(payable(_vapp));
        assertEq(vapp.owner(), OWNER);
        assertEq(vapp.staking(), _staking);
        assertEq(vapp.prove(), _prove);
        assertEq(vapp.minDepositAmount(), MIN_DEPOSIT_AMOUNT);
    }

    function _checkIProve(address _iProve, address _staking, address _prove) internal view {
        assertEq(IIntermediateSuccinct(_iProve).staking(), _staking);
        assertEq(IERC4626(_iProve).asset(), _prove);
    }

    function _checkGovernor(address _governor) internal view {
        uint256 VOTING_DELAY = readUint256("VOTING_DELAY");
        uint256 VOTING_PERIOD = readUint256("VOTING_PERIOD");
        uint256 PROPOSAL_THRESHOLD = readUint256("PROPOSAL_THRESHOLD");
        uint256 QUORUM_FRACTION = readUint256("QUORUM_FRACTION");
        address I_PROVE = readAddress("I_PROVE");

        SuccinctGovernor governor = SuccinctGovernor(payable(_governor));
        assertEq(address(governor.token()), I_PROVE);
        assertEq(governor.votingDelay(), VOTING_DELAY);
        assertEq(governor.votingPeriod(), VOTING_PERIOD);
        assertEq(governor.proposalThreshold(), PROPOSAL_THRESHOLD);
        assertEq(governor.quorumNumerator(), QUORUM_FRACTION);
    }
}
