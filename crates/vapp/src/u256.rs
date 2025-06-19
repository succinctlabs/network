//! U256 Safe Arithmetic Operations.
//!
//! This module contains the safe arithmetic operations for the U256 type.

use alloy_primitives::U256;

use crate::errors::VAppPanic;

/// Safe addition of two U256 values.
pub fn add(a: U256, b: U256) -> Result<U256, VAppPanic> {
    a.checked_add(b).ok_or(VAppPanic::ArithmeticOverflow)
}

/// Safe subtraction of two U256 values.
pub fn sub(a: U256, b: U256) -> Result<U256, VAppPanic> {
    a.checked_sub(b).ok_or(VAppPanic::ArithmeticOverflow)
}

/// Safe multiplication of two U256 values.
pub fn mul(a: U256, b: U256) -> Result<U256, VAppPanic> {
    a.checked_mul(b).ok_or(VAppPanic::ArithmeticOverflow)
}

/// Safe division of two U256 values.
pub fn div(a: U256, b: U256) -> Result<U256, VAppPanic> {
    a.checked_div(b).ok_or(VAppPanic::ArithmeticOverflow)
}
