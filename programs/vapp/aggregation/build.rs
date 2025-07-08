use sp1_sdk::{HashableKey, ProverClient};
use std::fs;

fn main() {
    // Ensure the build script is re-run whenever the ELF file changes.
    println!("cargo:rerun-if-changed=../../../elf/spn-vapp-stf");
    let elf = fs::read("../../../elf/spn-vapp-stf").expect("failed to read elf");

    // Setup the prover client.
    let client = ProverClient::from_env();

    // Setup the program.
    let (_, vk) = client.setup(&elf);
    let hash = vk.hash_u32();

    // Create key.rs file with the hash as [u32; 8]
    let content = format!("pub const STF_VKEY: [u32; 8] = {hash:?};");

    // Write the generated file into OUT_DIR.
    let out_dir = std::env::var("OUT_DIR").expect("OUT_DIR environment variable not set");
    let dest_path = std::path::Path::new(&out_dir).join("key.rs");
    fs::write(dest_path, content).expect("failed to write key.rs file");
}
