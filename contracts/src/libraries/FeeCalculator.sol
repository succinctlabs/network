// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title FeeCalculator
/// @notice Library for calculating and distributing fees for rewards.
/// @dev This occurs offchain in the VApp, and only exists in Solidity for testing purposes.
library FeeCalculator {
    uint256 internal constant FEE_UNIT = 10000;

    /// @notice Calculates the fee split for a reward amount.
    /// @param _totalAmount The total reward amount.
    /// @param _protocolFeeBips The protocol fee in basis points.
    /// @param _stakerFeeBips The staker fee in basis points.
    /// @return protocolReward The protocol reward amount.
    /// @return stakerReward The staker reward amount.
    /// @return ownerReward The prover owner reward amount.
    function calculateFeeSplit(
        uint256 _totalAmount,
        uint256 _protocolFeeBips,
        uint256 _stakerFeeBips
    ) internal pure returns (uint256 protocolReward, uint256 stakerReward, uint256 ownerReward) {
        // Step 1: Calculate protocol reward from the protocol fee.
        protocolReward = (_totalAmount * _protocolFeeBips) / FEE_UNIT;
        uint256 remainingAfterProtocol = _totalAmount - protocolReward;

        // Step 2: Calculate staker reward from staker fee.
        stakerReward = (remainingAfterProtocol * _stakerFeeBips) / FEE_UNIT;

        // Step 3: The remaining amount is the owner reward.
        ownerReward = remainingAfterProtocol - stakerReward;
    }
}
