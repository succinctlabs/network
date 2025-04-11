use std::process::Command;

use anyhow::Result;
use sp1_sdk::{ProverClient, SP1Stdin, include_elf};
use tracing::{debug, info};

// The ELF (executable and linkable format) for the program to run.
const ELF: &[u8] = include_elf!("fibonacci-program");

/// Check if CUDA is available by testing if nvidia-smi is installed and CUDA GPUs are present.
pub fn has_cuda_support() -> bool {
    // Common paths where nvidia-smi might be installed.
    let nvidia_smi_paths = ["nvidia-smi", "/usr/bin/nvidia-smi", "/usr/local/bin/nvidia-smi"];

    for path in nvidia_smi_paths {
        match Command::new(path).output() {
            Ok(output) => {
                if output.status.success() {
                    debug!("found working nvidia-smi at: {}.", path);
                    return true;
                } else {
                    debug!("nvidia-smi at {} exists but returned error status.", path);
                }
            }
            Err(e) => {
                debug!("failed to execute nvidia-smi at {}: {}.", path, e);
            }
        }
    }

    debug!("no working nvidia-smi found in any standard location.");
    false
}

/// Run the Fibonacci program for a given value of n.
async fn run_fibonacci(n: u32) -> Result<(u64, f64)> {
    // Create input stream.
    let mut stdin = SP1Stdin::new();
    stdin.write(&n);

    // Initialize the prover client from environment
    let client = ProverClient::from_env();

    // Execute to get the report.
    let (_, report) = client.execute(ELF, &stdin).run().unwrap();
    let prover_gas = report.gas.unwrap_or(0);
    println!("prover gas: {}", prover_gas);
    info!("executed program with {} cycles", report.total_instruction_count());

    // Setup the proving key and verification key.
    let (pk, _vk) = client.setup(ELF);

    // Start timing.
    let start = std::time::Instant::now();

    // Generate the proof.
    let _proof = client.prove(&pk, &stdin).compressed().run().unwrap();
    info!("generated proof for n = {}", n);

    // Calculate duration and throughput.
    let duration = start.elapsed();
    let throughput = prover_gas as f64 / duration.as_secs_f64();
    println!("n = {}: e2e time = {:.2?}, throughput = {:.2} gas/sec", n, duration, throughput);

    Ok((prover_gas, throughput))
}

/// Run benchmarks for different values of n and return the worst-case throughput.
pub async fn run_benchmarks() -> Result<(f64, u64)> {
    // Just run one Fibonacci calculation for now
    let (_, throughput) = run_fibonacci(2000000).await?;
    
    // Return only benchmark-related values
    Ok((
        throughput,  // WORST_CASE_THROUGHPUT
        1,          // BID_AMOUNT
    ))
}