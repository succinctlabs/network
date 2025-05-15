// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IIntermediateSuccinct {
    /// @dev Thrown when a transfer is attempted.
    error NonTransferable();

    /// @notice Returns the address of the staking contract.
    function staking() external view returns (address);

    /// @notice Burn $iPROVE. Only callable by the staking contract.
    /// @param from The address of the staker.
    /// @param iPROVE The amount of $iPROVE to burn.
    /// @return The amount of $PROVE burned.
    function burn(address from, uint256 iPROVE) external returns (uint256);
}
