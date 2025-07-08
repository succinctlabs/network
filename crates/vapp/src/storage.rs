//! Storage.
//!
//! This module contains the traits for the storage of the vApp.

use std::collections::btree_map::Entry;

use alloy_primitives::{Address, U256};
use alloy_sol_types::SolValue;
use thiserror::Error;

/// Storage trait providing basic operations matching those available on `MerkleStore`.
pub trait Storage<K: StorageKey, V: StorageValue> {
    /// Creates a new empty storage.
    fn new() -> Self;

    /// Insert a value at the given key.
    fn insert(&mut self, key: K, value: V) -> Result<(), StorageError>;

    /// Gets an entry at the given key.
    fn entry(&mut self, key: K) -> Result<Entry<U256, V>, StorageError>;

    /// Get a value at the given key.
    fn get(&mut self, key: &K) -> Result<Option<&V>, StorageError>;

    /// Get a mutable reference to a value at the given key.
    fn get_mut(&mut self, key: &K) -> Result<Option<&mut V>, StorageError>;
}

/// Errors that can occur when interacting with storage.
#[derive(Debug, Error, PartialEq)]
pub enum StorageError {
    /// The key is not allowed in the current context.
    #[error("key not allowed")]
    KeyNotAllowed,
}

/// Trait for types that can be used as keys in a [`MerkleTree`].
pub trait StorageKey: Clone + Eq + std::hash::Hash + Ord {
    /// Converts the key to a [U256] index for the merkle tree.
    fn index(&self) -> U256;

    /// Returns the number of bits in the index space.
    fn bits() -> usize;
}

impl StorageKey for U256 {
    fn index(&self) -> U256 {
        *self
    }

    fn bits() -> usize {
        256
    }
}

impl StorageKey for Address {
    fn index(&self) -> U256 {
        U256::from_be_slice(&self.0 .0)
    }

    fn bits() -> usize {
        160
    }
}

/// The unique identifier hash of a [`spn_network_types::RequestProofRequestBody`].
pub type RequestId = [u8; 32];

impl StorageKey for RequestId {
    fn index(&self) -> U256 {
        U256::from_be_slice(&self[..20])
    }

    fn bits() -> usize {
        160
    }
}

/// Trait for types that can be used as values in a [`crate::merkle::MerkleTree`].
pub trait StorageValue: SolValue + Clone + Default {}

impl<V: SolValue + Clone + Default> StorageValue for V {}
