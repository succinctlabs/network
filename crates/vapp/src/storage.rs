use std::collections::btree_map::Entry;

use alloy_primitives::U256;
use alloy_sol_types::SolValue;

/// Storage trait providing basic operations matching those available on MerkleStore.
pub trait Storage<K: StorageKey, V: StorageValue> {
    /// Creates a new empty storage.
    fn new() -> Self;

    /// Insert a value at the given key.
    fn insert(&mut self, key: K, value: V);

    /// Remove a value at the given key.
    fn remove(&mut self, key: K);

    /// Gets an entry at the given key.
    fn entry(&mut self, key: K) -> Entry<U256, V>;

    /// Get a value at the given key.
    fn get(&self, key: &K) -> Option<&V>;

    /// Get a mutable reference to a value at the given key.
    fn get_mut(&mut self, key: &K) -> Option<&mut V>;
}

/// Trait for types that can be used as keys in a [MerkleTree].
pub trait StorageKey: Clone + Eq + std::hash::Hash + Ord {
    /// Converts the key to a [U256] index for the merkle tree.
    fn index(&self) -> U256;

    /// Returns the number of bits in the index space.
    fn bits() -> usize;
}

/// Trait for types that can be used as values in a [MerkleTree].
pub trait StorageValue: SolValue + Clone {}
