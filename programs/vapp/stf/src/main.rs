#![no_main]
sp1_zkvm::entrypoint!(main);

use alloy_primitives::Keccak256;
use alloy_sol_types::SolType;
use sp1_zkvm::lib::verify::verify_sp1_proof;
use spn_vapp::{
    errors::VAppError,
    merkle::MerkleStorage,
    sol::StepPublicValues,
    verifier::{VAppVerifier, VAppVerifierError},
    VAppProgramInput,
};

#[derive(Debug, Clone, Default)]
pub struct SP1RecursiveVerifier;

impl VAppVerifier for SP1RecursiveVerifier {
    fn verify(
        &self,
        vk_digest_array: [u32; 8],
        pv_digest_array: [u8; 32],
    ) -> Result<(), VAppVerifierError> {
        verify_sp1_proof(&vk_digest_array, &pv_digest_array);
        Ok(())
    }
}

pub fn main() {
    // Read the program input.
    println!("cycle-tracker-report-start: read input");
    let input = sp1_zkvm::io::read::<VAppProgramInput>();
    println!("cycle-tracker-report-end: read input");

    // Check that the state root is consistent with the state.
    let mut state = input.state;
    assert_eq!(
        state.root::<Keccak256>(input.accounts_root, input.requests_root),
        input.root,
        "state root mismatch"
    );

    // Verify the roots against the proofs.
    println!("cycle-tracker-report-start: verify accounts root");
    state
        .accounts
        .verify::<Keccak256>(input.accounts_root, &input.account_proofs)
        .expect("accounts root mismatch");
    println!("cycle-tracker-report-end: verify accounts root");

    println!("cycle-tracker-report-start: verify requests root");
    state
        .requests
        .verify::<Keccak256>(input.requests_root, &input.request_proofs)
        .expect("requests root mismatch");
    println!("cycle-tracker-report-end: verify requests root");

    // Apply the state transition function.
    let mut receipts = Vec::new();
    for (pos, tx) in input.txs {
        println!("cycle-tracker-report-start: execute tx {}", pos);
        let action = state.execute::<SP1RecursiveVerifier>(&tx);
        println!("cycle-tracker-report-end: execute tx {}", pos);
        match action {
            Ok(Some(action)) => {
                println!("tx {} processed", pos);
                receipts.push(action);
            }
            Ok(None) => {
                println!("tx {} processed", pos);
            }
            Err(VAppError::Revert(revert)) => {
                println!("tx {} reverted: {:?}", pos, revert);
            }
            Err(VAppError::Panic(panic)) => {
                panic!("tx {} panicked: {:?}", pos, panic);
            }
        }
    }

    // Compute the updated roots.
    println!("cycle-tracker-report-start: compute new accounts root");
    let new_accounts_root = MerkleStorage::calculate_new_root_sparse(
        input.accounts_root,
        &input.account_proofs,
        &state.accounts,
    )
    .expect("failed to compute new accounts root");
    println!("cycle-tracker-report-end: compute new accounts root");

    println!("cycle-tracker-report-start: compute new requests root");
    let new_requests_root = MerkleStorage::calculate_new_root_sparse(
        input.requests_root,
        &input.request_proofs,
        &state.requests,
    )
    .expect("failed to compute new requests root");
    println!("cycle-tracker-report-end: compute new requests root");

    // Compute the new state root.
    println!("cycle-tracker-report-start: compute new state root");
    let new_root = state.root::<Keccak256>(new_accounts_root, new_requests_root);
    println!("cycle-tracker-report-end: compute new state root");

    // Encode the public values of the program.
    println!("cycle-tracker-report-start: encode public values");
    let public_values = StepPublicValues {
        oldRoot: input.root,
        newRoot: new_root,
        timestamp: input.timestamp,
        receipts: receipts.into_iter().map(|action| action.sol()).collect(),
    };
    let bytes = StepPublicValues::abi_encode(&public_values);
    println!("cycle-tracker-report-end: encode public values");

    // Commit to the public values of the program.
    sp1_zkvm::io::commit_slice(&bytes);
}
