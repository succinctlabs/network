// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BaseScript} from "../utils/Base.s.sol";
import {SuccinctStaking} from "../../src/SuccinctStaking.sol";
import {SuccinctVApp} from "../../src/SuccinctVApp.sol";
import {IntermediateSuccinct} from "../../src/tokens/IntermediateSuccinct.sol";
import {SuccinctGovernor} from "../../src/SuccinctGovernor.sol";
import {Succinct} from "../../src/tokens/Succinct.sol";
import {FixtureLoader} from "../../test/utils/FixtureLoader.sol";
import {ERC1967Proxy} from
    "../../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {SP1VerifierGateway} from "../../lib/sp1-contracts/contracts/src/SP1VerifierGateway.sol";
import {SP1Verifier} from "../../lib/sp1-contracts/contracts/src/v5.0.0/SP1VerifierGroth16.sol";

// Deploy all contracts.
contract AllScript is BaseScript, FixtureLoader {
    function run() external broadcaster {
        // Read config
        bytes32 salt = readBytes32("CREATE2_SALT");
        address OWNER = readAddress("OWNER");
        address PROVE = readAddress("PROVE");

        // Deploy contracts
        (address STAKING, address STAKING_IMPL) = _deployStakingAsProxy(salt);
        address I_PROVE = address(new IntermediateSuccinct{salt: salt}(PROVE, STAKING));
        address GOVERNOR = _deployGovernor(salt, I_PROVE);
        (address VAPP, address VAPP_IMPL) = _deployVAppAsProxy(salt, OWNER, PROVE, I_PROVE, STAKING);

        // Initialize staking contract
        _initializeStaking(OWNER, STAKING, GOVERNOR, VAPP, PROVE, I_PROVE);

        // Write addresses
        writeAddress("STAKING", STAKING);
        writeAddress("STAKING_IMPL", STAKING_IMPL);
        writeAddress("VAPP", VAPP);
        writeAddress("VAPP_IMPL", VAPP_IMPL);
        writeAddress("I_PROVE", I_PROVE);
        writeAddress("GOVERNOR", GOVERNOR);
    }

    /// @dev This is a stack-too-deep workaround.
    function _deployGovernor(bytes32 salt, address I_PROVE) internal returns (address) {
        uint48 VOTING_DELAY = readUint48("VOTING_DELAY");
        uint32 VOTING_PERIOD = readUint32("VOTING_PERIOD");
        uint256 PROPOSAL_THRESHOLD = readUint256("PROPOSAL_THRESHOLD");
        uint256 QUORUM_FRACTION = readUint256("QUORUM_FRACTION");

        return address(
            new SuccinctGovernor{salt: salt}(
                I_PROVE, VOTING_DELAY, VOTING_PERIOD, PROPOSAL_THRESHOLD, QUORUM_FRACTION
            )
        );
    }

    /// @dev This is a stack-too-deep workaround.
    function _deployVAppAsProxy(
        bytes32 salt,
        address OWNER,
        address PROVE,
        address I_PROVE,
        address STAKING
    ) internal returns (address, address) {
        // Read config
        address AUCTIONEER = readAddress("AUCTIONEER");
        address VERIFIER = readAddress("VERIFIER");
        uint256 MIN_DEPOSIT_AMOUNT = readUint256("MIN_DEPOSIT_AMOUNT");
        bytes32 VKEY = readBytes32("VKEY");
        bytes32 GENESIS_STATE_ROOT = readBytes32("GENESIS_STATE_ROOT");

        // Encode the initialize function call data
        bytes memory initData = abi.encodeCall(
            SuccinctVApp.initialize,
            (
                OWNER,
                PROVE,
                I_PROVE,
                AUCTIONEER,
                STAKING,
                VERIFIER,
                MIN_DEPOSIT_AMOUNT,
                VKEY,
                GENESIS_STATE_ROOT
            )
        );

        // Deploy contract
        address VAPP_IMPL = address(new SuccinctVApp{salt: salt}());
        address VAPP = address(
            SuccinctVApp(payable(address(new ERC1967Proxy{salt: salt}(VAPP_IMPL, initData))))
        );

        return (VAPP, VAPP_IMPL);
    }

    /// @dev Deploys the staking contract as a proxy but does not initialize it.
    function _deployStakingAsProxy(bytes32 salt) internal returns (address, address) {
        address STAKING_IMPL = address(new SuccinctStaking{salt: salt}());
        address STAKING = address(
            SuccinctStaking(payable(address(new ERC1967Proxy{salt: salt}(STAKING_IMPL, ""))))
        );
        return (STAKING, STAKING_IMPL);
    }

    /// @dev This is a stack-too-deep workaround.
    function _initializeStaking(
        address OWNER,
        address STAKING,
        address GOVERNOR,
        address VAPP,
        address PROVE,
        address I_PROVE
    ) internal {
        address DISPENSER = readAddress("DISPENSER");
        uint256 MIN_STAKE_AMOUNT = readUint256("MIN_STAKE_AMOUNT");
        uint256 MAX_UNSTAKE_REQUESTS = readUint256("MAX_UNSTAKE_REQUESTS");
        uint256 UNSTAKE_PERIOD = readUint256("UNSTAKE_PERIOD");
        uint256 SLASH_CANCELLATION_PERIOD = readUint256("SLASH_CANCELLATION_PERIOD");

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
