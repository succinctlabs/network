use alloy_primitives::Address;

use crate::errors::{VAppError, VAppPanic};

pub fn bytes_to_words_be(bytes: &[u8; 32]) -> [u32; 8] {
    let mut words = [0u32; 8];
    for i in 0..8 {
        let chunk: [u8; 4] = bytes[i * 4..(i + 1) * 4].try_into().unwrap();
        words[i] = u32::from_be_bytes(chunk);
    }
    words
}

pub fn address(bytes: &[u8]) -> Result<Address, VAppError> {
    Address::try_from(bytes).map_err(|_| VAppPanic::AddressDeserializationFailed.into())
}