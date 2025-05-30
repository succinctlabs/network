// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IProverRegistry {
    /// @dev Emitted when a prover is deployed.
    event ProverDeploy(address indexed prover, address owner);

    /// @dev Emitted when a delegated signer is request to be set.
    event DelegatedSignerSet(address indexed prover, address signer);

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

    /// @notice Get the delegated signer for a given prover.
    /// @dev This is a convenience function that calls the delegatedSigner function on the VApp.
    /// @param prover The address of the prover.
    /// @return The address of the delegated signer.
    function delegatedSigner(address prover) external view returns (address);

    /// @notice Create a new prover.
    /// @dev The caller becomes the owner of the new prover. Only one prover can be created per
    ///      owner. It is highly recommended to use a cold wallet or multisig to create a prover,
    ///      and then immediately set a delegated signer to a hot wallet for the prover.
    /// @param stakerFeeBips The reward percentage in basis points (one-hundredth of a percent) that
    ///        goes to the prover's stakers. This cannot be changed after the prover is created.
    /// @return The address of the new prover.
    function createProver(uint256 stakerFeeBips) external returns (address);

    /// @notice Set the delegated signer for a prover to the given address. Only callable by the prover owner.
    ///         This is not instantanious, and only after confirming with the signer and waiting until the VApp
    ///         state has been updated will this take effect.
    /// @dev This allows the signer EOA to sign messages on behalf of the prover. In the Succinct Prover Network,
    ///      this means that key running the prover node software can bid in proof auctions, and it will use the
    ///      prover's stake to bid. This also means that if the signer misbehaves, it is this prover's stake that
    ///      is at risk for being slashed.
    /// @param prover The address of the prover.
    /// @param signer The address of the delegated signer.
    /// @return The receipt of the action.
    function setDelegatedSigner(address prover, address signer) external returns (uint64);
}
