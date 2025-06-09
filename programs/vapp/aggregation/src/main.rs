#![no_main]
sp1_zkvm::entrypoint!(main);

use alloy_sol_types::SolType;
use sha2::{Digest, Sha256};
use sp1_zkvm::lib::verify::verify_sp1_proof;
use spn_vapp::sol::StepPublicValues;

pub fn main() {
    // Read the STF verification key.
    //
    // TODO(jtguibas): have this as a constant in the program.
    let stf_vkey = sp1_zkvm::io::read::<[u32; 8]>();

    // Read the public values from each STF proof.
    let public_values = sp1_zkvm::io::read::<Vec<Vec<u8>>>();

    // Ensure we have at least one proof to aggregate.
    assert!(!public_values.is_empty(), "no proofs to aggregate");

    // Verify all STF proofs.
    for public_value in &public_values {
        let public_values_digest = Sha256::digest(public_value);
        verify_sp1_proof(&stf_vkey, &public_values_digest.into());
    }

    // Decode all StepPublicValues and validate state transitions.
    let mut decoded_steps: Vec<StepPublicValues> = Vec::new();
    for public_value in &public_values {
        let step = StepPublicValues::abi_decode(public_value, false)
            .expect("failed to decode StepPublicValues");
        decoded_steps.push(step);
    }

    // Validate sequential consistency.
    for i in 0..decoded_steps.len() - 1 {
        let current = &decoded_steps[i];
        let next = &decoded_steps[i + 1];

        // Check state root consistency.
        assert_eq!(
            current.newRoot,
            next.oldRoot,
            "state root inconsistency between steps {} and {}",
            i,
            i + 1
        );

        // Check timestamp ordering.
        assert!(
            current.timestamp <= next.timestamp,
            "timestamp ordering violation between steps {} and {}",
            i,
            i + 1
        );
    }

    // Extract old and new roots.
    let old_root = decoded_steps[0].oldRoot;
    let new_root = decoded_steps.last().unwrap().newRoot;

    // Aggregate all receipts from all steps.
    let mut all_receipts = Vec::new();
    for step in &decoded_steps {
        all_receipts.extend_from_slice(&step.receipts);
    }

    // Create aggregated public values using StepPublicValues.
    let output = StepPublicValues {
        oldRoot: old_root,
        newRoot: new_root,
        timestamp: decoded_steps.last().unwrap().timestamp,
        receipts: all_receipts,
    };

    let encoded = StepPublicValues::abi_encode(&output);
    sp1_zkvm::io::commit_slice(&encoded);
}
