use config::{Config, ConfigError, Environment};
use serde::Deserialize;
use spn_logging::LogFormat;

/// Settings for the prover.
#[derive(Debug, Deserialize)]
pub struct Settings {
    /// The RPC URL for the network.
    pub rpc_url: String,
    /// The private key for signing transactions.
    pub private_key: String,
    /// The S3 bucket for storing artifacts.
    pub s3_bucket: String,
    /// The S3 region for storing artifacts.
    pub s3_region: String,
    /// The format for logging.
    pub log_format: LogFormat,
}

impl Settings {
    /// Create a new Settings instance from environment variables.
    pub fn new() -> Result<Self, ConfigError> {
        let config = Config::builder()
            .set_default("rpc_url", "https://rpc.production.succinct.xyz")?
            .set_default("s3_bucket", "spn-artifacts-testnet-private")?
            .set_default("s3_region", "us-east-2")?
            .set_default("log_format", "Minimal")?
            .add_source(Environment::with_prefix("NETWORK"))
            .build()?;

        config.try_deserialize()
    }
}
