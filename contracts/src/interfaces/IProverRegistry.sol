// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IProverRegistry {
    /// @dev Emitted when a prover is deployed.
    event ProverDeploy(address indexed prover, address owner, uint256 stakerFeeBips);

    /// @dev Emitted when a prover is deactivated.
    event ProverDeactivation(address indexed prover);

    /// @dev Thrown creating a prover before the registry is initialized.
    error NotInitialized();

    /// @dev Thrown if the caller is not authorized to perform the action.
    error NotAuthorized();

    /// @dev Thrown when an address parameter is zero.
    error ZeroAddress();

    /// @dev Thrown if the specified prover does not exist.
    error ProverNotFound();

    /// @dev Thrown if a prover already exists for this owner.
    error ProverAlreadyExists();

    /// @dev Thrown if the staker fee is greater than 100%.
    error InvalidStakerFeeBips();

    /// @dev Thrown when attempting to stake to a deactivated prover.
    error ProverNotActive();

    /// @notice The address of the governor contract.
    function governor() external view returns (address);

    /// @notice The address of the VApp.
    function vapp() external view returns (address);

    /// @notice The address of the $PROVE token.
    function prove() external view returns (address);

    /// @notice The address of the $iPROVE token.
    function iProve() external view returns (address);

    /// @notice The number of provers in the registry.
    function proverCount() external view returns (uint256);

    /// @notice Check if a given address is a prover.
    /// @dev This does not check if the prover is deactivated, use `isDeactivatedProver` to check
    ///      if the prover is deactivated.
    /// @param prover The address of the prover.
    /// @return True if the address is a prover, false otherwise.
    function isProver(address prover) external view returns (bool);

    /// @notice Check if a given prover is deactivated and cannot be staked to.
    /// @dev A prover can be deactivated if it is slashed to the point where its price-per-share
    ///      drops below the minimum.
    /// @param prover The address of the prover.
    /// @return True if the prover is deactivated, false otherwise.
    function isDeactivatedProver(address prover) external view returns (bool);

    /// @notice Get the address of a prover for a given owner.
    /// @param owner The address of the owner.
    /// @return The address of the prover.
    function getProver(address owner) external view returns (address);

    /// @notice Create a new prover.
    /// @dev The caller becomes the owner of the new prover. Only one prover can be created per
    ///      owner. It is recommended to use a cold wallet to create a prover, and then
    ///      immediately set a delegated signer to a hot wallet for the prover.
    /// @param stakerFeeBips The reward percentage in basis points (one-hundredth of a percent) that
    ///        goes to the prover's stakers. This cannot be changed after the prover is created.
    /// @return The address of the new prover.
    function createProver(uint256 stakerFeeBips) external returns (address);
}
