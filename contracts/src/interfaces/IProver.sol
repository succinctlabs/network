// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IProver {
    /// @dev Thrown when a transfer is attempted.
    error NonTransferable();

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
}
