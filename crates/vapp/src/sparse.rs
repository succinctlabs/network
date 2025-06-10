//! Sparse Merkelized Storage.
//!
//! This module contains implementations of the [`SparseStorage`] data structure, which is used to
//! store and retrieve data inside the vApp while keeping only the used leaves  

use std::collections::{btree_map::Entry, BTreeMap};

use alloy_primitives::{B256, U256};
use serde::{Deserialize, Serialize};
use thiserror::Error;

use crate::{
    merkle::{MerkleProof, MerkleStorage, MerkleTreeHasher},
    storage::{Storage, StorageKey, StorageValue},
};

/// A sparse storage implementation backed by a `BTreeMap`.
///
/// Similar to `MerkleStore`, this uses U256 indices internally and converts keys using the
/// [`crate::storage::StorageKey::index()`] method for efficient storage.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SparseStorage<K: StorageKey, V: StorageValue> {
    inner: BTreeMap<U256, V>,
    _key: std::marker::PhantomData<K>,
}

/// Errors that can occur during sparse storage operations.
#[derive(Debug, Error)]
#[allow(missing_docs)]
pub enum SparseStorageError {
    #[error("missing proof for stored value: {index}")]
    MissingProofForStoredValue { index: U256 },

    #[error("proof value doesn't match stored value: {index}")]
    ProofValueMismatch { index: U256 },

    #[error("invalid proof for stored value: {index}")]
    InvalidProofForStoredValue { index: U256 },

    #[error("proof for non-stored key with non-empty value: {index}")]
    ProofForNonStoredKeyWithValue { index: U256 },

    #[error("verification failed")]
    VerificationFailed,
}

impl<K: StorageKey, V: StorageValue> Storage<K, V> for SparseStorage<K, V> {
    fn new() -> Self {
        Self { inner: BTreeMap::new(), _key: std::marker::PhantomData }
    }

    fn insert(&mut self, key: K, value: V) {
        let index = key.index();
        self.inner.insert(index, value);
    }

    fn remove(&mut self, key: K) {
        let index = key.index();
        self.inner.remove(&index);
    }

    fn entry(&mut self, key: K) -> Entry<U256, V> {
        let index = key.index();
        self.inner.entry(index)
    }

    fn get(&self, key: &K) -> Option<&V> {
        let index = key.index();
        self.inner.get(&index)
    }

    fn get_mut(&mut self, key: &K) -> Option<&mut V> {
        let index = key.index();
        self.inner.get_mut(&index)
    }
}

impl<K: StorageKey, V: StorageValue> SparseStorage<K, V> {
    /// Check if the storage is empty.
    #[must_use] pub fn is_empty(&self) -> bool {
        self.inner.is_empty()
    }

    /// Iterate over the raw key-value pairs (returns U256 indices).
    pub fn iter_raw(&self) -> impl Iterator<Item = (&U256, &V)> {
        self.inner.iter()
    }
}

impl<K: StorageKey, V: StorageValue + PartialEq> SparseStorage<K, V> {
    /// Verify the state of the sparse store using merkle proofs against a given root.
    ///
    /// This function checks that all values currently stored in the sparse store
    /// are consistent with the provided merkle proofs and verify against the given root.
    ///
    /// # Arguments
    /// * `root` - The merkle root to verify against
    /// * `proofs` - A slice of merkle proofs for the stored values
    ///
    /// # Returns
    /// `Ok(())` if all stored values have valid proofs that verify against the root,
    /// `Err(SparseStorageError)` if verification fails
    pub fn verify<H: MerkleTreeHasher>(
        &self,
        root: B256,
        proofs: &[MerkleProof<K, V, H>],
    ) -> Result<(), SparseStorageError> {
        // Create a map for quick proof lookup.
        let proof_map: BTreeMap<U256, &MerkleProof<K, V, H>> =
            proofs.iter().map(|proof| (proof.key.index(), proof)).collect();

        // Verify that we have a proof for every stored value.
        for (index, value) in &self.inner {
            let Some(proof) = proof_map.get(index) else {
                return Err(SparseStorageError::MissingProofForStoredValue { index: *index });
            };

            // Check that the proof's value matches what we have stored.
            if proof.value.as_ref() != Some(value) {
                return Err(SparseStorageError::ProofValueMismatch { index: *index });
            }

            // Verify the proof for this key-value pair.
            if MerkleStorage::<K, V, H>::verify_proof(root, proof).is_err() {
                return Err(SparseStorageError::InvalidProofForStoredValue { index: *index });
            }
        }

        // Verify that we don't have proofs carrying a non-empty value for keys that aren't stored.
        for proof in proofs {
            let index = proof.key.index();
            if !self.inner.contains_key(&index) && proof.value.is_some() {
                return Err(SparseStorageError::ProofForNonStoredKeyWithValue { index });
            }
        }

        Ok(())
    }
}

impl<K: StorageKey, V: StorageValue> Default for SparseStorage<K, V> {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::merkle::MerkleStorage;
    use alloy_primitives::{uint, Address, Keccak256, U256};

    type U256Tree = MerkleStorage<U256, U256>;
    type U256SparseStore = SparseStorage<U256, U256>;

    #[test]
    fn verify_empty_store_succeeds() {
        let sparse_store = U256SparseStore::new();
        let empty_proofs: Vec<MerkleProof<U256, U256, Keccak256>> = vec![];

        // Any root should work for empty store with no proofs.
        let arbitrary_root = B256::from([1u8; 32]);
        assert!(sparse_store.verify::<Keccak256>(arbitrary_root, &empty_proofs).is_ok());
    }

    #[test]
    fn verify_single_value_succeeds() {
        let mut merkle_tree = U256Tree::new();
        let mut sparse_store = U256SparseStore::new();

        let key = uint!(42_U256);
        let value = uint!(1337_U256);

        // Insert into both stores.
        merkle_tree.insert(key, value);
        sparse_store.insert(key, value);

        // Get root and proof from merkle tree.
        let root = merkle_tree.root();
        let proof = merkle_tree.proof(&key);

        let proofs = vec![MerkleProof::new(key, Some(value), proof.unwrap().proof)];

        // Verification should succeed.
        assert!(sparse_store.verify::<Keccak256>(root, &proofs).is_ok());
    }

    #[test]
    fn verify_multiple_values_succeeds() {
        let mut merkle_tree = U256Tree::new();
        let mut sparse_store = U256SparseStore::new();

        let key1 = uint!(1_U256);
        let key2 = uint!(2_U256);
        let key3 = uint!(100_U256);
        let value1 = uint!(10_U256);
        let value2 = uint!(20_U256);
        let value3 = uint!(300_U256);

        // Insert into both stores.
        merkle_tree.insert(key1, value1);
        merkle_tree.insert(key2, value2);
        merkle_tree.insert(key3, value3);
        sparse_store.insert(key1, value1);
        sparse_store.insert(key2, value2);
        sparse_store.insert(key3, value3);

        // Get root and proofs from merkle tree.
        let root = merkle_tree.root();
        let proof1 = merkle_tree.proof(&key1);
        let proof2 = merkle_tree.proof(&key2);
        let proof3 = merkle_tree.proof(&key3);

        let proofs = vec![
            MerkleProof::new(key1, Some(value1), proof1.unwrap().proof),
            MerkleProof::new(key2, Some(value2), proof2.unwrap().proof),
            MerkleProof::new(key3, Some(value3), proof3.unwrap().proof),
        ];

        // Verification should succeed.
        assert!(sparse_store.verify::<Keccak256>(root, &proofs).is_ok());
    }

    #[test]
    fn verify_fails_with_wrong_root() {
        let mut merkle_tree = U256Tree::new();
        let mut sparse_store = U256SparseStore::new();

        let key = uint!(42_U256);
        let value = uint!(1337_U256);

        // Insert into both stores.
        merkle_tree.insert(key, value);
        sparse_store.insert(key, value);

        // Get proof from merkle tree but use wrong root.
        let proof = merkle_tree.proof(&key);
        let wrong_root = B256::from([
            0xde, 0xad, 0xbe, 0xef, 0xde, 0xad, 0xbe, 0xef, 0xde, 0xad, 0xbe, 0xef, 0xde, 0xad,
            0xbe, 0xef, 0xde, 0xad, 0xbe, 0xef, 0xde, 0xad, 0xbe, 0xef, 0xde, 0xad, 0xbe, 0xef,
            0xde, 0xad, 0xbe, 0xef,
        ]);

        let proofs = vec![MerkleProof::new(key, Some(value), proof.unwrap().proof)];

        // Verification should fail.
        assert!(sparse_store.verify::<Keccak256>(wrong_root, &proofs).is_err());
    }

    #[test]
    fn verify_fails_with_wrong_value() {
        let mut merkle_tree = U256Tree::new();
        let mut sparse_store = U256SparseStore::new();

        let key = uint!(42_U256);
        let correct_value = uint!(1337_U256);
        let wrong_value = uint!(999_U256);

        // Insert correct value into merkle tree, wrong value into sparse store.
        merkle_tree.insert(key, correct_value);
        sparse_store.insert(key, wrong_value);

        // Get root and proof from merkle tree.
        let root = merkle_tree.root();
        let proof = merkle_tree.proof(&key);

        let proofs = vec![MerkleProof::new(key, Some(correct_value), proof.unwrap().proof)];

        // Verification should fail because sparse store has wrong value.
        assert!(sparse_store.verify::<Keccak256>(root, &proofs).is_err());
    }

    #[test]
    fn verify_fails_with_missing_proof() {
        let mut sparse_store = U256SparseStore::new();

        let key1 = uint!(1_U256);
        let key2 = uint!(2_U256);
        let value1 = uint!(10_U256);
        let value2 = uint!(20_U256);

        // Insert both values into sparse store.
        sparse_store.insert(key1, value1);
        sparse_store.insert(key2, value2);

        // Only provide proof for one key.
        let mut merkle_tree = U256Tree::new();
        merkle_tree.insert(key1, value1);
        merkle_tree.insert(key2, value2);
        let root = merkle_tree.root();
        let proof1 = merkle_tree.proof(&key1);

        let proofs = vec![MerkleProof::new(key1, Some(value1), proof1.unwrap().proof)]; // Missing proof for key2.

        // Verification should fail.
        assert!(sparse_store.verify::<Keccak256>(root, &proofs).is_err());
    }

    #[test]
    fn verify_fails_with_extra_proof() {
        let mut merkle_tree = U256Tree::new();
        let mut sparse_store = U256SparseStore::new();

        let key1 = uint!(1_U256);
        let key2 = uint!(2_U256);
        let value1 = uint!(10_U256);
        let value2 = uint!(20_U256);

        // Insert both values into merkle tree.
        merkle_tree.insert(key1, value1);
        merkle_tree.insert(key2, value2);

        // Only insert one value into sparse store.
        sparse_store.insert(key1, value1);

        // Provide proofs for both keys.
        let root = merkle_tree.root();
        let proof1 = merkle_tree.proof(&key1);
        let proof2 = merkle_tree.proof(&key2);

        let proofs = vec![
            MerkleProof::new(key1, Some(value1), proof1.unwrap().proof),
            MerkleProof::new(key2, Some(value2), proof2.unwrap().proof), // Extra proof for key2.
        ];

        // Verification should fail.
        assert!(sparse_store.verify::<Keccak256>(root, &proofs).is_err());
    }

    #[test]
    fn verify_fails_with_wrong_proof() {
        let mut merkle_tree = U256Tree::new();
        let mut sparse_store = U256SparseStore::new();

        let key1 = uint!(1_U256);
        let key2 = uint!(2_U256);
        let value1 = uint!(10_U256);
        let value2 = uint!(20_U256);

        // Insert values into both stores.
        merkle_tree.insert(key1, value1);
        merkle_tree.insert(key2, value2);
        sparse_store.insert(key1, value1);
        sparse_store.insert(key2, value2);

        // Get root and proofs.
        let root = merkle_tree.root();
        let proof1 = merkle_tree.proof(&key1);
        let proof2 = merkle_tree.proof(&key2);

        // Swap the proofs (provide wrong proof for each key).
        let proofs = vec![
            MerkleProof::new(key1, Some(value1), proof2.unwrap().proof),
            MerkleProof::new(key2, Some(value2), proof1.unwrap().proof),
        ];

        // Verification should fail.
        assert!(sparse_store.verify::<Keccak256>(root, &proofs).is_err());
    }

    #[test]
    fn verify_works_with_address_keys() {
        let mut merkle_tree: MerkleStorage<Address, U256> = MerkleStorage::new();
        let mut sparse_store: SparseStorage<Address, U256> = SparseStorage::new();

        let addr1 = Address::from([1u8; 20]);
        let addr2 = Address::from([2u8; 20]);
        let value1 = uint!(100_U256);
        let value2 = uint!(200_U256);

        // Insert into both stores.
        merkle_tree.insert(addr1, value1);
        merkle_tree.insert(addr2, value2);
        sparse_store.insert(addr1, value1);
        sparse_store.insert(addr2, value2);

        // Get root and proofs.
        let root = merkle_tree.root();
        let proof1 = merkle_tree.proof(&addr1);
        let proof2 = merkle_tree.proof(&addr2);

        let proofs = vec![
            MerkleProof::new(addr1, Some(value1), proof1.unwrap().proof),
            MerkleProof::new(addr2, Some(value2), proof2.unwrap().proof),
        ];

        // Verification should succeed.
        assert!(sparse_store.verify::<Keccak256>(root, &proofs).is_ok());
    }

    #[test]
    fn verify_large_store_succeeds() {
        let mut merkle_tree = U256Tree::new();
        let mut sparse_store = U256SparseStore::new();

        let num_entries = 50;
        let mut keys_values = Vec::new();

        // Insert many entries into both stores.
        for i in 0..num_entries {
            let key = U256::from(i * 13 + 7); // Use some spread.
            let value = U256::from(i * 17 + 3);
            keys_values.push((key, value));

            merkle_tree.insert(key, value);
            sparse_store.insert(key, value);
        }

        // Get root and all proofs.
        let root = merkle_tree.root();
        let proofs: Vec<MerkleProof<U256, U256, Keccak256>> = keys_values
            .iter()
            .map(|(key, value)| {
                MerkleProof::new(*key, Some(*value), merkle_tree.proof(key).unwrap().proof)
            })
            .collect();

        // Verification should succeed.
        assert!(sparse_store.verify::<Keccak256>(root, &proofs).is_ok());
    }
}
