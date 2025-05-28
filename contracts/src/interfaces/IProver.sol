// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IProver {
    /// @dev Thrown when a transfer is attempted.
    error NonTransferable();

    /// @notice Get the staking contract for this prover.
    /// @return The address of the staking contract.
    function staking() external view returns (address);

    /// @notice Get the owner of this prover.
    /// @dev This address MUST be capable of receiving $USDC rewards. Some portion of the rewards
    ///      for fulfilling a proof will go directly to this address, while the rest is distributed
    ///      to this prover's stakers.
    /// @return The address of the owner.
    function owner() external view returns (address);

    /// @notice Get the ID of this prover. IDs are assigned sequentially, incrementing
    ///         each time a prover is created.
    /// @dev This is purely for informational purposes.
    /// @return The ID of the prover.
    function id() external view returns (uint256);

    /// @notice Get the staker fee percentage in basis points (one-hundredth of a percent). For a
    ///         given reward, this much goes into this vault.
    /// @return The staker fee percentage in basis points.
    function stakerFeeBips() external view returns (uint256);

    /// @notice Claim the rewards for this prover.
    function claimRewards() external;
}
