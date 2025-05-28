// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SuccinctProver} from "../tokens/SuccinctProver.sol";
import {Create2} from "../../lib/openzeppelin-contracts/contracts/utils/Create2.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {IProver} from "../interfaces/IProver.sol";
import {IProverRegistry} from "../interfaces/IProverRegistry.sol";

/// @title ProverRegistry
/// @author Succinct Labs
/// @notice This contract is used to manage provers.
/// @dev Because provers are approved to spend $iPROVE, it is important that tracked
///      provers are only contracts with `type(SuccinctProver).creationCode`.
abstract contract ProverRegistry is IProverRegistry {
    /// @inheritdoc IProverRegistry
    address public override vapp;

    /// @inheritdoc IProverRegistry
    address public override prove;

    /// @inheritdoc IProverRegistry
    address public override iProve;

    /// @inheritdoc IProverRegistry
    uint256 public override proverCount;

    mapping(address => address) internal ownerToProver;
    mapping(address => bool) internal provers;

    /// @dev This call must target a prover that exists in the registry.
    modifier onlyForProver(address _prover) {
        if (!provers[_prover]) {
            revert ProverNotFound();
        }
        _;
    }

    function __ProverRegistry_init(address _vapp, address _prove, address _iProve) internal {
        vapp = _vapp;
        prove = _prove;
        iProve = _iProve;
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
    function createProver(uint256 _stakerFeeBips) external override returns (address) {
        if (hasProver(msg.sender)) {
            revert ProverAlreadyExists();
        }

        return _deployProver(_stakerFeeBips);
    }

    /// @dev Uses CREATE2 to deploy an instance of SuccinctProver and adds it to the mapping.
    function _deployProver(uint256 _stakerFeeBips) internal returns (address) {
        // Ensure that the contract is initialized.
        if (iProve == address(0)) {
            revert NotInitialized();
        }

        // Increment the number of provers.
        unchecked {
            ++proverCount;
        }

        // Deploy the prover.
        address prover = Create2.deploy(
            0,
            bytes32(uint256(uint160(msg.sender))),
            abi.encodePacked(
                type(SuccinctProver).creationCode,
                abi.encode(iProve, address(this), msg.sender, proverCount, _stakerFeeBips)
            )
        );

        // Update the mappings.
        ownerToProver[msg.sender] = prover;
        provers[prover] = true;

        // Approve the prover to transfer $iPROVE to $PROVER-N during stake().
        IERC20(iProve).approve(prover, type(uint256).max);

        emit ProverDeploy(prover, msg.sender);

        return prover;
    }
}
