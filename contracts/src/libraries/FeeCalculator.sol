// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IProver} from "../interfaces/IProver.sol";
import {ISuccinctStaking} from "../interfaces/ISuccinctStaking.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/// @title FeeCalculator
/// @notice Library for calculating and distributing fees for rewards.
library FeeCalculator {
    using SafeERC20 for IERC20;

    uint256 internal constant FEE_UNIT = 10000;

    /// @notice Calculates the fee split for a reward amount.
    /// @param _totalAmount The total reward amount
    /// @param _protocolFeeBips The protocol fee in basis points
    /// @param _stakerFeeBips The staker fee in basis points
    /// @return protocolFee The protocol fee amount
    /// @return stakerReward The staker reward amount
    /// @return ownerReward The prover owner reward amount
    function calculateFeeSplit(
        uint256 _totalAmount,
        uint256 _protocolFeeBips,
        uint256 _stakerFeeBips
    ) internal pure returns (uint256 protocolFee, uint256 stakerReward, uint256 ownerReward) {
        // Step 1: Calculate protocol fee.
        protocolFee = (_totalAmount * _protocolFeeBips) / FEE_UNIT;
        uint256 remainingAfterProtocol = _totalAmount - protocolFee;

        // Step 2: Calculate staker reward from remaining amount.
        stakerReward = (remainingAfterProtocol * _stakerFeeBips) / FEE_UNIT;

        // Step 3: Owner gets the remainder.
        ownerReward = remainingAfterProtocol - stakerReward;
    }

    /// @notice Processes a reward by calculating fees and distributing tokens.
    /// @param _prover The prover address
    /// @param _totalAmount The total reward amount
    /// @param _protocolFeeBips The protocol fee in basis points
    /// @param _prove The PROVE token address
    /// @param _feeVault The fee vault address
    /// @param _staking The staking contract address
    function processReward(
        address _prover,
        uint256 _totalAmount,
        uint256 _protocolFeeBips,
        address _prove,
        address _feeVault,
        address _staking
    ) internal {
        uint256 stakerFeeBips = IProver(_prover).stakerFeeBips();

        // Calculate fee split.
        (uint256 protocolFee, uint256 stakerReward, uint256 ownerReward) =
            calculateFeeSplit(_totalAmount, _protocolFeeBips, stakerFeeBips);

        // Step 1: Transfer protocol fee to fee vault (if any).
        if (protocolFee > 0) {
            IERC20(_prove).safeTransfer(_feeVault, protocolFee);
        }

        // Step 2: Transfer staker reward to staking contract and notify (if any).
        if (stakerReward > 0) {
            IERC20(_prove).safeTransfer(_staking, stakerReward);
            ISuccinctStaking(_staking).reward(_prover, stakerReward);
        }

        // Step 3: Transfer owner reward to prover owner (if any).
        if (ownerReward > 0) {
            address owner = IProver(_prover).owner();
            IERC20(_prove).safeTransfer(owner, ownerReward);
        }
    }
}
