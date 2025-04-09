use clap::Parser;
use anyhow::Result;
use dotenv::dotenv;
use spn_prover::prove;

/// The main CLI structure that defines the available commands.
#[derive(Parser)]
#[command(author, version, about, long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

/// The available commands that can be executed by the CLI.
#[derive(clap::Subcommand)]
enum Commands {
    /// Run the prover with optional environment variables.
    Prove {
        /// Override the worst case throughput in proofs/second from .env.
        #[arg(long)]
        worst_case_throughput: Option<f64>,
        
        /// Override the bid amount in USDC from .env.
        #[arg(long)]
        bid_amount: Option<u64>,
    },
}

/// The main entry point for the CLI.
#[tokio::main]
async fn main() -> Result<()> {
    // Load environment variables.
    dotenv().ok();

    let cli = Cli::parse();

    match &cli.command {
        Commands::Prove { worst_case_throughput, bid_amount } => {
            if let Some(throughput) = worst_case_throughput {
                std::env::set_var("WORST_CASE_THROUGHPUT", throughput.to_string());
            }
            if let Some(amount) = bid_amount {
                std::env::set_var("BID_AMOUNT", amount.to_string());
            }

            // Call the prover's main function directly.
            prove().await?;
        }
    }

    Ok(())
} 