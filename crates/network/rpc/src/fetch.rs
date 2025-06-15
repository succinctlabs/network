use std::str::FromStr;

use alloy_primitives::U256;
use anyhow::Result;
use spn_network_types::{
    prover_network_client::ProverNetworkClient, GetBalanceRequest, GetOwnerRequest,
};
use tonic::{transport::Channel, Request};
use tracing::debug;

use crate::RetryableRpc;

/// Fetches the balance of an address on the network.
pub async fn fetch_balance(network: &ProverNetworkClient<Channel>, address: &[u8]) -> Result<U256> {
    let address = address.to_vec();
    let response = network
        .clone()
        .with_retry(
            || async {
                debug!("fetching balance for {}", hex::encode(&address));
                let req = Request::new(GetBalanceRequest { address: address.clone() });
                let response = network.clone().get_balance(req).await?;
                Ok(response.into_inner().amount)
            },
            "get balance",
        )
        .await?;
    debug!("fetched balance for {} with response: {}", hex::encode(&address), response);
    Ok(U256::from_str(&response)?)
}

/// Fetches the owner of an address/prover on the network.
pub async fn fetch_owner(
    network: &ProverNetworkClient<Channel>,
    address: &[u8],
) -> Result<Vec<u8>> {
    let address = address.to_vec();
    let req = Request::new(GetOwnerRequest { address });
    let resp = network.clone().get_owner(req).await?;
    Ok(resp.into_inner().owner)
}
