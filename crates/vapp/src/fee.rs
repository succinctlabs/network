//! Fee Calculation.
//!
//! This module contains the constants and functions related to calculating the fee split upon the
//! processing of a [`crate::transactions::VAppTransaction::Clear`] transaction.

use crate::{errors::VAppPanic, u256};
use alloy_primitives::U256;

/// The protocol fee in bips.
pub const PROTOCOL_FEE_BIPS: U256 = U256::ZERO;

/// Calculates the fee split for a given reward.
///
/// Returns (`protocol_reward`, `staker_reward`, `owner_reward`).
pub fn fee(
    amount: U256,
    protocol_fee_bips: U256,
    staker_fee_bips: U256,
) -> Result<(U256, U256, U256), VAppPanic> {
    // Basis points denominator (100% = 10_000 bips).
    let denominator = U256::from(10_000u64);

    // Ensure individual bips are within the valid 0–10_000 range.
    if protocol_fee_bips > denominator {
        return Err(VAppPanic::ProtocolFeeTooHigh { bips: protocol_fee_bips });
    }
    if staker_fee_bips > denominator {
        return Err(VAppPanic::StakerFeeTooHigh { bips: staker_fee_bips });
    }

    // Adjust the staker fee if the total fee exceeds 100%.
    //
    // Example:
    // - protocol_fee_bips = 5000
    // - staker_fee_bips = 7000
    // - total_fee_bips = 12000
    // - adjusted_staker_fee_bips = 5000
    let total_fee_bips = u256::add(protocol_fee_bips, staker_fee_bips)?;
    let adjusted_staker_fee_bips = if total_fee_bips > denominator {
        let overflow = u256::sub(total_fee_bips, denominator)?;
        u256::sub(staker_fee_bips, overflow)?
    } else {
        staker_fee_bips
    };

    // Ensure that the combined fee percentages do not exceed 100%.
    if u256::add(protocol_fee_bips, adjusted_staker_fee_bips)? > denominator {
        return Err(VAppPanic::TotalFeeTooHigh {
            protocol_bips: protocol_fee_bips,
            staker_bips: staker_fee_bips,
        });
    }

    let protocol_reward = u256::div(u256::mul(amount, protocol_fee_bips)?, denominator)?;
    let staker_reward = u256::div(u256::mul(amount, adjusted_staker_fee_bips)?, denominator)?;
    let owner_reward = u256::sub(u256::sub(amount, protocol_reward)?, staker_reward)?;

    Ok((protocol_reward, staker_reward, owner_reward))
}
