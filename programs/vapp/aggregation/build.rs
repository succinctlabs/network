use sp1_sdk::{HashableKey, ProverClient};
use std::fs;

fn main() {
    // Fetch the ELF.
    let elf = fs::read("../../../elf/spn-vapp-stf").expect("failed to read elf");

    // Setup the prover client.
    let client = ProverClient::from_env();

    // Setup the program.
    let (_, vk) = client.setup(&elf);
    let hash = vk.hash_u32();

    // Create key.rs file with the hash as [u32; 8]
    let content = format!("pub const STF_VKEY: [u32; 8] = {:?};", hash);
    fs::write("src/key.rs", content).expect("Failed to write key.rs file");
}
