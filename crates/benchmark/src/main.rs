use anyhow::Result;
use crate::{has_cuda_support, run_fibonacci};
use sp1_sdk::utils;

#[tokio::main]
async fn main() -> Result<()> {
    utils::setup_logger();

    if has_cuda_support() {
        println!("CUDA support detected, using GPU prover.");
    } else {
        println!("No CUDA support detected, using CPU prover.");
    }

    let n = 2000000;
    println!("Running Fibonacci for n = {}...", n);
    run_fibonacci(n).await?;

    Ok(())
}