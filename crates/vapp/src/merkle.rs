//! Merkelized Storage.
//!
//! This module contains implementations of the [`MerkleStorage`] data structure, which is used to
//! store and retrieve data inside the vApp while keeping all leaves in memory.

use std::{
    collections::{btree_map::Entry, BTreeMap, BTreeSet},
    marker::PhantomData,
};

use alloy_primitives::{keccak256, Keccak256, B256, U256};
use serde::{Deserialize, Serialize};
use thiserror::Error;

use crate::{
    sparse::SparseStorage,
    storage::{Storage, StorageError, StorageKey, StorageValue},
};

/// Merkle tree with key type K and value type V.
///
/// This implementation supports `2^K::bits()` possible indices and uses sparse storage to
/// efficiently handle large address spaces. Empty subtrees are optimized using precomputed zero
/// hashes.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MerkleStorage<K: StorageKey, V: StorageValue, H: MerkleTreeHasher = Keccak256> {
    /// Sparse storage for non-empty leaves (key -> value).
    leaves: BTreeMap<U256, V>,
    /// Precomputed zero hashes for each layer (optimization for sparse trees).
    zero_hashes: Vec<B256>,
    /// Cache for computed node hashes to avoid recomputation.
    #[serde(skip)]
    cache: BTreeMap<(usize, U256), B256>,
    /// Set of keys that have been touched (read or written).
    #[serde(skip)]
    touched_keys: BTreeSet<K>,
    /// The phantom data for the key type.
    _key: PhantomData<K>,
    /// The phantom data for the hasher type.
    _hasher: PhantomData<H>,
}

/// Errors that can occur during [`MerkleStorage`] operations.
#[derive(Debug, Error, PartialEq, Serialize, Deserialize)]
#[allow(missing_docs)]
pub enum MerkleStorageError {
    #[error("Index {index} out of bounds for {num_bits} bits")]
    IndexOutOfBounds { index: U256, num_bits: usize },

    #[error("Invalid merkle proof provided")]
    InvalidMerkleProof,

    #[error("Missing merkle proof for updated key")]
    MissingMerkleProofForUpdatedKey,

    #[error("Failed to compute new root")]
    FailedToComputeNewRoot,

    #[error("Invalid merkle proof length")]
    InvalidMerkleProofLength,
}

/// A merkle proof for a key-value pair in the [`MerkleStorage`].
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MerkleProof<K: StorageKey, V: StorageValue, H: MerkleTreeHasher = Keccak256> {
    /// The key being accessed.
    pub key: K,
    /// The current value at the key (`None` if the leaf is empty).
    pub value: Option<V>,
    /// The merkle proof path.
    pub proof: Vec<B256>,
    /// The phantom data for the hasher type.
    #[serde(skip)]
    _hasher: PhantomData<H>,
}

impl<K: StorageKey, V: StorageValue, H: MerkleTreeHasher> MerkleProof<K, V, H> {
    /// Construct a proof for a key that currently holds a value.
    pub fn new(key: K, value: Option<V>, proof: Vec<B256>) -> Self {
        Self { key, value, proof, _hasher: PhantomData }
    }
}

/// Trait for types that can be used as the hasher in a [`MerkleTree`].
pub trait MerkleTreeHasher {
    /// Returns the hash of the value.
    fn hash<V: StorageValue>(value: &V) -> B256;

    /// Returns the hash of the pair of values.
    fn hash_pair<V: StorageValue>(left: &V, right: &V) -> B256;
}

impl<K: StorageKey, V: StorageValue, H: MerkleTreeHasher> MerkleStorage<K, V, H> {
    /// Compute the merkle root from scratch.
    pub fn root(&mut self) -> B256 {
        let num_bits = K::bits();

        // If no leaves, return the precomputed empty tree root.
        if self.leaves.is_empty() {
            return self.zero_hashes[num_bits];
        }

        // Build the tree bottom-up.
        let mut current_layer: BTreeMap<U256, B256> = BTreeMap::new();

        // Start with leaves (layer 0) - hash the values.
        for (&index, value) in &self.leaves {
            let hash = H::hash(value);
            current_layer.insert(index, hash);
        }

        // Build each layer up to the root.
        for layer in 1..=num_bits {
            let mut next_layer: BTreeMap<U256, B256> = BTreeMap::new();

            // Process all nodes that exist in current layer.
            for (&index, &hash) in &current_layer {
                let parent_index = index >> 1;
                let is_left_child = (index & U256::from(1)) == U256::ZERO;

                // Get or create parent entry.
                let parent_entry = next_layer.entry(parent_index).or_insert_with(|| {
                    if is_left_child {
                        H::hash_pair(&hash, &self.zero_hashes[layer - 1])
                    } else {
                        H::hash_pair(&self.zero_hashes[layer - 1], &hash)
                    }
                });

                // Update parent with both children if we now have the sibling.
                if is_left_child {
                    let sibling_index = index | U256::from(1);
                    if let Some(&sibling_hash) = current_layer.get(&sibling_index) {
                        *parent_entry = H::hash_pair(&hash, &sibling_hash);
                    }
                } else {
                    let sibling_index = index & !U256::from(1);
                    if let Some(&sibling_hash) = current_layer.get(&sibling_index) {
                        *parent_entry = H::hash_pair(&sibling_hash, &hash);
                    }
                }
            }

            current_layer = next_layer;
        }

        // Return root or empty tree hash if no nodes made it to the top.
        let num_bits = K::bits();
        current_layer.get(&U256::ZERO).copied().unwrap_or(self.zero_hashes[num_bits])
    }

    /// Generate a merkle proof for the value at the given key.
    pub fn proof(&mut self, key: &K) -> Result<MerkleProof<K, V, H>, MerkleStorageError> {
        let index = key.index();
        let num_bits = K::bits();

        if K::bits() < 256 && index >= (U256::from(1) << num_bits) {
            return Err(MerkleStorageError::IndexOutOfBounds { index, num_bits });
        }

        let mut proof = Vec::new();
        let mut current_index = index;
        for layer in 0..num_bits {
            // Get sibling index.
            let sibling_index = current_index ^ U256::from(1);

            // Get the sibling hash.
            let sibling_hash = if layer == 0 {
                if let Some(value) = self.leaves.get(&sibling_index) {
                    H::hash(value)
                } else {
                    self.zero_hashes[0]
                }
            } else if let Some(&cached_hash) = self.cache.get(&(layer, sibling_index)) {
                cached_hash
            } else {
                // Check if sibling subtree is completely empty.
                if self.is_subtree_empty(layer, sibling_index) {
                    self.zero_hashes[layer]
                }
                // Compute and cache the sibling hash bottom-up.
                else {
                    self.compute_node(layer, sibling_index)
                }
            };

            proof.push(sibling_hash);
            current_index >>= 1;
        }

        Ok(MerkleProof::new(key.clone(), self.leaves.get(&index).cloned(), proof))
    }

    /// Check if a subtree is completely empty (contains no leaves).
    fn is_subtree_empty(&self, layer: usize, index: U256) -> bool {
        // Calculate the range of leaf indices that this subtree covers.
        let start_leaf = index << layer;
        let end_leaf = start_leaf + (U256::from(1) << layer);

        // Use BTreeMap's range query to efficiently check if any keys exist in the range.
        if end_leaf == U256::ZERO {
            self.leaves.range(start_leaf..).next().is_none()
        } else {
            self.leaves.range(start_leaf..end_leaf).next().is_none()
        }
    }

    /// Compute a node hash bottom-up, caching intermediate results.
    fn compute_node(&mut self, target_layer: usize, target_index: U256) -> B256 {
        // Build a stack of (layer, index) pairs that need to be computed.
        let mut stack = Vec::new();
        let mut to_compute = vec![(target_layer, target_index)];

        // Find all nodes that need computation (not cached and not empty).
        while let Some((layer, index)) = to_compute.pop() {
            if layer == 0 {
                // Leaf node - no dependencies.
                continue;
            }

            if self.cache.contains_key(&(layer, index)) {
                // Already cached.
                continue;
            }

            if self.is_subtree_empty(layer, index) {
                // Empty subtree - cache zero hash.
                self.cache.insert((layer, index), self.zero_hashes[layer]);
                continue;
            }

            // Add to computation stack.
            stack.push((layer, index));

            // Add children to be computed first.
            let left_child = index << 1;
            let right_child = left_child | U256::from(1);

            to_compute.push((layer - 1, left_child));
            to_compute.push((layer - 1, right_child));
        }

        // Compute hashes bottom-up.
        while let Some((layer, index)) = stack.pop() {
            if self.cache.contains_key(&(layer, index)) {
                continue; // Already computed.
            }

            let left_child = index << 1;
            let right_child = left_child | U256::from(1);

            let left_hash = if layer == 1 {
                // Children are leaves.
                if let Some(value) = self.leaves.get(&left_child) {
                    H::hash(value)
                } else {
                    self.zero_hashes[0]
                }
            } else {
                // Children are internal nodes - should be cached now.
                self.cache
                    .get(&(layer - 1, left_child))
                    .copied()
                    .unwrap_or(self.zero_hashes[layer - 1])
            };

            let right_hash = if layer == 1 {
                // Children are leaves.
                if let Some(value) = self.leaves.get(&right_child) {
                    H::hash(value)
                } else {
                    self.zero_hashes[0]
                }
            } else {
                // Children are internal nodes - should be cached now.
                self.cache
                    .get(&(layer - 1, right_child))
                    .copied()
                    .unwrap_or(self.zero_hashes[layer - 1])
            };

            let hash = H::hash_pair(&left_hash, &right_hash);
            self.cache.insert((layer, index), hash);
        }

        // Return the computed hash.
        self.cache
            .get(&(target_layer, target_index))
            .copied()
            .unwrap_or(self.zero_hashes[target_layer])
    }

    /// Get the set of keys that have been touched (read or written).
    #[must_use]
    pub fn get_touched_keys(&self) -> &BTreeSet<K> {
        &self.touched_keys
    }

    /// Clear the tracking of touched keys.
    pub fn clear_key_tracking(&mut self) {
        self.touched_keys.clear();
    }

    /// Get a value at the given key without tracking access.
    pub fn get_untracked(&self, key: &K) -> Option<&V> {
        let index = key.index();
        self.leaves.get(&index)
    }

    /// Get a value at the given key and track the access.
    pub fn get_tracked(&mut self, key: &K) -> Option<&V> {
        let index = key.index();
        // Track that this key has been touched (read).
        self.touched_keys.insert(key.clone());
        self.leaves.get(&index)
    }

    /// Manually track a key as touched.
    pub fn track_touched(&mut self, key: &K) {
        self.touched_keys.insert(key.clone());
    }

    /// Verify a merkle proof for a key-value pair.
    pub fn verify_proof(
        root: B256,
        proof: &MerkleProof<K, V, H>,
    ) -> Result<(), MerkleStorageError> {
        let index = proof.key.index();
        let leaf_hash = match &proof.value {
            Some(v) => H::hash(v),
            None => B256::ZERO, // Empty leaf corresponds to zero hash.
        };

        match Self::verify_proof_with_hash(root, index, leaf_hash, &proof.proof) {
            Ok(()) => Ok(()),
            Err(e) => Err(e),
        }
    }

    /// Verify a merkle proof with a pre-computed leaf hash.
    pub fn verify_proof_with_hash(
        root: B256,
        index: U256,
        leaf_hash: B256,
        proof: &[B256],
    ) -> Result<(), MerkleStorageError> {
        if proof.len() != K::bits() {
            return Err(MerkleStorageError::InvalidMerkleProofLength);
        }

        let mut current_hash = leaf_hash;
        let mut current_index = index;

        for &sibling_hash in proof {
            if current_index & U256::ONE == U256::ZERO {
                current_hash = H::hash_pair(&current_hash, &sibling_hash);
            } else {
                current_hash = H::hash_pair(&sibling_hash, &current_hash);
            }
            current_index >>= 1;
        }

        if current_hash != root {
            return Err(MerkleStorageError::InvalidMerkleProof);
        }

        Ok(())
    }

    /// Compute zero hashes for all layers.
    fn compute_zero_hashes() -> Vec<B256> {
        let num_bits = K::bits();
        let mut zero_hashes = vec![B256::ZERO; num_bits + 1];
        zero_hashes[0] = B256::ZERO;

        for i in 1..=num_bits {
            zero_hashes[i] = H::hash_pair(&zero_hashes[i - 1], &zero_hashes[i - 1]);
        }

        zero_hashes
    }

    /// Calculate a new state root given an old root, merkle proofs, and new values.
    ///
    /// This function efficiently computes the new merkle root by:
    /// 1. Verifying all merkle proofs against the old root
    /// 2. For each updated key, recalculate its path to the root using the proof
    /// 3. Combine all updated paths to get the new root
    ///
    /// # Arguments
    /// * `old_root` - The previous merkle root
    /// * `proofs` - List of merkle proofs for accessed keys
    /// * `new_values` - List of (key, `new_value`) pairs to update
    ///
    /// # Returns
    /// Result containing the new merkle root or an error if proofs are invalid
    pub fn calculate_new_root(
        old_root: B256,
        proofs: &[MerkleProof<K, V, H>],
        new_values: &[(K, V)],
    ) -> Result<B256, MerkleStorageError> {
        // Early return if absolutely nothing was accessed or modified.
        if new_values.is_empty() && proofs.is_empty() {
            return Ok(old_root);
        }

        // -----------------------------------------------------------------------------------------
        // 1. Verify that every supplied proof is valid with respect to the old root. While we do
        //    this, also build a fast-lookup table that tells us whether a particular key has an
        //    updated value or not.
        // -----------------------------------------------------------------------------------------
        let mut updated_value_map: BTreeMap<U256, &V> = BTreeMap::new();
        for (k, v) in new_values {
            updated_value_map.insert(k.index(), v);
        }

        for proof in proofs {
            Self::verify_proof(old_root, proof)?;
        }

        // Ensure that every updated key comes with a proof. Without it we cannot
        // rebalance the tree because we would lack the required sibling hashes
        // on the path to the root.
        for (key, _) in new_values {
            if !proofs.iter().any(|p| p.key == *key) {
                return Err(MerkleStorageError::MissingMerkleProofForUpdatedKey);
            }
        }

        // -----------------------------------------------------------------------------------------
        // 2. Collect all nodes that are known after the update. We build a map keyed by (level,
        //    index) -> hash. Level 0 corresponds to leaves, a larger level means a node that is
        //    further up the tree.  The map is gradually filled while we walk over all proofs.
        // -----------------------------------------------------------------------------------------
        let num_bits = K::bits();
        let mut nodes: BTreeMap<(usize, U256), B256> = BTreeMap::new();

        // Iterate over every proof and replay its path to the root using the
        // (possibly updated) value for the leaf.
        for proof in proofs {
            let leaf_index = proof.key.index();
            let is_updated = updated_value_map.contains_key(&leaf_index);
            let mut current_hash = if is_updated {
                H::hash(updated_value_map[&leaf_index])
            } else {
                match &proof.value {
                    Some(v) => H::hash(v),
                    None => B256::ZERO,
                }
            };
            let mut current_index = leaf_index;

            // Store/overwrite the leaf node.
            nodes.insert((0, current_index), current_hash);

            // Walk up the tree using the supplied sibling hashes.
            for (level, &proof_sibling_hash) in proof.proof.iter().enumerate() {
                let sibling_index = current_index ^ U256::ONE;
                // Prefer an updated sibling hash that might already be present in the map.
                let sibling_hash =
                    nodes.get(&(level, sibling_index)).copied().unwrap_or(proof_sibling_hash);

                // Make sure the sibling is also recorded so later proofs can
                // make use of a potentially updated version.
                nodes.entry((level, sibling_index)).or_insert(sibling_hash);

                // Compose the parent hash.
                let parent_hash = if current_index & U256::ONE == U256::ZERO {
                    H::hash_pair(&current_hash, &sibling_hash)
                } else {
                    H::hash_pair(&sibling_hash, &current_hash)
                };

                current_index >>= 1;
                current_hash = parent_hash;

                // Persist the parent for use by subsequent proofs.
                nodes.insert((level + 1, current_index), current_hash);
            }
        }

        // -----------------------------------------------------------------------------------------
        // 3. The root resides at `level == num_bits` and `index == 0` after all proofs have been
        //    processed.  We stored/overwrote that entry during the previous loop, so we can read it
        //    directly.
        // -----------------------------------------------------------------------------------------
        nodes
            .get(&(num_bits, U256::ZERO))
            .copied()
            .ok_or(MerkleStorageError::FailedToComputeNewRoot)
    }

    /// Calculate a new state root using a `SparseStorage` that contains the **updated** values.
    ///
    /// This is a thin convenience wrapper around [`calculate_new_root`] that collects the
    /// updated values from the provided `SparseStorage` and forwards the computation to the
    /// original implementation. The function still requires the caller to supply merkle proofs
    /// for *all* keys that are updated; otherwise, the function will return an error.
    pub fn calculate_new_root_sparse(
        old_root: B256,
        proofs: &[MerkleProof<K, V, H>],
        updates: &SparseStorage<K, V>,
    ) -> Result<B256, MerkleStorageError> {
        // Fast-path: nothing accessed or modified.
        if updates.is_empty() && proofs.is_empty() {
            return Ok(old_root);
        }

        // Build a `Vec<(K, V)>` with **updated** key/value pairs. We rely on the proofs to
        // provide the canonical key values (`K`) for each updated index.
        let mut new_values: Vec<(K, V)> = Vec::new();

        for (index, value) in updates.iter_raw() {
            // Find the matching proof so we can recover the key of type `K`.
            let Some(proof) = proofs.iter().find(|p| p.key.index() == *index) else {
                return Err(MerkleStorageError::MissingMerkleProofForUpdatedKey);
            };

            new_values.push((proof.key.clone(), (*value).clone()));
        }

        // Delegate to the original implementation.
        Self::calculate_new_root(old_root, proofs, &new_values)
    }
}

impl<K: StorageKey, V: StorageValue, H: MerkleTreeHasher> Default for MerkleStorage<K, V, H> {
    fn default() -> Self {
        Self::new()
    }
}

impl<K: StorageKey, V: StorageValue, H: MerkleTreeHasher> Storage<K, V> for MerkleStorage<K, V, H> {
    /// Creates a new [`MerkleTree`].
    fn new() -> Self {
        let zero_hashes = Self::compute_zero_hashes();
        Self {
            leaves: BTreeMap::new(),
            zero_hashes,
            cache: BTreeMap::new(),
            touched_keys: BTreeSet::new(),
            _key: PhantomData,
            _hasher: PhantomData,
        }
    }

    /// Insert a value at the given key.
    ///
    /// The value is automatically ABI-encoded and hashed.
    fn insert(&mut self, key: K, value: V) -> Result<(), StorageError> {
        let index = key.index();
        self.leaves.insert(index, value);
        // Track that this key has been touched (written).
        self.touched_keys.insert(key);
        // Clear cache as tree structure has changed.
        self.cache.clear();

        Ok(())
    }

    /// Gets an entry at the given key.
    fn entry(&mut self, key: K) -> Result<Entry<U256, V>, StorageError> {
        let index = key.index();
        // Track that this key has been touched (entry can be used for read or write).
        self.touched_keys.insert(key);
        // Get the entry.
        let entry = self.leaves.entry(index);
        // Clear cache as tree structure may change.
        self.cache.clear();
        Ok(entry)
    }

    /// Get a value at the given key.
    fn get(&mut self, key: &K) -> Result<Option<&V>, StorageError> {
        let index = key.index();
        // Track that this key has been touched (entry can be used for read or write).
        self.touched_keys.insert(key.clone());
        // Get the leaf.
        let leaf = self.leaves.get(&index);
        Ok(leaf)
    }

    /// Get a mutable reference to a value at the given key.
    fn get_mut(&mut self, key: &K) -> Result<Option<&mut V>, StorageError> {
        let index = key.index();
        // Track that this key has been touched (entry can be used for read or write).
        self.touched_keys.insert(key.clone());
        // Get the leaf.
        let leaf = self.leaves.get_mut(&index);
        // Clear cache as tree structure may change.
        self.cache.clear();
        Ok(leaf)
    }
}

impl MerkleTreeHasher for Keccak256 {
    fn hash<V: StorageValue>(value: &V) -> B256 {
        keccak256(value.abi_encode())
    }

    fn hash_pair<V: StorageValue>(left: &V, right: &V) -> B256 {
        let mut input = Vec::with_capacity(64);
        input.extend_from_slice(left.abi_encode().as_slice());
        input.extend_from_slice(right.abi_encode().as_slice());
        keccak256(input)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    use alloy_primitives::{address, uint, Address, U256};

    type U256Tree = MerkleStorage<U256, U256>;
    type AddressTree = MerkleStorage<Address, U256>;

    #[test]
    fn empty_tree_has_expected_root() {
        let mut tree = U256Tree::new();
        let expected_root = tree.zero_hashes[256];
        assert_eq!(tree.root(), expected_root);
    }

    #[test]
    fn single_insertion_generates_valid_proof() {
        let mut tree = U256Tree::new();
        let key = uint!(5_U256);
        let value = uint!(42_U256);

        tree.insert(key, value).unwrap();
        let root = tree.root();
        let proof = tree.proof(&key).unwrap();

        assert!(U256Tree::verify_proof(root, &proof).is_ok());
    }

    #[test]
    fn different_keys_produce_different_roots() {
        let mut tree1 = U256Tree::new();
        let mut tree2 = U256Tree::new();

        tree1.insert(uint!(1_U256), uint!(100_U256)).unwrap();
        tree2.insert(uint!(2_U256), uint!(200_U256)).unwrap();

        assert_ne!(tree1.root(), tree2.root());
    }

    #[test]
    fn proof_verification_fails_with_wrong_value() {
        let mut tree = U256Tree::new();
        let key = uint!(7_U256);
        let value = uint!(300_U256);

        tree.insert(key, value).unwrap();
        let root = tree.root();
        let proof = tree.proof(&key).unwrap();

        let wrong_value = uint!(999_U256);
        let wrong_proof = MerkleProof::new(key, Some(wrong_value), proof.proof);
        assert!(U256Tree::verify_proof(root, &wrong_proof).is_err());
    }

    #[test]
    fn insertion_order_does_not_affect_root() {
        let values = vec![
            (uint!(1_U256), uint!(100_U256)),
            (uint!(2_U256), uint!(200_U256)),
            (uint!(3_U256), uint!(300_U256)),
        ];

        let mut tree1 = U256Tree::new();
        let mut tree2 = U256Tree::new();

        // Insert in original order.
        for (key, value) in &values {
            tree1.insert(*key, *value).unwrap();
        }

        // Insert in reverse order.
        for (key, value) in values.iter().rev() {
            tree2.insert(*key, *value).unwrap();
        }

        assert_eq!(tree1.root(), tree2.root());
    }

    #[test]
    fn address_tree_works_with_ethereum_addresses() {
        let mut tree = AddressTree::new();
        let addr1 = address!("742d35Cc6635C0532925a3b8D39A2E9bcf2E7570");
        let addr2 = address!("8ba1f109551bD432803012645aac136c0001bC80");
        let value1 = uint!(1000_U256);
        let value2 = uint!(2000_U256);

        tree.insert(addr1, value1).unwrap();
        tree.insert(addr2, value2).unwrap();

        let root = tree.root();
        let proof1 = tree.proof(&addr1).unwrap();
        let proof2 = tree.proof(&addr2).unwrap();

        assert!(AddressTree::verify_proof(root, &proof1).is_ok());
        assert!(AddressTree::verify_proof(root, &proof2).is_ok());
        assert_eq!(proof1.proof.len(), 160); // Address keys have 160 bits.
    }

    #[test]
    fn get_returns_correct_value() {
        let mut tree = U256Tree::new();
        let key = uint!(42_U256);
        let value = uint!(1337_U256);

        assert_eq!(tree.get(&key).unwrap(), None);

        tree.insert(key, value).unwrap();
        assert_eq!(tree.get(&key).unwrap(), Some(&value));
    }

    #[test]
    fn entry_provides_mutable_access() {
        let mut tree = U256Tree::new();
        let key = uint!(42_U256);
        let initial_value = uint!(100_U256);
        let updated_value = uint!(200_U256);

        // Insert via entry.
        tree.entry(key).unwrap().or_insert(initial_value);
        assert_eq!(tree.get(&key).unwrap(), Some(&initial_value));

        // Update via entry.
        *tree.entry(key).unwrap().or_insert(uint!(0_U256)) = updated_value;
        assert_eq!(tree.get(&key).unwrap(), Some(&updated_value));
    }

    #[test]
    fn verify_proof_with_hash_works_correctly() {
        let mut tree = U256Tree::new();
        let key = uint!(123_U256);
        let value = uint!(456_U256);

        tree.insert(key, value).unwrap();
        let root = tree.root();
        let proof = tree.proof(&key).unwrap();
        let leaf_hash = Keccak256::hash(&value);

        assert!(U256Tree::verify_proof_with_hash(root, key, leaf_hash, &proof.proof).is_ok());

        // Verify with wrong hash fails.
        let wrong_hash = Keccak256::hash(&uint!(999_U256));
        assert!(U256Tree::verify_proof_with_hash(root, key, wrong_hash, &proof.proof).is_err());
    }

    #[test]
    fn large_trees_maintain_consistency() {
        let mut tree = U256Tree::new();
        let num_entries = 100;

        // Insert many entries.
        for i in 0..num_entries {
            let key = U256::from((i * 17) % 1000); // Use some spread.
            let value = U256::from(i * 3);
            tree.insert(key, value).unwrap();
        }

        let root = tree.root();

        // Verify all proofs still work.
        for i in 0..num_entries {
            let key = U256::from((i * 17) % 1000);
            let _value = U256::from(i * 3);
            let proof = tree.proof(&key).unwrap();
            assert!(U256Tree::verify_proof(root, &proof).is_ok());
        }
    }

    #[test]
    fn zero_key_and_value_work_correctly() {
        let mut tree = U256Tree::new();
        let zero_key = uint!(0_U256);
        let zero_value = uint!(0_U256);

        tree.insert(zero_key, zero_value).unwrap();
        let root = tree.root();
        let proof = tree.proof(&zero_key).unwrap();

        assert!(U256Tree::verify_proof(root, &proof).is_ok());
        assert_eq!(tree.get(&zero_key).unwrap(), Some(&zero_value));
    }

    #[test]
    fn maximum_u256_key_works() {
        let mut tree = U256Tree::new();
        let max_key = U256::MAX;
        let value = uint!(42_U256);

        tree.insert(max_key, value).unwrap();
        let root = tree.root();
        let proof = tree.proof(&max_key).unwrap();

        assert!(U256Tree::verify_proof(root, &proof).is_ok());
        assert_eq!(proof.proof.len(), 256); // U256 keys have 256 bits.
    }

    #[test]
    fn tree_supports_default_constructor() {
        let mut tree: U256Tree = MerkleStorage::default();
        let mut empty_tree = U256Tree::new();
        assert_eq!(tree.root(), empty_tree.root());
    }

    #[test]
    fn calculate_new_root_works_correctly() {
        let mut tree = U256Tree::new();
        let key1 = uint!(1_U256);
        let value1 = uint!(100_U256);

        // Build initial tree with one value.
        tree.insert(key1, value1).unwrap();
        let old_root = tree.root();

        // Generate proof for the existing key.
        let proof1 = tree.proof(&key1).unwrap();

        let proofs = vec![MerkleProof::new(key1, Some(value1), proof1.proof)];

        // Define new value: update key1.
        let new_value1 = uint!(150_U256);
        let new_values = vec![(key1, new_value1)];

        // Calculate new root using the function.
        let calculated_root = U256Tree::calculate_new_root(old_root, &proofs, &new_values)
            .expect("Should calculate new root successfully");

        // Verify by manually building the expected tree.
        let mut expected_tree = U256Tree::new();
        expected_tree.insert(key1, new_value1).unwrap();
        let expected_root = expected_tree.root();

        assert_eq!(calculated_root, expected_root);
    }

    #[test]
    fn calculate_new_root_multiple_proofs() {
        let mut tree = U256Tree::new();
        let key1 = uint!(1_U256);
        let key2 = uint!(2_U256);
        let value1 = uint!(100_U256);
        let value2 = uint!(200_U256);

        // Build initial tree with two values.
        tree.insert(key1, value1).unwrap();
        tree.insert(key2, value2).unwrap();
        let old_root = tree.root();

        // Generate proofs for both keys.
        let proof1 = tree.proof(&key1).unwrap();
        let proof2 = tree.proof(&key2).unwrap();

        let proofs = vec![
            MerkleProof::new(key1, Some(value1), proof1.proof),
            MerkleProof::new(key2, Some(value2), proof2.proof),
        ];

        // Define new values: update key1, keep key2 same.
        let new_value1 = uint!(150_U256);
        let new_values = vec![(key1, new_value1)];

        // Calculate new root using the function.
        let calculated_root = U256Tree::calculate_new_root(old_root, &proofs, &new_values)
            .expect("Should calculate new root successfully");

        // Verify by manually building the expected tree.
        let mut expected_tree = U256Tree::new();
        expected_tree.insert(key1, new_value1).unwrap();
        expected_tree.insert(key2, value2).unwrap();
        let expected_root = expected_tree.root();

        assert_eq!(calculated_root, expected_root);
    }

    #[test]
    fn calculate_new_root_multiple_updates() {
        let mut tree = U256Tree::new();
        let key1 = uint!(1_U256);
        let key2 = uint!(2_U256);
        let key3 = uint!(3_U256);
        let value1 = uint!(100_U256);
        let value2 = uint!(200_U256);
        let value3 = uint!(300_U256);

        // Build initial tree with three values.
        tree.insert(key1, value1).unwrap();
        tree.insert(key2, value2).unwrap();
        tree.insert(key3, value3).unwrap();
        let old_root = tree.root();

        // Generate proofs for all keys.
        let proof1 = tree.proof(&key1).unwrap();
        let proof2 = tree.proof(&key2).unwrap();
        let proof3 = tree.proof(&key3).unwrap();

        let proofs = vec![
            MerkleProof::new(key1, Some(value1), proof1.proof),
            MerkleProof::new(key2, Some(value2), proof2.proof),
            MerkleProof::new(key3, Some(value3), proof3.proof),
        ];

        // Define new values: update key1 and key3.
        let new_value1 = uint!(150_U256);
        let new_value3 = uint!(350_U256);
        let new_values = vec![(key1, new_value1), (key3, new_value3)];

        // Calculate new root using the function.
        let calculated_root = U256Tree::calculate_new_root(old_root, &proofs, &new_values)
            .expect("Should calculate new root successfully");

        // Verify by manually building the expected tree.
        let mut expected_tree = U256Tree::new();
        expected_tree.insert(key1, new_value1).unwrap();
        expected_tree.insert(key2, value2).unwrap();
        expected_tree.insert(key3, new_value3).unwrap();
        let expected_root = expected_tree.root();

        assert_eq!(calculated_root, expected_root);
    }

    #[test]
    fn calculate_new_root_fails_with_invalid_proof() {
        let mut tree = U256Tree::new();
        let key = uint!(1_U256);
        let value = uint!(100_U256);
        let wrong_value = uint!(999_U256);

        tree.insert(key, value).unwrap();
        let old_root = tree.root();
        let proof = tree.proof(&key).unwrap();

        // Create proof with wrong value.
        let invalid_proofs = vec![MerkleProof::new(key, Some(wrong_value), proof.proof)];

        let new_values = vec![];

        let result = U256Tree::calculate_new_root(old_root, &invalid_proofs, &new_values);
        assert!(result.is_err());
        assert_eq!(result.unwrap_err(), MerkleStorageError::InvalidMerkleProof);
    }

    #[test]
    fn calculate_new_root_fails_when_proof_missing_for_update() {
        let mut tree = U256Tree::new();
        let key_existing = uint!(1_U256);
        let value_existing = uint!(100_U256);

        // Populate tree.
        tree.insert(key_existing, value_existing).unwrap();
        let old_root = tree.root();

        // Prepare a *different* key that we will try to update without providing a proof.
        let key_missing = uint!(2_U256);
        let new_value_missing = uint!(200_U256);

        // Provide a valid proof for the existing key, but none for the missing key.
        let proof_existing = tree.proof(&key_existing).unwrap();
        let proofs =
            vec![MerkleProof::new(key_existing, Some(value_existing), proof_existing.proof)];

        // Attempt to update the missing key – this should fail.
        let new_values = vec![(key_missing, new_value_missing)];

        let result = U256Tree::calculate_new_root(old_root, &proofs, &new_values);
        assert!(result.is_err());
        assert_eq!(result.unwrap_err(), MerkleStorageError::MissingMerkleProofForUpdatedKey);
    }

    #[test]
    fn calculate_new_root_no_changes_returns_same_root() {
        let mut tree = U256Tree::new();
        tree.insert(uint!(5_U256), uint!(55_U256)).unwrap();
        let old_root = tree.root();

        // No proofs, no updates.
        let new_root = U256Tree::calculate_new_root(old_root, &[], &[]).expect("Should succeed");
        assert_eq!(new_root, old_root);
    }

    #[test]
    fn calculate_new_root_same_value_update_keeps_root() {
        let mut tree = U256Tree::new();
        let key = uint!(10_U256);
        let value = uint!(123_U256);
        tree.insert(key, value).unwrap();
        let old_root = tree.root();

        let proof = tree.proof(&key).unwrap();
        let proofs = vec![MerkleProof::new(key, Some(value), proof.proof)];
        // Update to the *same* value.
        let new_values = vec![(key, value)];

        let new_root =
            U256Tree::calculate_new_root(old_root, &proofs, &new_values).expect("Should succeed");
        assert_eq!(new_root, old_root);
    }

    #[test]
    fn calculate_new_root_duplicate_updates_last_value_wins() {
        let mut tree = U256Tree::new();
        let key = uint!(42_U256);
        let original_value = uint!(1_U256);
        tree.insert(key, original_value).unwrap();
        let old_root = tree.root();

        let proof = tree.proof(&key).unwrap();
        let proofs = vec![MerkleProof::new(key, Some(original_value), proof.proof)];

        // Provide duplicate updates – the last one should be applied.
        let new_values = vec![(key, uint!(10_U256)), (key, uint!(20_U256)), (key, uint!(30_U256))];

        let calculated_root =
            U256Tree::calculate_new_root(old_root, &proofs, &new_values).expect("Should succeed");

        // Build expected tree with the *last* value.
        let mut expected_tree = U256Tree::new();
        expected_tree.insert(key, uint!(30_U256)).unwrap();
        let expected_root = expected_tree.root();

        assert_eq!(calculated_root, expected_root);
    }

    #[test]
    fn key_tracking_works_correctly() {
        let mut tree = U256Tree::new();
        let key1 = uint!(1_U256);
        let key2 = uint!(2_U256);
        let key3 = uint!(3_U256);
        let value1 = uint!(100_U256);

        // Initially no keys should be tracked.
        assert!(tree.get_touched_keys().is_empty());

        // Insert operations should track keys as touched.
        tree.insert(key1, value1).unwrap();
        assert!(tree.get_touched_keys().contains(&key1));

        // Tracked get should mark key as touched.
        let _ = tree.get_tracked(&key2);
        assert!(tree.get_touched_keys().contains(&key2));

        // Entry access should mark key as touched.
        let _ = tree.entry(key3);
        assert!(tree.get_touched_keys().contains(&key3));

        // Manual tracking should work.
        let key4 = uint!(4_U256);
        tree.track_touched(&key4);
        assert!(tree.get_touched_keys().contains(&key4));

        // Untracked get should not affect tracking.
        let key5 = uint!(5_U256);
        let _ = tree.get_untracked(&key5);
        assert!(!tree.get_touched_keys().contains(&key5));

        // Clear tracking should reset everything.
        tree.clear_key_tracking();
        assert!(tree.get_touched_keys().is_empty());
    }

    #[test]
    fn calculate_new_root_large_batch_of_updates() {
        // Build a tree with a deterministic but spread-out set of keys.
        let mut tree = U256Tree::new();
        let num_entries = 256; // large enough to hit many branches.

        for i in 0..num_entries {
            let key = U256::from(i * 13 + 7);
            let value = U256::from(i * 17 + 3);
            tree.insert(key, value).unwrap();
        }

        let old_root = tree.root();

        // Prepare proofs for *all* keys and choose every 5th key to update.
        let mut proofs = Vec::new();
        let mut new_values = Vec::new();

        for i in 0..num_entries {
            let key = U256::from(i * 13 + 7);
            let value = *tree.get(&key).unwrap().unwrap();
            let proof = tree.proof(&key).unwrap();
            proofs.push(MerkleProof::new(key, Some(value), proof.proof));

            if i % 5 == 0 {
                // Update selected keys to a new deterministic value.
                let new_value = U256::from(i * 19 + 11);
                new_values.push((key, new_value));
            }
        }

        let calculated_root =
            U256Tree::calculate_new_root(old_root, &proofs, &new_values).expect("Should succeed");

        // Apply the same updates to the original tree and compare roots.
        for (key, new_value) in new_values {
            tree.insert(key, new_value).unwrap();
        }
        let expected_root = tree.root();

        assert_eq!(calculated_root, expected_root);
    }

    // ------------------------------------------------------------------------------------------------.
    // Tests for `calculate_new_root_sparse`.
    // ------------------------------------------------------------------------------------------------.

    use crate::sparse::SparseStorage;
    type U256Sparse = SparseStorage<U256, U256>;
    type AddressSparse = SparseStorage<Address, U256>;

    #[test]
    fn calculate_new_root_sparse_single_update() {
        // Build a tree with one entry so we have a non-empty root.
        let mut tree = U256Tree::new();
        let key = uint!(1_U256);
        let original_value = uint!(100_U256);
        tree.insert(key, original_value).unwrap();
        let old_root = tree.root();

        // Generate proof for the existing key.
        let proof = tree.proof(&key).expect("Proof generation must succeed.");
        let proofs = vec![MerkleProof::new(key, Some(original_value), proof.proof)];

        // Prepare sparse updates that change the value for the key.
        let new_value = uint!(150_U256);
        let mut updates = U256Sparse::new();
        updates.recover::<Keccak256>(old_root, &proofs).unwrap();
        updates.insert(key, new_value).unwrap();

        // Calculate the new root via the sparse method.
        let calculated_root = U256Tree::calculate_new_root_sparse(old_root, &proofs, &updates)
            .expect("calculate_new_root_sparse should succeed.");

        // Manually apply the same update to the tree and compare roots.
        tree.insert(key, new_value).unwrap();
        let expected_root = tree.root();

        assert_eq!(calculated_root, expected_root);
    }

    #[test]
    fn calculate_new_root_sparse_insertion_of_new_key() {
        // Start with an empty tree.
        let mut tree = U256Tree::new();
        let old_root = tree.root();

        // Choose a key that is not yet present.
        let key = uint!(42_U256);
        let new_value = uint!(1337_U256);

        // Even though the key is absent, we can still create a proof for it (value == None).
        let proof = tree.proof(&key).expect("Proof generation for absent key must succeed.");
        let proofs = vec![MerkleProof::new(key, None, proof.proof)];

        // Prepare updates that insert the new value.
        let mut updates = U256Sparse::new();
        updates.recover::<Keccak256>(old_root, &proofs).unwrap();
        updates.insert(key, new_value).unwrap();

        // Calculate the new root.
        let calculated_root = U256Tree::calculate_new_root_sparse(old_root, &proofs, &updates)
            .expect("calculate_new_root_sparse should succeed.");

        // Verify by applying the same insertion to the original tree.
        tree.insert(key, new_value).unwrap();
        let expected_root = tree.root();

        assert_eq!(calculated_root, expected_root);
    }

    #[test]
    fn calculate_new_root_sparse_multiple_updates() {
        // Build initial tree with three keys.
        let mut tree = U256Tree::new();
        let key1 = uint!(1_U256);
        let key2 = uint!(2_U256);
        let key3 = uint!(3_U256);
        let value1 = uint!(10_U256);
        let value2 = uint!(20_U256);
        let value3 = uint!(30_U256);
        tree.insert(key1, value1).unwrap();
        tree.insert(key2, value2).unwrap();
        tree.insert(key3, value3).unwrap();
        let old_root = tree.root();

        // Generate proofs for all keys.
        let proof1 = tree.proof(&key1).unwrap();
        let proof2 = tree.proof(&key2).unwrap();
        let proof3 = tree.proof(&key3).unwrap();
        let proofs = vec![
            MerkleProof::new(key1, Some(value1), proof1.proof),
            MerkleProof::new(key2, Some(value2), proof2.proof),
            MerkleProof::new(key3, Some(value3), proof3.proof),
        ];

        // Prepare updates: modify key1 and key3.
        let new_value1 = uint!(100_U256);
        let new_value3 = uint!(300_U256);
        let mut updates = U256Sparse::new();
        updates.recover::<Keccak256>(old_root, &proofs).unwrap();
        updates.insert(key1, new_value1).unwrap();
        updates.insert(key3, new_value3).unwrap();

        // Calculate the new root.
        let calculated_root = U256Tree::calculate_new_root_sparse(old_root, &proofs, &updates)
            .expect("calculate_new_root_sparse should succeed.");

        // Apply same updates directly and compare.
        tree.insert(key1, new_value1).unwrap();
        tree.insert(key3, new_value3).unwrap();
        let expected_root = tree.root();

        assert_eq!(calculated_root, expected_root);
    }

    #[test]
    fn calculate_new_root_sparse_no_changes_returns_same_root() {
        let mut tree = U256Tree::new();
        tree.insert(uint!(7_U256), uint!(70_U256)).unwrap();
        let old_root = tree.root();

        // Empty proofs and updates should yield identical root.
        let empty_updates: U256Sparse = U256Sparse::new();
        let proofs: Vec<MerkleProof<U256, U256, Keccak256>> = Vec::new();
        let new_root = U256Tree::calculate_new_root_sparse(old_root, &proofs, &empty_updates)
            .expect("Should succeed.");
        assert_eq!(new_root, old_root);
    }

    #[test]
    fn calculate_new_root_sparse_address_keys() {
        // Use address keys to exercise the 160-bit variant.
        let mut tree: MerkleStorage<Address, U256> = MerkleStorage::new();
        let mut updates: AddressSparse = AddressSparse::new();

        let addr1 = address!("1111111111111111111111111111111111111111");
        let addr2 = address!("2222222222222222222222222222222222222222");
        let val1 = uint!(1_U256);
        let val2 = uint!(2_U256);
        tree.insert(addr1, val1).unwrap();
        tree.insert(addr2, val2).unwrap();
        let old_root = tree.root();

        // Proofs for both addresses.
        let proof1 = tree.proof(&addr1).unwrap();
        let proof2 = tree.proof(&addr2).unwrap();
        let proofs = vec![
            MerkleProof::new(addr1, Some(val1), proof1.proof),
            MerkleProof::new(addr2, Some(val2), proof2.proof),
        ];

        // Update addr2 only.
        let new_val2 = uint!(20_U256);
        updates.recover::<Keccak256>(old_root, &proofs).unwrap();
        updates.insert(addr2, new_val2).unwrap();

        // Calculate new root via sparse method.
        let calculated_root =
            MerkleStorage::<Address, U256>::calculate_new_root_sparse(old_root, &proofs, &updates)
                .expect("Should succeed.");

        // Apply update directly and compare.
        tree.insert(addr2, new_val2).unwrap();
        let expected_root = tree.root();
        assert_eq!(calculated_root, expected_root);
    }

    #[test]
    fn calculate_new_root_sparse_large_batch_of_updates() {
        // Construct a tree with a spread-out set of keys.
        let mut tree = U256Tree::new();
        let num_entries = 128;
        for i in 0..num_entries {
            let key = U256::from(i * 31 + 9);
            let value = U256::from(i * 17 + 5);
            tree.insert(key, value).unwrap();
        }
        let old_root = tree.root();

        // Generate proofs for all keys and build updates for every 6th key.
        let mut proofs: Vec<MerkleProof<U256, U256, Keccak256>> = Vec::new();
        let mut updates = U256Sparse::new();
        for i in 0..num_entries {
            let key = U256::from(i * 31 + 9);
            let value = *tree.get(&key).unwrap().unwrap();
            let proof = tree.proof(&key).unwrap();
            proofs.push(MerkleProof::new(key, Some(value), proof.proof));
        }

        // Recover the updates from the proofs.
        updates.recover::<Keccak256>(old_root, &proofs).unwrap();

        // Apply the updates to the sparse store.
        for i in 0..num_entries {
            if i % 6 == 0 {
                let key = U256::from(i * 31 + 9);
                let new_value = U256::from(i * 29 + 7);
                updates.insert(key, new_value).unwrap();
            }
        }

        // Calculate the new root.
        let calculated_root = U256Tree::calculate_new_root_sparse(old_root, &proofs, &updates)
            .expect("calculate_new_root_sparse should succeed.");

        // Apply identical updates directly and compare.
        for (index, new_val) in updates.iter_raw() {
            tree.insert(*index, *new_val).unwrap();
        }
        let expected_root = tree.root();
        assert_eq!(calculated_root, expected_root);
    }
}
