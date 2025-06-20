// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SuccinctProver} from "../tokens/SuccinctProver.sol";
import {Create2} from "../../lib/openzeppelin-contracts/contracts/utils/Create2.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {IProver} from "../interfaces/IProver.sol";
import {IProverRegistry} from "../interfaces/IProverRegistry.sol";
import {ISuccinctVApp} from "../interfaces/ISuccinctVApp.sol";

/// @title ProverRegistry
/// @author Succinct Labs
/// @notice This contract is used to manage provers.
/// @dev Because provers are approved to spend $iPROVE, it is important that tracked
///      provers are only contracts with `type(SuccinctProver).creationCode`.

abstract contract ProverRegistry is IProverRegistry {
    /// @inheritdoc IProverRegistry
    address public override governor;

    /// @inheritdoc IProverRegistry
    address public override vapp;

    /// @inheritdoc IProverRegistry
    address public override prove;

    /// @inheritdoc IProverRegistry
    address public override iProve;

    /// @inheritdoc IProverRegistry
    uint256 public override proverCount;

    /// @dev A mapping from prover owner to prover vault.
    mapping(address => address) internal ownerToProver;

    /// @dev A mapping from prover vault to whether it exists.
    mapping(address => bool) internal provers;

    /// @dev This call must be sent by the VApp contract. This also acts as a check to ensure that the contract
    ///      has been initialized.
    modifier onlyVApp() {
        if (msg.sender != vapp) {
            revert NotAuthorized();
        }
        _;
    }

    /// @dev This call must target a prover that exists in the registry.
    modifier onlyForProver(address _prover) {
        if (!provers[_prover]) {
            revert ProverNotFound();
        }
        _;
    }

    function __ProverRegistry_init(
        address _governor,
        address _vapp,
        address _prove,
        address _iProve
    ) internal {
        governor = _governor;
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
        if (_stakerFeeBips > 10000) {
            revert InvalidStakerFeeBips();
        }

        if (hasProver(msg.sender)) {
            revert ProverAlreadyExists();
        }

        return _deployProver(msg.sender, _stakerFeeBips);
    }

    /// @dev Uses CREATE2 to deploy an instance of SuccinctProver and adds it to the mapping.
    function _deployProver(address _owner, uint256 _stakerFeeBips)
        internal
        returns (address prover)
    {
        // Ensure that the contract is initialized.
        if (iProve == address(0)) {
            revert NotInitialized();
        }

        // Increment the number of provers.
        unchecked {
            ++proverCount;
        }

        // Deploy the prover.
        prover = Create2.deploy(
            0,
            bytes32(uint256(uint160(_owner))),
            abi.encodePacked(
                type(SuccinctProver).creationCode,
                abi.encode(governor, prove, iProve, _owner, proverCount, _stakerFeeBips)
            )
        );

        // Update the mappings.
        ownerToProver[_owner] = prover;
        provers[prover] = true;

        // Register the prover with the VApp.
        ISuccinctVApp(vapp).createProver(prover, _owner, _stakerFeeBips);

        // Approve the prover as a spender of $iPROVE, so that $iPROVE can be transferred to the
        // prover during stake().
        IERC20(iProve).approve(prover, type(uint256).max);

        emit ProverDeploy(prover, _owner, _stakerFeeBips);
    }
}
