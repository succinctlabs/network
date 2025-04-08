use std::sync::Arc;

use anyhow::{Context, Result};
use futures::future::join_all;
use tokio::spawn;
use tonic::Request;
use tracing::{debug, error, info};

use spn_network_types::{
    BidRequest, BidRequestBody, FulfillmentStatus, GetFilteredProofRequestsRequest,
    GetNonceRequest, MessageFormat, Signable,
};
use spn_utils::time_now;

use crate::{retry::RetryableRpc, Prover, EXPLORER_URL_REQUEST, REQUEST_LIMIT, VERSION};

/// Queries the network for new requests (status: Requested) and bids on each.
pub(crate) async fn process_requests(prover: Arc<Prover>, owner: &[u8]) -> Result<()> {
    let req = GetFilteredProofRequestsRequest {
        version: Some(VERSION.to_string()),
        fulfillment_status: Some(FulfillmentStatus::Requested.into()),
        execution_status: None,
        minimum_deadline: Some(time_now()),
        vk_hash: None,
        requester: None,
        fulfiller: None,
        limit: Some(REQUEST_LIMIT),
        page: None,
        from: None,
        to: None,
        mode: None,
        not_bid_by: Some(owner.to_vec()),
    };

    let network_resp = prover.network.clone().get_filtered_proof_requests(req).await?;
    let requests = network_resp.into_inner().requests;
    if requests.is_empty() {
        debug!("found no auctions to bid in");
        return Ok(());
    }
    info!(
        "📢 found {} {} to bid in",
        requests.len(),
        if requests.len() == 1 { "auction" } else { "auctions" }
    );

    let bid_tasks = requests.into_iter().map(|req| {
        let prover = Arc::clone(&prover);
        let id = hex::encode(&req.request_id);

        spawn(async move {
            match process_request(&prover, &id).await {
                Ok(_) => info!("🏷️  bid on request {}/0x{}", EXPLORER_URL_REQUEST, id),
                Err(e) => {
                    error!("❌ failed to bid on request {}/0x{}: {:?}", EXPLORER_URL_REQUEST, id, e)
                }
            }
        })
    });

    join_all(bid_tasks).await;

    Ok(())
}

/// Sends a bid for a single request.
async fn process_request(prover: &Prover, request_id: &str) -> Result<()> {
    let address = prover.signer.address().to_vec();
    prover
        .network
        .clone()
        .with_retry(
            || async {
                // Get the nonce.
                let req = Request::new(GetNonceRequest { address: address.clone() });
                let nonce = prover.network.clone().get_nonce(req).await?.into_inner().nonce;

                // Create and submit the bid request.
                let body = BidRequestBody {
                    nonce,
                    request_id: hex::decode(request_id).context("failed to decode request_id")?,
                };
                let bid_request = BidRequest {
                    format: MessageFormat::Binary.into(),
                    signature: body.sign(&prover.signer).into(),
                    body: Some(body),
                };
                prover.network.clone().bid(bid_request).await?;
                Ok(())
            },
            "bid on request",
        )
        .await?;

    Ok(())
}
