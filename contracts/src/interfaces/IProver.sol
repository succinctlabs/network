// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IProver {
    /// @dev Thrown when a zero address is provided.
    error ZeroAddress();

    /// @dev Thrown when the caller is not the prover owner.
    error NotProverOwner();

    /// @dev Thrown when the caller is not the staking contract.
    error NotStaking();

    /// @dev Thrown when a transfer is attempted.
    error NonTransferable();

    /// @notice The staking contract that corresponding to this prover.
    /// @dev This address cannot be changed.
    /// @return The address of the staking contract.
    function staking() external view returns (address);

    /// @notice The governor used in protocol governance.
    /// @dev This address cannot be changed.
    /// @return The address of the governor contract.
    function governor() external view returns (address);

    /// @notice The $PROVE token
    /// @dev This address cannot be changed.
    /// @return The address of the $PROVE token.
    function prove() external view returns (address);

    /// @notice The owner of this prover. The owner was the address that created this prover by
    ///         calling `createProver()` on the staking contract. The owner has control over
    ///         particpiation in governance, collection of prover owner rewards, and the signing
    ///         rights of verifiable prover network actions such as bidding and fulfilling proofs.
    /// @dev This address cannot be changed.
    /// @return The address of the prover owner.
    function owner() external view returns (address);

    /// @notice The ID of this prover. IDs are assigned sequentially, incrementing
    ///         each time a prover is created.
    /// @dev This is purely for informational purposes. This ID cannot be changed.
    /// @return The ID of the prover.
    function id() external view returns (uint256);

    /// @notice The staker fee percentage in basis points (one-hundredth of a percent). For a
    ///         given $PROVE reward for fulfilling proofs, this much goes into this prover.
    /// @dev This fee cannot be changed.
    /// @return The staker fee percentage in basis points.
    function stakerFeeBips() external view returns (uint256);

    /// @notice Create a governance proposal. Only callable by the prover owner.
    /// @dev This function is a wrapper around `IGovernor.propose`.
    /// @param targets The addresses of the contracts to call.
    /// @param values The amounts of ETH to send.
    /// @param calldatas The calldata for each call.
    /// @param description The proposal description.
    /// @return The proposal ID.
    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) external returns (uint256);

    /// @notice Cancel a governance proposal. Only callable by the prover owner.
    /// @dev This function is a wrapper around `IGovernor.cancel`.
    /// @param targets The addresses of the contracts to call.
    /// @param values The amounts of ETH to send.
    /// @param calldatas The calldata for each call.
    /// @param descriptionHash The hash of the proposal description.
    /// @return The proposal ID.
    function cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) external returns (uint256);

    /// @notice Cast a vote on a governance proposal. Only callable by the prover owner.
    /// @dev This function is a wrapper around `IGovernor.castVote`.
    /// @param proposalId The ID of the proposal.
    /// @param support The vote type (0 = Against, 1 = For, 2 = Abstain).
    /// @return The voting weight used.
    function castVote(uint256 proposalId, uint8 support) external returns (uint256);

    /// @notice Transfer $PROVE to the staking contract. Only callable by the staking contract.
    /// @dev Since in `SuccinctStaking.permitAndStake()`, the staker approves the prover to spend $PROVE, the
    ///      staking contract needs to transfer the $PROVE utilizing this contract as the spender.
    /// @param from The address to transfer $PROVE from.
    /// @param amount The amount of $PROVE to transfer.
    function transferProveToStaking(address from, uint256 amount) external;
}
