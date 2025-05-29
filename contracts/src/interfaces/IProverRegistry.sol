// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IProverRegistry {
    /// @dev Emitted when a prover is deployed.
    event ProverDeploy(address indexed prover, address owner);

    /// @dev Thrown creating a prover before the registry is initialized.
    error NotInitialized();

    /// @dev Thrown if the caller is not authorized to perform the action.
    error NotAuthorized();

    /// @dev Thrown if the specified prover does not exist.
    error ProverNotFound();

    /// @dev Thrown if a prover already exists for this owner.
    error ProverAlreadyExists();

    /// @notice The address of the VApp.
    function vapp() external view returns (address);

    /// @notice The address of the $PROVE token.
    function prove() external view returns (address);

    /// @notice The address of the $iPROVE token.
    function iProve() external view returns (address);

    /// @notice The number of provers in the registry.
    function proverCount() external view returns (uint256);

    /// @notice The owner of a given prover.
    /// @param prover The address of the prover.
    /// @return The address of the owner.
    function ownerOf(address prover) external view returns (address);

    /// @notice Check if a given address is a prover.
    /// @param prover The address of the prover.
    /// @return True if the address is a prover, false otherwise.
    function isProver(address prover) external view returns (bool);

    /// @notice Get the address of a prover for a given owner.
    /// @param owner The address of the owner.
    /// @return The address of the prover.
    function getProver(address owner) external view returns (address);

    /// @notice Check if a given address is the owner of a prover.
    /// @param owner The address of the owner.
    /// @return True if the address is the owner of a prover, false otherwise.
    function hasProver(address owner) external view returns (bool);
}
