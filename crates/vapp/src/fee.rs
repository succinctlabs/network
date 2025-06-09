//! Fee Calculation.
//!
//! This module contains the logic for calculating the fee split for a total reward.

use alloy_primitives::U256;

/// Basis points denominator (10000 = 100%).
pub const FEE_UNIT: u32 = 10000;

/// Calculates the fee split for a total reward.
///
/// Returns (protocol_reward, staker_reward, owner_reward).
pub fn calculate_fee_split(
    amount: U256,
    protocol_fee_bips: U256,
    staker_fee_bips: U256,
) -> (U256, U256, U256) {
    let unit = U256::from(FEE_UNIT);

    let protocol_reward = amount * protocol_fee_bips / unit;
    let staker_reward = amount * staker_fee_bips / unit;
    let owner_reward = amount - protocol_reward - staker_reward;

    (protocol_reward, staker_reward, owner_reward)
}
