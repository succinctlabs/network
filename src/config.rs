use config::{Config, ConfigError, Environment};
use serde::Deserialize;
use spn_logging::LogFormat;

#[derive(Debug, Deserialize)]
pub struct Settings {
    pub rpc_url: String,
    pub private_key: String,
    pub s3_bucket: String,
    pub s3_region: String,
    pub log_format: LogFormat,
}

impl Settings {
    pub fn new() -> Result<Self, ConfigError> {
        let config = Config::builder()
            .set_default("rpc_url", "https://rpc.production.succinct.xyz")?
            .set_default("s3_bucket", "spn-artifacts-production3")?
            .set_default("s3_region", "us-east-2")?
            .set_default("log_format", "Minimal")?
            .add_source(Environment::with_prefix("NETWORK"))
            .build()?;

        config.try_deserialize()
    }
}
