use anyhow::Result;
use benchmark::{has_cuda_support, run_fibonacci};

#[tokio::main]
async fn main() -> Result<()> {
    if has_cuda_support() {
        println!("CUDA support detected, using GPU prover.");
    } else {
        println!("No CUDA support detected, using CPU prover.");
    }

    for n in [20000, 200000, 2000000] {
        println!("Running Fibonacci for n = {}...", n);
        run_fibonacci(n).await?;
    }

    Ok(())
}