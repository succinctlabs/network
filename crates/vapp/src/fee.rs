//! Fee Calculation.
//!
//! This module contains the constants and functions related to calculating the fee split upon the
//! processing of a [`crate::transactions::VAppTransaction::Clear`] transaction.

use alloy_primitives::U256;

/// Calculates the fee split for a given reward.
///
/// Returns (`protocol_reward`, `staker_reward`, `owner_reward`).
#[must_use] pub fn fee(amount: U256, protocol_fee_bips: U256, staker_fee_bips: U256) -> (U256, U256, U256) {
    let denominator = U256::from(10_000);
    let protocol_reward = amount * protocol_fee_bips / denominator;
    let staker_reward = amount * staker_fee_bips / denominator;
    let owner_reward = amount - protocol_reward - staker_reward;

    (protocol_reward, staker_reward, owner_reward)
}
