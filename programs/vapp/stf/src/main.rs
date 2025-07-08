#![no_main]
sp1_zkvm::entrypoint!(main);

use alloy_primitives::Keccak256;
use alloy_sol_types::SolType;
use sp1_zkvm::lib::verify::verify_sp1_proof;
use spn_vapp_core::{
    input::VAppStfInput,
    merkle::MerkleStorage,
    sol::StepPublicValues,
    verifier::{VAppVerifier, VAppVerifierError},
};

#[derive(Debug, Clone, Default)]
struct SP1RecursiveVerifier;

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
    let input = sp1_zkvm::io::read::<VAppStfInput>();

    // Check that the state root is consistent with the state.
    let mut state = input.state;
    assert_eq!(
        state.root::<Keccak256>(input.accounts_root, input.requests_root),
        input.root,
        "state root mismatch"
    );

    // Verify the roots against the proofs.
    state
        .accounts
        .recover::<Keccak256>(input.accounts_root, &input.account_proofs)
        .expect("accounts root mismatch");

    state
        .transactions
        .recover::<Keccak256>(input.requests_root, &input.request_proofs)
        .expect("requests root mismatch");

    // Apply the state transition function.
    let mut receipts = Vec::new();
    for (pos, tx) in input.txs {
        let action = state.execute::<SP1RecursiveVerifier>(&tx);
        match action {
            Ok(Some(receipt)) => {
                println!("tx {pos} processed");
                receipts.push(receipt);
            }
            Ok(None) => {
                println!("tx {pos} processed");
            }
            Err(panic) => {
                panic!("tx {pos} panicked: {panic:?}");
            }
        }
    }

    // Compute the updated roots.
    let new_accounts_root = MerkleStorage::calculate_new_root_sparse(
        input.accounts_root,
        &input.account_proofs,
        &state.accounts,
    )
    .expect("failed to compute new accounts root");

    let new_requests_root = MerkleStorage::calculate_new_root_sparse(
        input.requests_root,
        &input.request_proofs,
        &state.transactions,
    )
    .expect("failed to compute new requests root");

    // Compute the new state root.
    let new_root = state.root::<Keccak256>(new_accounts_root, new_requests_root);

    // Encode the public values of the program.
    let public_values = StepPublicValues {
        oldRoot: input.root,
        newRoot: new_root,
        timestamp: input.timestamp,
        receipts: receipts.into_iter().map(|receipt| receipt.sol()).collect(),
    };
    let bytes = StepPublicValues::abi_encode(&public_values);

    // Commit to the public values of the program.
    sp1_zkvm::io::commit_slice(&bytes);
}
