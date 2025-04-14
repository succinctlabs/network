use std::{str::FromStr, sync::Arc};

use anyhow::Result;
use spn_network_types::GetBalanceRequest;
use tonic::Request;
use tracing::{debug, error};

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
                let response = prover.network.clone().get_balance(req).await?;
                debug!("Raw balance response: {:?}", response);
                Ok(response.into_inner().amount)
            },
            "get balance",
        )
        .await?;
    debug!("Balance string: {}", resp);
    Ok(resp)
}

/// Checks if the account has enough balance to prove.
pub(crate) async fn has_enough(prover: Arc<Prover>) -> Result<bool> {
    let balance = fetch(prover.clone()).await?;
    let balance_uint = alloy::primitives::U256::from_str(&balance)?;
    let bid_amount_uint = alloy::primitives::U256::from(prover.bid_amount);
    
    debug!("Balance: {}, Bid Amount: {}", balance, prover.bid_amount);
    debug!("Balance U256: {}, Bid Amount U256: {}", balance_uint, bid_amount_uint);
    
    if balance_uint.is_zero() {
        error!("❌ Account has zero balance");
        return Ok(false);
    }
    
    if balance_uint < bid_amount_uint {
        error!("❌ Insufficient balance {} credits for bid amount {} credits", balance, prover.bid_amount);
        return Ok(false);
    }
    
    Ok(true)
}
