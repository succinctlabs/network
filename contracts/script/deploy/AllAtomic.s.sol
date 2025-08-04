// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BaseScript} from "../utils/Base.s.sol";
import {SuccinctStaking} from "../../src/SuccinctStaking.sol";
import {SuccinctVApp} from "../../src/SuccinctVApp.sol";
import {IntermediateSuccinct} from "../../src/tokens/IntermediateSuccinct.sol";
import {SuccinctGovernor} from "../../src/SuccinctGovernor.sol";
import {AtomicDeployer} from "../utils/AtomicDeployer.sol";
import {ERC1967Proxy} from
    "../../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Deploy all contracts.
contract AllAtomicScript is BaseScript {
    function run() external broadcaster {
        // Read config
        bytes32 salt = readBytes32("CREATE2_SALT");
        address OWNER = readAddress("OWNER");
        address PROVE = readAddress("PROVE");
        address VERIFIER = readAddress("VERIFIER");

        // Deploy implementation contracts
        address STAKING_IMPL = address(new SuccinctStaking{salt: salt}());
        address VAPP_IMPL = address(new SuccinctVApp{salt: salt}());

        // Atomically deploy the rest of the contracts
        {
            AtomicDeployer deployer = new AtomicDeployer();
            {
                uint48 VOTING_DELAY = readUint48("VOTING_DELAY");
                uint32 VOTING_PERIOD = readUint32("VOTING_PERIOD");
                uint256 PROPOSAL_THRESHOLD = readUint256("PROPOSAL_THRESHOLD");
                uint256 QUORUM_FRACTION = readUint256("QUORUM_FRACTION");
                deployer.setParams1(
                    STAKING_IMPL,
                    PROVE,
                    VOTING_DELAY,
                    VOTING_PERIOD,
                    PROPOSAL_THRESHOLD,
                    QUORUM_FRACTION
                );
            }
            {
                address AUCTIONEER = readAddress("AUCTIONEER");
                uint256 MIN_DEPOSIT_AMOUNT = readUint256("MIN_DEPOSIT_AMOUNT");
                bytes32 VKEY = readBytes32("VKEY");
                deployer.setParams2(
                    VAPP_IMPL, OWNER, AUCTIONEER, VERIFIER, MIN_DEPOSIT_AMOUNT, VKEY
                );
            }
            {
                address DISPENSER = readAddress("DISPENSER");
                uint256 MIN_STAKE_AMOUNT = readUint256("MIN_STAKE_AMOUNT");
                uint256 MAX_UNSTAKE_REQUESTS = readUint256("MAX_UNSTAKE_REQUESTS");
                uint256 UNSTAKE_PERIOD = readUint256("UNSTAKE_PERIOD");
                uint256 SLASH_CANCELLATION_PERIOD = readUint256("SLASH_CANCELLATION_PERIOD");
                bytes32 GENESIS_STATE_ROOT = readBytes32("GENESIS_STATE_ROOT");
                deployer.setParams3(
                    DISPENSER,
                    MIN_STAKE_AMOUNT,
                    MAX_UNSTAKE_REQUESTS,
                    UNSTAKE_PERIOD,
                    SLASH_CANCELLATION_PERIOD,
                    GENESIS_STATE_ROOT
                );
            }
            (address STAKING, address VAPP, address I_PROVE, address GOVERNOR) = deployer.deploy(
                salt, type(IntermediateSuccinct).creationCode, type(SuccinctGovernor).creationCode
            );
            writeAddress("STAKING", STAKING);
            writeAddress("VAPP", VAPP);
            writeAddress("I_PROVE", I_PROVE);
            writeAddress("GOVERNOR", GOVERNOR);
        }

        // Write addresses
        writeAddress("STAKING_IMPL", STAKING_IMPL);
        writeAddress("VAPP_IMPL", VAPP_IMPL);
    }
}
