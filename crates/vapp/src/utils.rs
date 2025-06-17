//! Utilities.
//!
//! This module contains the utilities for the vApp.

use alloy_primitives::Address;
use spn_network_types::TransactionVariant;

use crate::errors::VAppPanic;

/// Converts a 32-byte array to a 8-word array in big-endian order.
pub fn bytes_to_words_be(bytes: &[u8; 32]) -> Result<[u32; 8], VAppPanic> {
    let mut words = [0u32; 8];
    for i in 0..8 {
        let chunk: [u8; 4] =
            bytes[i * 4..(i + 1) * 4].try_into().map_err(|_| VAppPanic::FailedToParseBytes)?;
        words[i] = u32::from_be_bytes(chunk);
    }
    Ok(words)
}

/// Converts a byte array to an address.
pub fn address(bytes: &[u8]) -> Result<Address, VAppPanic> {
    Address::try_from(bytes).map_err(|_| VAppPanic::AddressDeserializationFailed)
}

/// Converts a variant to a transaction variant.
pub fn tx_variant(variant: i32) -> Result<TransactionVariant, VAppPanic> {
    TransactionVariant::try_from(variant).map_err(|_| VAppPanic::InvalidTransactionVariant)
}
