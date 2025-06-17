// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IProver {
    /// @dev Thrown when a transfer is attempted.
    error NonTransferable();

    /// @dev Thrown when the caller is not the staking contract.
    error NotStaking();

    /// @notice Get the $PROVE token
    /// @dev This address cannot be changed.
    /// @return The address of the $PROVE token.
    function prove() external view returns (address);

    /// @notice Get the staking contract for this prover.
    /// @dev This address cannot be changed.
    /// @return The address of the staking contract.
    function staking() external view returns (address);

    /// @notice Get the owner of this prover.
    /// @dev This acts as a withdrawal address for the $PROVE rewards of fulfilling proofs. In particular,
    ///      once the protocolFeeBips and stakerFeeBips are subtracted from the reward, the remaining
    ///      amount is sent to this address. This address cannot be changed.
    /// @return The address of the owner.
    function owner() external view returns (address);

    /// @notice Get the ID of this prover. IDs are assigned sequentially, incrementing
    ///         each time a prover is created.
    /// @dev This is purely for informational purposes. This ID cannot be changed.
    /// @return The ID of the prover.
    function id() external view returns (uint256);

    /// @notice Get the staker fee percentage in basis points (one-hundredth of a percent). For a
    ///         given $PROVE reward, this much goes into this vault.
    /// @dev This fee cannot be changed.
    /// @return The staker fee percentage in basis points.
    function stakerFeeBips() external view returns (uint256);

    /// @notice Transfer $PROVE to the staking contract. Only callable by the staking contract.
    /// @dev Since in SuccinctStaking.permitAndStake(), the staker approves the prover to spend $PROVE,
    ///      the staking contract needs to transfer the $PROVE utilizing this contract as the spender.
    /// @param from The address to transfer $PROVE from.
    /// @param amount The amount of $PROVE to transfer.
    function transferProveToStaking(address from, uint256 amount) external;
}
