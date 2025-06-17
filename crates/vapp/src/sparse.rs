//! Sparse Merkelized Storage.
//!
//! This module contains implementations of the [`SparseStorage`] data structure, which is used to
//! store and retrieve data inside the vApp while keeping only the used leaves  

use std::{
    collections::{btree_map::Entry, BTreeMap, BTreeSet},
    marker::PhantomData,
};

use alloy_primitives::{B256, U256};
use serde::{Deserialize, Serialize};
use thiserror::Error;

use crate::{
    merkle::{MerkleProof, MerkleStorage, MerkleTreeHasher},
    storage::{Storage, StorageError, StorageKey, StorageValue},
};

/// A sparse storage implementation backed by a `BTreeMap`.
///
/// Similar to `MerkleStore`, this uses U256 indices internally and converts keys using the
/// [`crate::storage::StorageKey::index()`] method for efficient storage.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SparseStorage<K: StorageKey, V: StorageValue> {
    inner: BTreeMap<U256, V>,
    witnessed_keys: BTreeSet<U256>,
    _key: PhantomData<K>,
}

/// Errors that can occur during sparse storage operations.
#[derive(Debug, Error, PartialEq)]
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

    #[error("duplicate proof supplied for key: {index}")]
    DuplicateProof { index: U256 },

    #[error("proof supplied for key that is not stored: {index}")]
    UnusedProof { index: U256 },
}

impl<K: StorageKey, V: StorageValue> Storage<K, V> for SparseStorage<K, V> {
    fn new() -> Self {
        Self { inner: BTreeMap::new(), witnessed_keys: BTreeSet::new(), _key: PhantomData }
    }

    fn insert(&mut self, key: K, value: V) -> Result<(), StorageError> {
        let index = key.index();
        if !self.witnessed_keys.contains(&index) {
            return Err(StorageError::KeyNotAllowed);
        }

        self.inner.insert(index, value);
        Ok(())
    }

    fn entry(&mut self, key: K) -> Result<Entry<U256, V>, StorageError> {
        let index = key.index();
        if !self.witnessed_keys.contains(&index) {
            return Err(StorageError::KeyNotAllowed);
        }

        Ok(self.inner.entry(index))
    }

    fn get(&mut self, key: &K) -> Result<Option<&V>, StorageError> {
        let index = key.index();
        if !self.witnessed_keys.contains(&index) {
            return Err(StorageError::KeyNotAllowed);
        }

        Ok(self.inner.get(&index))
    }

    fn get_mut(&mut self, key: &K) -> Result<Option<&mut V>, StorageError> {
        let index = key.index();
        if !self.witnessed_keys.contains(&index) {
            return Err(StorageError::KeyNotAllowed);
        }

        Ok(self.inner.get_mut(&index))
    }
}

impl<K: StorageKey, V: StorageValue> SparseStorage<K, V> {
    /// Check if the storage is empty.
    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.inner.is_empty()
    }

    /// Iterate over the raw key-value pairs (returns U256 indices).
    pub fn iter_raw(&self) -> impl Iterator<Item = (&U256, &V)> {
        self.inner.iter().filter(|(key, _)| self.witnessed_keys.contains(key))
    }
}

impl<K: StorageKey, V: StorageValue + PartialEq> SparseStorage<K, V> {
    /// Recovers the state of the sparse store using merkle proofs against a given root.
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
    pub fn recover<H: MerkleTreeHasher>(
        &mut self,
        root: B256,
        proofs: &[MerkleProof<K, V, H>],
    ) -> Result<(), SparseStorageError> {
        self.inner.clear();
        self.witnessed_keys.clear();

        for proof in proofs {
            // Add the key to the set of witnessed keys.
            //
            // We enforce that only witnessed keys can be used with the [`Storage`] trait.
            if self.witnessed_keys.contains(&proof.key.index()) {
                return Err(SparseStorageError::DuplicateProof { index: proof.key.index() });
            }
            self.witnessed_keys.insert(proof.key.index());

            // Verify the proof against the root.
            if MerkleStorage::<K, V, H>::verify_proof(root, proof).is_err() {
                return Err(SparseStorageError::VerificationFailed);
            }

            // Write the value to the sparse store.
            if let Some(value) = &proof.value {
                self.inner.insert(proof.key.index(), value.clone());
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
        let mut sparse_store = U256SparseStore::new();
        let empty_proofs: Vec<MerkleProof<U256, U256, Keccak256>> = vec![];

        // Any root should work for empty store with no proofs.
        let arbitrary_root = B256::from([1u8; 32]);
        assert!(sparse_store.recover::<Keccak256>(arbitrary_root, &empty_proofs).is_ok());
    }

    #[test]
    fn verify_single_value_succeeds() {
        let mut sparse_store = U256SparseStore::new();
        let mut merkle_tree = U256Tree::new();

        let key = uint!(42_U256);
        let value = uint!(1337_U256);

        // Insert into the merkle tree.
        merkle_tree.insert(key, value).unwrap();

        // Get root and proof from merkle tree.
        let root = merkle_tree.root();
        let proof = merkle_tree.proof(&key);

        let proofs = vec![MerkleProof::new(key, Some(value), proof.unwrap().proof)];

        // Verification should succeed.
        assert!(sparse_store.recover::<Keccak256>(root, &proofs).is_ok());
    }

    #[test]
    fn verify_multiple_values_succeeds() {
        let mut sparse_store = U256SparseStore::new();
        let mut merkle_tree = U256Tree::new();

        let key1 = uint!(1_U256);
        let key2 = uint!(2_U256);
        let key3 = uint!(100_U256);
        let value1 = uint!(10_U256);
        let value2 = uint!(20_U256);
        let value3 = uint!(300_U256);

        // Insert into both stores.
        merkle_tree.insert(key1, value1).unwrap();
        merkle_tree.insert(key2, value2).unwrap();
        merkle_tree.insert(key3, value3).unwrap();

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
        assert!(sparse_store.recover::<Keccak256>(root, &proofs).is_ok());
    }

    #[test]
    fn verify_fails_with_wrong_root() {
        let mut sparse_store = U256SparseStore::new();
        let mut merkle_tree = U256Tree::new();

        let key = uint!(42_U256);
        let value = uint!(1337_U256);

        // Insert into both stores.
        merkle_tree.insert(key, value).unwrap();

        // Get proof from merkle tree but use wrong root.
        let proof = merkle_tree.proof(&key);
        let wrong_root = B256::from([
            0xde, 0xad, 0xbe, 0xef, 0xde, 0xad, 0xbe, 0xef, 0xde, 0xad, 0xbe, 0xef, 0xde, 0xad,
            0xbe, 0xef, 0xde, 0xad, 0xbe, 0xef, 0xde, 0xad, 0xbe, 0xef, 0xde, 0xad, 0xbe, 0xef,
            0xde, 0xad, 0xbe, 0xef,
        ]);

        let proofs = vec![MerkleProof::new(key, Some(value), proof.unwrap().proof)];

        // Verification should fail.
        assert!(sparse_store.recover::<Keccak256>(wrong_root, &proofs).is_err());
    }

    #[test]
    fn verify_fails_with_wrong_proof() {
        let mut sparse_store = U256SparseStore::new();
        let mut merkle_tree = U256Tree::new();

        let key1 = uint!(1_U256);
        let key2 = uint!(2_U256);
        let value1 = uint!(10_U256);
        let value2 = uint!(20_U256);

        // Insert values into both stores.
        merkle_tree.insert(key1, value1).unwrap();
        merkle_tree.insert(key2, value2).unwrap();

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
        assert!(sparse_store.recover::<Keccak256>(root, &proofs).is_err());
    }

    #[test]
    fn verify_works_with_address_keys() {
        let mut sparse_store = SparseStorage::<Address, U256>::new();
        let mut merkle_tree: MerkleStorage<Address, U256> = MerkleStorage::new();

        let addr1 = Address::from([1u8; 20]);
        let addr2 = Address::from([2u8; 20]);
        let value1 = uint!(100_U256);
        let value2 = uint!(200_U256);

        // Insert into both stores.
        merkle_tree.insert(addr1, value1).unwrap();
        merkle_tree.insert(addr2, value2).unwrap();

        // Get root and proofs.
        let root = merkle_tree.root();
        let proof1 = merkle_tree.proof(&addr1);
        let proof2 = merkle_tree.proof(&addr2);

        let proofs = vec![
            MerkleProof::new(addr1, Some(value1), proof1.unwrap().proof),
            MerkleProof::new(addr2, Some(value2), proof2.unwrap().proof),
        ];

        // Verification should succeed.
        assert!(sparse_store.recover::<Keccak256>(root, &proofs).is_ok());
    }

    #[test]
    fn verify_large_store_succeeds() {
        let mut sparse_store = U256SparseStore::new();
        let mut merkle_tree = U256Tree::new();

        let num_entries = 50;
        let mut keys_values = Vec::new();

        // Insert many entries into both stores.
        for i in 0..num_entries {
            let key = U256::from(i * 13 + 7); // Use some spread.
            let value = U256::from(i * 17 + 3);
            keys_values.push((key, value));

            merkle_tree.insert(key, value).unwrap();
        }

        // Get root and all proofs.
        let root = merkle_tree.root();
        let proofs: Vec<MerkleProof<U256, U256, Keccak256>> =
            keys_values.iter().map(|(key, _)| merkle_tree.proof(key).unwrap()).collect();

        // Verification should succeed.
        assert!(sparse_store.recover::<Keccak256>(root, &proofs).is_ok());
    }

    // Tests for stricter proof validation.

    #[test]
    fn verify_fails_with_duplicate_proofs() {
        let mut sparse_store = U256SparseStore::new();
        let mut merkle_tree = U256Tree::new();

        let key = uint!(42_U256);
        let value = uint!(7_U256);

        merkle_tree.insert(key, value).unwrap();

        let root = merkle_tree.root();
        let proof_data = merkle_tree.proof(&key).unwrap();

        // Create duplicate proofs for the same key.
        let proofs = vec![proof_data.clone(), proof_data];

        let result = sparse_store.recover::<Keccak256>(root, &proofs);
        assert!(
            matches!(result, Err(SparseStorageError::DuplicateProof { index }) if index == key)
        );
    }

    #[test]
    fn verify_non_inclusion_proof_succeeds() {
        let mut sparse_store = U256SparseStore::new();
        let mut merkle_tree = U256Tree::new();

        let key_stored = uint!(1_U256);
        let value_stored = uint!(100_U256);
        merkle_tree.insert(key_stored, value_stored).unwrap();

        // Create a key that is not stored in the sparse store.
        let key_unused = uint!(999_U256);
        let root = merkle_tree.root();

        // Proof for stored key.
        let proof_stored = merkle_tree.proof(&key_stored).unwrap();

        // Create proof for the unused key (non-inclusion proof).
        let proof_unused = merkle_tree.proof(&key_unused).unwrap();

        let proofs = vec![proof_stored, proof_unused];

        // Verification should now succeed because non-inclusion proofs are accepted.
        assert!(sparse_store.recover::<Keccak256>(root, &proofs).is_ok());
    }
}
