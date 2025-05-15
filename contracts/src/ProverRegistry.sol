// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Create2} from "../lib/openzeppelin-contracts/contracts/utils/Create2.sol";
import {SuccinctProver} from "./tokens/SuccinctProver.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {IProver} from "./interfaces/IProver.sol";
import {IProverRegistry} from "./interfaces/IProverRegistry.sol";

/// @title ProverRegistry
/// @author Succinct Labs
/// @notice This contract is used to manage provers.
/// @dev Because provers are approved to spend $iPROVE, it is important that tracked
///      provers are only contracts with `type(SuccinctProver).creationCode`.
abstract contract ProverRegistry is IProverRegistry {
    address internal PROVE;
    address internal I_PROVE;

    uint256 internal numProvers;
    mapping(address => address) internal ownerToProver;
    mapping(address => bool) internal provers;

    /// @dev This call must target a prover that exists in the registry.
    modifier onlyForProver(address _prover) {
        if (!provers[_prover]) {
            revert ProverNotFound();
        }
        _;
    }

    function __ProverRegistry_init(address _prove, address _intermediateProve) internal {
        PROVE = _prove;
        I_PROVE = _intermediateProve;
    }

    /// @inheritdoc IProverRegistry
    function prove() external view override returns (address) {
        return PROVE;
    }

    /// @inheritdoc IProverRegistry
    function intermediateProve() external view override returns (address) {
        return I_PROVE;
    }

    /// @inheritdoc IProverRegistry
    function proverCount() public view override returns (uint256) {
        return numProvers;
    }

    /// @inheritdoc IProverRegistry
    function ownerOf(address _prover) public view override returns (address) {
        return IProver(_prover).owner();
    }

    /// @inheritdoc IProverRegistry
    function isProver(address _prover) public view override returns (bool) {
        return provers[_prover];
    }

    /// @inheritdoc IProverRegistry
    function getProver(address _owner) public view override returns (address) {
        return ownerToProver[_owner];
    }

    /// @inheritdoc IProverRegistry
    function hasProver(address _owner) public view override returns (bool) {
        return ownerToProver[_owner] != address(0);
    }

    /// @inheritdoc IProverRegistry
    function createProver() external override returns (address) {
        if (hasProver(msg.sender)) {
            revert ProverAlreadyExists();
        }

        return _deployProver();
    }

    /// @dev Uses CREATE2 to deploy an instance of SuccinctProver and adds it to the mapping.
    function _deployProver() internal returns (address) {
        // Ensure that the contract is initialized.
        if (I_PROVE == address(0)) {
            revert NotInitialized();
        }

        // Increment the number of provers.
        unchecked {
            ++numProvers;
        }

        // Deploy the prover.
        address prover = Create2.deploy(
            0,
            bytes32(uint256(uint160(msg.sender))),
            abi.encodePacked(
                type(SuccinctProver).creationCode,
                abi.encode(I_PROVE, address(this), numProvers, msg.sender)
            )
        );

        // Update the mappings.
        ownerToProver[msg.sender] = prover;
        provers[prover] = true;

        // Approve the prover to transfer $iPROVE to $PROVER-N during stake().
        IERC20(I_PROVE).approve(prover, type(uint256).max);

        emit ProverDeploy(prover, msg.sender);

        return prover;
    }
}
