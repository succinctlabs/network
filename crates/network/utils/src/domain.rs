use alloy_primitives::B256;
use alloy_sol_types::eip712_domain;
use anyhow::Result;
use serde::{Deserialize, Deserializer};
use std::sync::LazyLock;

/// Deserializes a domain name into a [B256] domain separator.
pub fn deserialize_domain<'de, D>(deserializer: D) -> Result<B256, D::Error>
where
    D: Deserializer<'de>,
{
    let domain_name = String::deserialize(deserializer)?;
    get_domain(&domain_name).map_err(serde::de::Error::custom)
}

/// Returns the domain separator for the given domain name.
pub fn get_domain(name: &str) -> Result<B256> {
    match name {
        "SPN_MAINNET_V1_DOMAIN" => Ok(*SPN_MAINNET_V1_DOMAIN),
        "SPN_SEPOLIA_V1_DOMAIN" => Ok(*SPN_SEPOLIA_V1_DOMAIN),
        _ => Err(anyhow::anyhow!("Invalid domain name: {}", name)),
    }
}

/// The [`alloy_sol_types::Eip712Domain`] separator for the vApp on Sepolia.
pub static SPN_SEPOLIA_V1_DOMAIN: LazyLock<B256> = LazyLock::new(|| {
    let domain = eip712_domain! {
        name: "Succinct Prover Network",
        version: "1.0.0",
        chain_id: 11155111,
    };
    domain.separator()
});

/// The [`alloy_sol_types::Eip712Domain`] separator for the vApp on Sepolia.
pub static SPN_MAINNET_V1_DOMAIN: LazyLock<B256> = LazyLock::new(|| {
    let domain = eip712_domain! {
        name: "Succinct Prover Network",
        version: "1.0.0",
        chain_id: 1,
    };
    domain.separator()
});
