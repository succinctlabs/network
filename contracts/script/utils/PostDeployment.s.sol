// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.28;

import {BaseScript} from "../utils/Base.s.sol";

import {SuccinctVApp} from "../../src/SuccinctVApp.sol";
import {SuccinctStaking} from "../../src/SuccinctStaking.sol";
import {SuccinctGovernor} from "../../src/SuccinctGovernor.sol";
import {IIntermediateSuccinct} from "../../src/tokens/IntermediateSuccinct.sol";
import {IERC4626} from "../../lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

/// @notice Reverts if any deployment invariant is violated or the contracts are
///         not in the expected state after deployment.
contract PostDeploymentScript is BaseScript {
    /// EIP‑1967 implementation slot: bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1)
    bytes32 private constant _IMPL_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    function run() external view {
        // Read addresses
        address OWNER = readAddress("OWNER");
        address VAPP = readAddress("VAPP");
        address VAPP_IMPL = readAddress("VAPP_IMPL");
        address STAKING = readAddress("STAKING");
        address PROVE = readAddress("PROVE");
        address I_PROVE = readAddress("I_PROVE");
        address GOVERNOR = readAddress("GOVERNOR");

        uint256 UNSTAKE_PERIOD = readUint256("UNSTAKE_PERIOD");
        uint256 SLASH_CANCELLATION_PERIOD = readUint256("SLASH_CANCELLATION_PERIOD");
        uint256 DISPENSE_RATE = readUint256("DISPENSE_RATE");
        uint256 MIN_DEPOSIT_AMOUNT = readUint256("MIN_DEPOSIT_AMOUNT");

        uint256 VOTING_DELAY = readUint256("VOTING_DELAY");
        uint256 VOTING_PERIOD = readUint256("VOTING_PERIOD");
        uint256 PROPOSAL_THRESHOLD = readUint256("PROPOSAL_THRESHOLD");
        uint256 QUORUM_FRACTION = readUint256("QUORUM_FRACTION");

        // Check that the vApp proxy points to the correct implementation
        bytes32 implRaw = vm.load(VAPP, _IMPL_SLOT);
        address currentImpl = address(uint160(uint256(implRaw)));
        require(
            currentImpl == VAPP_IMPL,
            "vApp implementation address mismatch (may have been upgraded)"
        );

        // Check that the SuccinctStaking contract is correctly initialized
        SuccinctStaking staking = SuccinctStaking(STAKING);
        require(staking.owner() == OWNER);
        require(staking.vapp() == VAPP);
        require(staking.prove() == PROVE);
        require(staking.iProve() == I_PROVE);
        require(staking.unstakePeriod() == UNSTAKE_PERIOD);
        require(staking.slashCancellationPeriod() == SLASH_CANCELLATION_PERIOD);
        require(staking.dispenseRate() == DISPENSE_RATE);
        require(staking.dispenseEarned() == 0);
        require(staking.dispenseDistributed() == 0);
        require(staking.dispenseRateTimestamp() <= block.timestamp);

        // Check that the SuccinctVApp contract is correctly initialized
        SuccinctVApp vapp = SuccinctVApp(payable(VAPP));
        require(vapp.owner() == OWNER);
        require(vapp.staking() == STAKING);
        require(vapp.prove() == PROVE);
        require(vapp.minDepositAmount() == MIN_DEPOSIT_AMOUNT);

        // Check that the $iPROVE contract is correctly initialized
        require(IIntermediateSuccinct(I_PROVE).staking() == STAKING);
        require(IERC4626(I_PROVE).asset() == PROVE);

        // Check that the SuccinctGovernor contract is correctly initialized
        SuccinctGovernor governor = SuccinctGovernor(payable(GOVERNOR));
        require(address(governor.token()) == I_PROVE);
        require(governor.votingDelay() == VOTING_DELAY);
        require(governor.votingPeriod() == VOTING_PERIOD);
        require(governor.proposalThreshold() == PROPOSAL_THRESHOLD);
        require(governor.quorum(0) == QUORUM_FRACTION);
        require(governor.clock() == 0);
    }
}
