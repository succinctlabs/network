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

struct AtomicDeployerParams {
    // Staking proxy param
    address stakingImpl;

    // IntermediateSuccinct param
    address prove;

    // Governor params
    uint48 votingDelay;
    uint32 votingPeriod;
    uint256 proposalThreshold;
    uint256 quorumFraction;

    address vappImpl;
    address owner;
    address auctioneer;
    address verifier;
    uint256 minDepositAmount;
    bytes32 vkey;
    bytes32 genesisStateRoot;
    address dispenser;
    uint256 minStakeAmount;
    uint256 maxUnstakeRequests;
    uint256 unstakePeriod;
    uint256 slashCancellationPeriod;
    bytes32 salt;
}

contract AtomicDeployer {
     // Staking proxy param
    address public stakingImpl;

    // IntermediateSuccinct param
    address public prove;

    // Governor params
    uint48 public votingDelay;
    uint32 public votingPeriod;
    uint256 public proposalThreshold;
    uint256 public quorumFraction;

    address public vappImpl;
    address public owner;
    address public auctioneer;
    address public verifier;
    uint256 public minDepositAmount;
    bytes32 public vkey;
    address public dispenser;
    uint256 public minStakeAmount;
    uint256 public maxUnstakeRequests;
    uint256 public unstakePeriod;
    uint256 public slashCancellationPeriod;
    bytes32 public genesisStateRoot;

    address public deployerOwner;

    constructor() {
        deployerOwner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == deployerOwner);
        _;
    }

    function setParams1(
        address _stakingImpl,
        address _prove,
        uint48 _votingDelay,
        uint32 _votingPeriod,
        uint256 _proposalThreshold,
        uint256 _quorumFraction
    ) external onlyOwner {
        stakingImpl = _stakingImpl;
        prove = _prove;
        votingDelay = _votingDelay;
        votingPeriod = _votingPeriod;
        proposalThreshold = _proposalThreshold;
        quorumFraction = _quorumFraction;
    }

    function setParams2(
        address _vappImpl,
        address _owner,
        address _auctioneer,
        address _verifier,
        uint256 _minDepositAmount,
        bytes32 _vkey
    ) external onlyOwner {
        vappImpl = _vappImpl;
        owner = _owner;
        auctioneer = _auctioneer;
        verifier = _verifier;
        minDepositAmount = _minDepositAmount;
        vkey = _vkey;
    }

    function setParams3(
        address _dispenser,
        uint256 _minStakeAmount,
        uint256 _maxUnstakeRequests,
        uint256 _unstakePeriod,
        uint256 _slashCancellationPeriod,
        bytes32 _genesisStateRoot
    ) external onlyOwner {
        dispenser = _dispenser;
        minStakeAmount = _minStakeAmount;
        maxUnstakeRequests = _maxUnstakeRequests;
        unstakePeriod = _unstakePeriod;
        slashCancellationPeriod = _slashCancellationPeriod;
        genesisStateRoot = _genesisStateRoot;
    }

    function deploy(bytes32 salt) external onlyOwner returns (address, address, address, address) {
        address STAKING;
        {
            STAKING = address(
                SuccinctStaking(payable(address(new ERC1967Proxy{salt: salt}(stakingImpl, ""))))
            );
        }

        address I_PROVE;
        {
            I_PROVE = address(new IntermediateSuccinct{salt: salt}(prove, STAKING));
        }

        address GOVERNOR;
        {
            GOVERNOR = address(new SuccinctGovernor{salt: salt}(
                I_PROVE, votingDelay, votingPeriod, proposalThreshold, quorumFraction
            ));
        }

        address VAPP;
        {
            // Encode the initialize function call data
            bytes memory vappInitData;
            {
                vappInitData = abi.encodeCall(
                SuccinctVApp.initialize,
                (
                    owner,
                    prove,
                    I_PROVE,
                    auctioneer,
                    STAKING,
                    verifier,
                    minDepositAmount,
                    vkey,
                    genesisStateRoot
                )
            );
            }
            VAPP = address(
                SuccinctVApp(payable(address(new ERC1967Proxy{salt: salt}(vappImpl, vappInitData))))
            );
        }

        SuccinctStaking(STAKING).initialize(
            owner,
            GOVERNOR,
            VAPP,
            prove,
            I_PROVE,
            dispenser,
            minStakeAmount,
            maxUnstakeRequests,
            unstakePeriod,
            slashCancellationPeriod
        );

        return (STAKING, VAPP, I_PROVE, GOVERNOR);
    }
}

// Deploy all contracts.
contract AllAtomicScript is BaseScript, FixtureLoader {
    function run() external broadcaster {
        // Read config
        bytes32 salt = readBytes32("CREATE2_SALT");
        address OWNER = readAddress("OWNER");

        address STAKING_IMPL = address(new SuccinctStaking{salt: salt}());

        // Deploy contracts
        address PROVE = address(new Succinct{salt: salt}(OWNER));
        (address VERIFIER, address VAPP_IMPL) =
            _deployVAppImpl(salt, OWNER);

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
                    VAPP_IMPL,
                    OWNER,
                    AUCTIONEER,
                    VERIFIER,
                    MIN_DEPOSIT_AMOUNT,
                    VKEY
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
            (address STAKING, address VAPP, address I_PROVE, address GOVERNOR) = deployer.deploy(salt);
            writeAddress("STAKING", STAKING);
            writeAddress("VAPP", VAPP);
            writeAddress("I_PROVE", I_PROVE);
            writeAddress("GOVERNOR", GOVERNOR);
        }

        // Write addresses
        writeAddress("STAKING_IMPL", STAKING_IMPL);
        writeAddress("VERIFIER", VERIFIER);
        writeAddress("VAPP_IMPL", VAPP_IMPL);
        writeAddress("PROVE", PROVE);
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
    function _deployVAppImpl(
        bytes32 salt,
        address OWNER
    ) internal returns (address, address) {
        // Read config
        address VERIFIER = readAddress("VERIFIER");

        // If the verifier is not provided, deploy the SP1VerifierGateway and add v5.0.0 Groth16 SP1Verifier to it
        if (VERIFIER == address(0)) {
            VERIFIER = address(new SP1VerifierGateway{salt: salt}(OWNER));
            address groth16 = address(new SP1Verifier{salt: salt}());
            SP1VerifierGateway(VERIFIER).addRoute(groth16);
        }

        // Deploy contract
        address VAPP_IMPL = address(new SuccinctVApp{salt: salt}());

        return (VERIFIER, VAPP_IMPL);
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
