use std::{str::FromStr, sync::Arc};

use anyhow::Result;
use spn_network_types::GetBalanceRequest;
use tonic::Request;

use crate::{retry::RetryableRpc, Prover};

/// Queries the network for the owner of the signer.
pub(crate) async fn owner(prover: Arc<Prover>) -> Result<Vec<u8>> {
    let address = prover.signer.address().to_vec();
    let req = spn_network_types::GetOwnerRequest { address };
    let resp = prover.network.clone().get_owner(Request::new(req)).await?;
    Ok(resp.into_inner().owner)
}

/// Queries the network for the balance of the signer.
pub(crate) async fn fetch(prover: Arc<Prover>) -> Result<String> {
    let address = prover.signer.address().to_vec();
    let resp = prover
        .network
        .clone()
        .with_retry(
            || async {
                let req = Request::new(GetBalanceRequest { address: address.clone() });
                Ok(prover.network.clone().get_balance(req).await?.into_inner().amount)
            },
            "get balance",
        )
        .await?;
    Ok(resp)
}

/// Checks if the account has enough balance to prove.
pub(crate) async fn has_enough(prover: Arc<Prover>) -> Result<bool> {
    let balance = fetch(prover).await?;
    let balance_uint = alloy::primitives::U256::from_str(&balance)?;
    Ok(!balance_uint.is_zero())
}
