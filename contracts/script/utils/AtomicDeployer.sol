// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SuccinctStaking} from "../../src/SuccinctStaking.sol";
import {SuccinctVApp} from "../../src/SuccinctVApp.sol";
import {IntermediateSuccinct} from "../../src/tokens/IntermediateSuccinct.sol";
import {ERC1967Proxy} from
    "../../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

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

    // VApp params
    address public vappImpl;
    address public owner;
    address public auctioneer;
    address public verifier;
    uint256 public minDepositAmount;
    bytes32 public vkey;

    // Staking params
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

    function deploy(bytes32 salt, bytes calldata iproveCode, bytes calldata governorCode)
        external
        onlyOwner
        returns (address, address, address, address)
    {
        address STAKING;
        {
            STAKING = address(new ERC1967Proxy{salt: salt}(stakingImpl, ""));
        }

        address I_PROVE;
        {
            // I_PROVE = address(new IntermediateSuccinct{salt: salt}(prove, STAKING));
            bytes memory args = abi.encode(prove, STAKING);
            bytes memory initCode = abi.encodePacked(iproveCode, args);

            assembly {
                I_PROVE := create2(0, add(initCode, 0x20), mload(initCode), salt)
                if iszero(extcodesize(I_PROVE)) { revert(0, 0) }
            }
        }

        address GOVERNOR;
        {
            bytes memory args =
                abi.encode(I_PROVE, votingDelay, votingPeriod, proposalThreshold, quorumFraction);
            bytes memory initCode = abi.encodePacked(governorCode, args);

            assembly {
                GOVERNOR := create2(0, add(initCode, 0x20), mload(initCode), salt)
                if iszero(extcodesize(GOVERNOR)) { revert(0, 0) }
            }
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
            VAPP = address(new ERC1967Proxy{salt: salt}(vappImpl, vappInitData));
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
