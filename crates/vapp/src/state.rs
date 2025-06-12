//! State.
//!
//! This module contains the state and the logic of the state transition function of the vApp.

use alloy_primitives::{Address, B256, U256};
use eyre::Result;
use serde::{Deserialize, Serialize};
use tracing::{debug, info};

use spn_network_types::{ExecutionStatus, HashableWithSender, ProofMode};

use crate::{
    errors::{VAppError, VAppPanic, VAppRevert},
    fee::fee,
    merkle::{MerkleStorage, MerkleTreeHasher},
    receipts::{OnchainReceipt, VAppReceipt},
    signing::{eth_sign_verify, proto_verify},
    sol::{Account, TransactionStatus, VAppStateContainer},
    sparse::SparseStorage,
    storage::{RequestId, Storage},
    transactions::{OnchainTransaction, VAppTransaction},
    utils::{address, bytes_to_words_be},
    verifier::VAppVerifier,
};

/// The state of the Succinct Prover Network vApp.
///
/// This state is used to keep track of the accounts, requests, and other data in the vApp.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VAppState<A: Storage<Address, Account>, R: Storage<RequestId, bool>> {
    /// The domain separator, used to avoid replay attacks.
    ///
    /// Encoded as a bytes32 hash of the [`alloy_sol_types::Eip712Domain`] domain.
    pub domain: B256,
    /// The current transaction counter.
    ///
    /// Keeps track of what transaction to execute next.
    pub tx_id: u64,
    /// The current L1 transaction counter.
    ///
    /// Keeps track of what on-chain transaction to execute next.
    pub onchain_tx_id: u64,
    /// The current L1 block number.
    ///
    /// Keeps track of the last seen block number from a [`VAppEvent`].
    pub onchain_block: u64,
    /// The current L1 log index.
    ///
    /// Keeps track of the last seen log index from a [`VAppEvent`].
    pub onchain_log_index: u64,
    /// The accounts in the system for both requesters and provers.
    ///
    /// Stores balances, nonces, prover vault owners, and prover delegated signers.
    pub accounts: A,
    /// The processed requests in the system.
    ///
    /// Keeps track of which request IDs have been processed to avoid replay attacks.
    pub requests: R,
    /// The treasury address.
    ///
    /// Fees earned by the protocol are sent to this address.
    pub treasury: Address,
    /// The auctioneer address.
    ///
    /// This is a trusted party that matches requests to provers.
    pub auctioneer: Address,
    /// The executor address.
    ///
    /// This is a trusted party that executes the requests and provides auxiliary information.
    pub executor: Address,
    /// The verifier address.
    ///
    /// This is a trusted party that verifies the proof and provides auxiliary information.
    pub verifier: Address,
}

impl VAppState<MerkleStorage<Address, Account>, MerkleStorage<RequestId, bool>> {
    /// Computes the state root.
    pub fn root<H: MerkleTreeHasher>(&mut self) -> B256 {
        let state = VAppStateContainer {
            domain: self.domain,
            txId: self.tx_id,
            onchainTxId: self.onchain_tx_id,
            onchainBlock: self.onchain_block,
            onchainLogIndex: self.onchain_log_index,
            accountsRoot: self.accounts.root(),
            requestsRoot: self.requests.root(),
            treasury: self.treasury,
            auctioneer: self.auctioneer,
            executor: self.executor,
            verifier: self.verifier,
        };
        H::hash(&state)
    }
}

impl VAppState<SparseStorage<Address, Account>, SparseStorage<RequestId, bool>> {
    /// Computes the state root.
    #[must_use]
    pub fn root<H: MerkleTreeHasher>(&self, account_root: B256, requests_root: B256) -> B256 {
        let state = VAppStateContainer {
            domain: self.domain,
            txId: self.tx_id,
            onchainTxId: self.onchain_tx_id,
            onchainBlock: self.onchain_block,
            onchainLogIndex: self.onchain_log_index,
            accountsRoot: account_root,
            requestsRoot: requests_root,
            treasury: self.treasury,
            auctioneer: self.auctioneer,
            executor: self.executor,
            verifier: self.verifier,
        };
        H::hash(&state)
    }
}

impl<A: Storage<Address, Account>, R: Storage<RequestId, bool>> VAppState<A, R> {
    /// Creates a new [`VAppState`].
    #[must_use]
    pub fn new(
        domain: B256,
        treasury: Address,
        auctioneer: Address,
        executor: Address,
        verifier: Address,
    ) -> Self {
        Self {
            domain,
            tx_id: 1,
            onchain_tx_id: 1,
            onchain_block: 0,
            onchain_log_index: 0,
            accounts: A::new(),
            requests: R::new(),
            treasury,
            auctioneer,
            executor,
            verifier,
        }
    }

    /// Validates a [`OnchainTransaction`].
    ///
    /// Checks for basic invariants such as the EIP-712 domain being initialized and that the
    /// block number, log index, and timestamp are all increasing.
    pub fn validate_onchain_tx<T>(
        &self,
        event: &OnchainTransaction<T>,
        l1_tx: u64,
    ) -> Result<(), VAppError> {
        debug!("check l1 tx is not out of order");
        if l1_tx != self.onchain_tx_id {
            return Err(VAppPanic::OnchainTxOutOfOrder {
                expected: self.onchain_tx_id,
                actual: l1_tx,
            }
            .into());
        }

        debug!("check l1 block is not out of order");
        if event.block < self.onchain_block {
            return Err(VAppPanic::BlockNumberOutOfOrder {
                expected: self.onchain_block,
                actual: event.block,
            }
            .into());
        }

        debug!("check l1 log index is not out of order");
        if event.block == self.onchain_block && event.log_index <= self.onchain_log_index {
            return Err(VAppPanic::LogIndexOutOfOrder {
                current: self.onchain_log_index,
                next: event.log_index,
            }
            .into());
        }

        Ok(())
    }

    /// Executes an [`VAppTransaction`] and returns an optional [`VAppReceipt`].
    #[allow(clippy::too_many_lines)]
    pub fn execute<V: VAppVerifier>(
        &mut self,
        event: &VAppTransaction,
    ) -> Result<Option<VAppReceipt>, VAppError> {
        let action = match event {
            VAppTransaction::Deposit(deposit) => {
                // Log the deposit event.
                info!("TX {}: DEPOSIT({:?})", self.tx_id, deposit);

                // Validate the receipt.
                debug!("validate receipt");
                self.validate_onchain_tx(deposit, deposit.onchain_tx)?;

                // Update the current receipt, block, and log index.
                debug!("update l1 tx, block, and log index");
                self.onchain_tx_id += 1;
                self.onchain_block = deposit.block;
                self.onchain_log_index = deposit.log_index;

                // Update the token balance.
                info!(
                    "├── Account({}): + {} $PROVE",
                    deposit.action.account, deposit.action.amount
                );
                self.accounts
                    .entry(deposit.action.account)
                    .or_default()
                    .add_balance(deposit.action.amount);

                // Return the deposit action.
                Ok(Some(VAppReceipt::Deposit(OnchainReceipt {
                    onchain_tx_id: deposit.onchain_tx,
                    action: deposit.action.clone(),
                    status: TransactionStatus::Completed,
                })))
            }
            VAppTransaction::Withdraw(withdraw) => {
                // Log the withdraw event.
                info!("TX {}: WITHDRAW({:?})", self.tx_id, withdraw);

                // Validate the receipt.
                debug!("validate receipt");
                self.validate_onchain_tx(withdraw, withdraw.onchain_tx)?;

                // Update the current receipt, block, and log index.
                debug!("update l1 tx, block, and log index");
                self.onchain_tx_id += 1;
                self.onchain_block = withdraw.block;
                self.onchain_log_index = withdraw.log_index;

                // If the maximum value of an U256 is used, drain the entire balance.
                debug!("deduct balance");
                let account = self.accounts.entry(withdraw.action.account).or_default();
                let balance = account.get_balance();
                let withdrawal_amount = if withdraw.action.amount == U256::MAX {
                    balance
                } else {
                    if balance < withdraw.action.amount {
                        return Err(VAppRevert::InsufficientBalance {
                            account: withdraw.action.account,
                            amount: withdraw.action.amount,
                            balance,
                        }
                        .into());
                    }
                    withdraw.action.amount
                };

                // Process the withdraw by deducting from account balance.
                info!("├── Account({}): - {} $PROVE", withdraw.action.account, withdrawal_amount);
                account.deduct_balance(withdrawal_amount);

                // Return the withdraw action.
                Ok(Some(VAppReceipt::Withdraw(OnchainReceipt {
                    onchain_tx_id: withdraw.onchain_tx,
                    action: withdraw.action.clone(),
                    status: TransactionStatus::Completed,
                })))
            }
            VAppTransaction::CreateProver(prover) => {
                // Log the set delegated signer event.
                info!("TX {}: CREATE_PROVER({:?})", self.tx_id, prover);

                // Validate the onchain transaction.
                debug!("validate receipt");
                self.validate_onchain_tx(prover, prover.onchain_tx)?;

                // Update the current onchain transaction, block, and log index.
                debug!("update l1 tx, block, and log index");
                self.onchain_tx_id += 1;
                self.onchain_block = prover.block;
                self.onchain_log_index = prover.log_index;

                // Set the owner, signer, and staker fee of the prover.
                //
                // We set the owner as the signer so that they can immediately start running their
                // prover with the owner key without having to delegate.
                debug!("set owner, signer, and staker fee");
                self.accounts
                    .entry(prover.action.prover)
                    .or_default()
                    .set_owner(prover.action.owner)
                    .set_signer(prover.action.owner)
                    .set_staker_fee_bips(prover.action.stakerFeeBips);

                // Return the set delegated signer action.
                Ok(Some(VAppReceipt::CreateProver(OnchainReceipt {
                    action: prover.action.clone(),
                    onchain_tx_id: prover.onchain_tx,
                    status: TransactionStatus::Completed,
                })))
            }
            VAppTransaction::Delegate(delegation) => {
                // Log the delegation event.
                info!("TX {}: DELEGATE({:?})", self.tx_id, delegation);

                // Make sure the delegation body is present.
                debug!("validate proto body");
                let body =
                    delegation.delegation.body.as_ref().ok_or(VAppPanic::MissingProtoBody)?;

                // Verify the domain.
                debug!("verify domain");
                let domain = B256::try_from(body.domain.as_slice())
                    .map_err(|_| VAppPanic::DomainDeserializationFailed)?;
                if domain != self.domain {
                    return Err(VAppPanic::DomainMismatch {
                        expected: self.domain,
                        actual: domain,
                    }
                    .into());
                }

                // Verify the proto signature.
                debug!("verify proto signature");
                let signer = proto_verify(body, &delegation.delegation.signature)
                    .map_err(|_| VAppPanic::InvalidDelegationSignature)?;

                // Extract the prover address.
                debug!("extract prover address");
                let prover = Address::try_from(body.prover.as_slice())
                    .map_err(|_| VAppPanic::AddressDeserializationFailed)?;

                // Verify that the prover exists.
                debug!("verify prover exists");
                let Some(prover) = self.accounts.get_mut(&prover) else {
                    return Err(VAppRevert::ProverDoesNotExist { prover }.into());
                };

                // Verify that the signer of the delegation is the owner of the prover.
                debug!("verify signer is owner");
                if signer != prover.get_owner() {
                    return Err(VAppPanic::OnlyOwnerCanDelegate.into());
                }

                // Extract the delegate address.
                debug!("extract delegate address");
                let delegate = Address::try_from(body.delegate.as_slice())
                    .map_err(|_| VAppPanic::AddressDeserializationFailed)?;

                // Set the delegate as a signer for the prover's account.
                debug!("set delegate as signer");
                prover.set_signer(delegate);

                // No action returned since delegation is off-chain.
                Ok(None)
            }
            VAppTransaction::Transfer(transfer) => {
                // Log the transfer event.
                info!("TX {}: TRANSFER({:?})", self.tx_id, transfer);

                // Make sure the transfer body is present.
                debug!("validate proto body");
                let body = transfer.transfer.body.as_ref().ok_or(VAppPanic::MissingProtoBody)?;

                // Verify the proto signature.
                debug!("verify proto signature");
                let from = proto_verify(body, &transfer.transfer.signature)
                    .map_err(|_| VAppPanic::InvalidTransferSignature)?;

                // Verify the domain.
                debug!("verify domain");
                let domain = B256::try_from(body.domain.as_slice())
                    .map_err(|_| VAppPanic::DomainDeserializationFailed)?;
                if domain != self.domain {
                    return Err(VAppPanic::DomainMismatch {
                        expected: self.domain,
                        actual: domain,
                    }
                    .into());
                }

                // Transfer the amount from the requester to the recipient.
                debug!("extract to address");
                let to = Address::try_from(body.to.as_slice())
                    .map_err(|_| VAppPanic::AddressDeserializationFailed)?;
                let amount = body.amount.parse::<U256>().map_err(|_| {
                    VAppPanic::InvalidTransferAmount { amount: body.amount.clone() }
                })?;

                // Validate that the from account has sufficient balance.
                debug!("validate from account has sufficient balance");
                let balance = self.accounts.entry(from).or_default().get_balance();
                if balance < amount {
                    return Err(
                        VAppPanic::InsufficientBalance { account: from, amount, balance }.into()
                    );
                }

                // Transfer the amount from the transferer to the recipient.
                info!("├── Account({}): - {} $PROVE", from, amount);
                self.accounts.entry(from).or_default().deduct_balance(amount);
                info!("├── Account({}): + {} $PROVE", to, amount);
                self.accounts.entry(to).or_default().add_balance(amount);

                Ok(None)
            }
            VAppTransaction::Clear(clear) => {
                // Make sure the proto bodies are present for (request, bid, settle, execute).
                let request = clear.request.body.as_ref().ok_or(VAppPanic::MissingProtoBody)?;
                let bid = clear.bid.body.as_ref().ok_or(VAppPanic::MissingProtoBody)?;
                let settle = clear.settle.body.as_ref().ok_or(VAppPanic::MissingProtoBody)?;
                let execute = clear.execute.body.as_ref().ok_or(VAppPanic::MissingProtoBody)?;

                // Verify the proto signatures for (request, bid, settle, execute).
                let request_signer = proto_verify(request, &clear.request.signature)
                    .map_err(|_| VAppPanic::InvalidRequestSignature)?;
                let bid_signer = proto_verify(bid, &clear.bid.signature)
                    .map_err(|_| VAppPanic::InvalidBidSignature)?;
                let settle_signer = proto_verify(settle, &clear.settle.signature)
                    .map_err(|_| VAppPanic::InvalidSettleSignature)?;
                let execute_signer = proto_verify(execute, &clear.execute.signature)
                    .map_err(|_| VAppPanic::InvalidExecuteSignature)?;

                // Verify the domains for (request, bid, settle, execute).
                for domain in [&request.domain, &bid.domain, &settle.domain, &execute.domain] {
                    let domain = B256::try_from(domain.as_slice())
                        .map_err(|_| VAppPanic::FailedToParseBytes)?;
                    if domain != self.domain {
                        return Err(VAppPanic::DomainMismatch {
                            expected: self.domain,
                            actual: domain,
                        }
                        .into());
                    }
                }

                // Validate that the request ID is the same for (request, bid, settle, execute).
                let request_id: RequestId = request
                    .hash_with_signer(request_signer.as_slice())
                    .map_err(|_| VAppPanic::HashingBodyFailed)?;
                for other_request_id in [&bid.request_id, &settle.request_id, &execute.request_id] {
                    if request_id.as_slice() != other_request_id.as_slice() {
                        return Err(VAppPanic::RequestIdMismatch {
                            found: address(&request_id)?,
                            expected: address(other_request_id)?,
                        }
                        .into());
                    }
                }

                // Check that the request ID has not been fulfilled yet.
                //
                // This check ensures that a request can't be used multiple times to pay a prover.
                if self.requests.get(&request_id).copied().unwrap_or_default() {
                    return Err(
                        VAppPanic::RequestAlreadyFulfilled { id: hex::encode(request_id) }.into()
                    );
                }

                // Validate the the bidder has the right to bid on behalf of the prover.
                //
                // Provers are liable for their bids, so it's imported to verify that they are the
                // ones that are bidding.
                let prover_address = address(bid.prover.as_slice())?;
                let prover_account = self.accounts.entry(prover_address).or_default();
                let prover_owner = prover_account.get_owner();
                if prover_account.get_signer() != bid_signer {
                    return Err(VAppPanic::ProverDelegatedSignerMismatch {
                        prover: prover_address,
                        delegated_signer: prover_account.delegatedSigner,
                    }
                    .into());
                }

                // Validate that the prover is in the request whitelist, if a whitelist is provided.
                //
                // Requesters may whitelist what provers they want to work with to ensure better
                // SLAs and quality of service.
                if !request.whitelist.is_empty()
                    && !request.whitelist.contains(&prover_address.to_vec())
                {
                    return Err(VAppPanic::ProverNotInWhitelist { prover: prover_address }.into());
                }

                // Validate that the request, settle, and auctioneer addresses match.
                let request_auctioneer = address(request.auctioneer.as_slice())?;
                if request_auctioneer != settle_signer && settle_signer != self.auctioneer {
                    return Err(VAppPanic::AuctioneerMismatch {
                        request_auctioneer,
                        settle_signer,
                        auctioneer: self.auctioneer,
                    }
                    .into());
                }

                // Validate that the request, execute, and executor addresses match.
                let request_executor = address(request.executor.as_slice())?;
                if request_executor != execute_signer && request_executor != self.executor {
                    return Err(VAppPanic::ExecutorMismatch {
                        request_executor,
                        execute_signer,
                        executor: self.executor,
                    }
                    .into());
                }

                // Ensure that the bid price is less than the max price per pgu.
                let base_fee =
                    request.base_fee.parse::<U256>().map_err(VAppPanic::U256ParseError)?;
                let max_price_per_pgu =
                    request.max_price_per_pgu.parse::<U256>().map_err(VAppPanic::U256ParseError)?;
                let price = bid.amount.parse::<U256>().map_err(VAppPanic::U256ParseError)?;
                if price > max_price_per_pgu {
                    return Err(
                        VAppPanic::MaxPricePerPguExceeded { max_price_per_pgu, price }.into()
                    );
                }

                // If the execution status is unexecutable, then punish the requester.
                //
                // This may happen in cases where the requester is malicious and doesn't provide
                // a well-formed request that can actually be proven.
                if execute.execution_status == ExecutionStatus::Unexecutable as i32 {
                    // Extract the punishment.
                    let punishment = execute
                        .punishment
                        .as_ref()
                        .ok_or(VAppPanic::MissingPunishment)?
                        .parse::<U256>()
                        .map_err(VAppPanic::U256ParseError)?;

                    // Check that the punishment is less than the max price.
                    let max_price = max_price_per_pgu * U256::from(request.gas_limit) + base_fee;
                    if punishment > max_price {
                        return Err(
                            VAppPanic::PunishmentExceedsMaxCost { punishment, max_price }.into()
                        );
                    }

                    // Deduct the punishment from the requester.
                    self.accounts.entry(request_signer).or_default().deduct_balance(punishment);

                    return Ok(None);
                }

                // Validate that the execution status is successful.
                //
                // If this is true, then a prover should definitely be able to prove the request.
                if execute.execution_status != ExecutionStatus::Executed as i32 {
                    return Err(
                        VAppPanic::ExecutionFailed { status: execute.execution_status }.into()
                    );
                }

                // Extract the fulfill body.
                let fulfill = clear.fulfill.as_ref().ok_or(VAppPanic::MissingFulfill)?;
                let fulfill_body = fulfill.body.as_ref().ok_or(VAppPanic::MissingProtoBody)?;

                // Verify the signature of the fulfiller.
                let fulfill_signer = proto_verify(fulfill_body, &fulfill.signature)
                    .map_err(|_| VAppPanic::InvalidFulfillSignature)?;

                // Verify the domain of the fulfill.
                let fulfill_domain = B256::try_from(fulfill_body.domain.as_slice())
                    .map_err(|_| VAppPanic::DomainDeserializationFailed)?;
                if fulfill_domain != self.domain {
                    return Err(VAppPanic::DomainMismatch {
                        expected: self.domain,
                        actual: fulfill_domain,
                    }
                    .into());
                }

                // Validate that the fulfill request ID matches the request ID.
                let fulfill_request_id = fulfill_body.request_id.clone();
                if fulfill_request_id != request_id {
                    return Err(VAppPanic::RequestIdMismatch {
                        found: address(&fulfill_request_id)?,
                        expected: address(&request_id)?,
                    }
                    .into());
                }

                // Extract the public values hash from the execute or the request.
                //
                // If the request has a public values hash, then it must match the execute public
                // values hash as well.
                let execute_public_values_hash: [u8; 32] = execute
                    .public_values_hash
                    .as_ref()
                    .ok_or(VAppPanic::MissingPublicValuesHash)?
                    .as_slice()
                    .try_into()
                    .map_err(|_| VAppPanic::FailedToParseBytes)?;
                let public_values_hash: [u8; 32] = match &request.public_values_hash {
                    Some(hash) => {
                        let request_public_values_hash = hash
                            .as_slice()
                            .try_into()
                            .map_err(|_| VAppPanic::FailedToParseBytes)?;
                        if request_public_values_hash != execute_public_values_hash {
                            return Err(VAppPanic::PublicValuesHashMismatch.into());
                        }
                        request_public_values_hash
                    }
                    None => execute_public_values_hash,
                };

                // Verify the proof.
                let vk = bytes_to_words_be(
                    &request
                        .vk_hash
                        .clone()
                        .try_into()
                        .map_err(|_| VAppPanic::FailedToParseBytes)?,
                )?;
                let mode = ProofMode::try_from(request.mode)
                    .map_err(|_| VAppPanic::UnsupportedProofMode { mode: request.mode })?;
                match mode {
                    ProofMode::Compressed => {
                        let verifier = V::default();
                        verifier
                            .verify(vk, public_values_hash)
                            .map_err(|_| VAppPanic::InvalidProof)?;
                    }
                    ProofMode::Groth16 | ProofMode::Plonk => {
                        let verify =
                            clear.verify.as_ref().ok_or(VAppPanic::MissingVerifierSignature)?;
                        let fulfillment_id = fulfill_body
                            .hash_with_signer(fulfill_signer.as_slice())
                            .map_err(|_| VAppPanic::HashingBodyFailed)?;
                        let verifier = eth_sign_verify(&fulfillment_id, verify)
                            .map_err(|_| VAppPanic::InvalidVerifierSignature)?;
                        if verifier != self.verifier {
                            return Err(VAppPanic::InvalidVerifierSignature.into());
                        }
                    }
                    _ => {
                        return Err(VAppPanic::UnsupportedProofMode { mode: request.mode }.into());
                    }
                }

                // Calculate the cost of the proof.
                let pgus = execute.pgus.ok_or(VAppPanic::MissingPgusUsed)?;
                let cost = price * U256::from(pgus) + base_fee;

                // Validate that the execute gas_used was lower than the request gas_limit.
                if pgus > request.gas_limit {
                    return Err(
                        VAppPanic::GasLimitExceeded { pgus, gas_limit: request.gas_limit }.into()
                    );
                }

                // Ensure the user can afford the cost of the proof.
                let account = self
                    .accounts
                    .get(&request_signer)
                    .ok_or(VAppPanic::AccountDoesNotExist { account: request_signer })?;
                if account.get_balance() < cost {
                    return Err(VAppPanic::InsufficientBalance {
                        account: request_signer,
                        amount: cost,
                        balance: account.get_balance(),
                    }
                    .into());
                }

                // Log the clear event.
                let request_id: [u8; 32] = clear
                    .fulfill
                    .as_ref()
                    .ok_or(VAppPanic::MissingFulfill)?
                    .body
                    .as_ref()
                    .ok_or(VAppPanic::MissingProtoBody)?
                    .request_id
                    .clone()
                    .try_into()
                    .map_err(|_| VAppPanic::FailedToParseBytes)?;
                info!(
                    "STEP {}: CLEAR(request_id={}, requester={}, prover={}, cost={})",
                    self.tx_id,
                    hex::encode(request_id),
                    request_signer,
                    prover_address,
                    cost
                );

                // Log the calculation of the requester fee.
                info!("├── Requester Fee = {} PGUs × {} $PROVE/PGU = {} $PROVE", pgus, price, cost);

                // Mark request as consumed before processing payment.
                self.requests.entry(request_id).or_insert(true);

                // Deduct the cost from the requester.
                info!("├── Account({}): - {} $PROVE (Requester Fee)", request_signer, cost);
                self.accounts.entry(request_signer).or_default().deduct_balance(cost);

                // Get the protocol fee.
                let protocol_address = self.treasury;
                let protocol_fee_bips = U256::from(0);

                // Get the staker fee from the prover account.
                let prover_account = self
                    .accounts
                    .get(&prover_address)
                    .ok_or(VAppPanic::AccountDoesNotExist { account: prover_address })?;
                let staker_fee_bips = prover_account.get_staker_fee_bips();

                // Calculate the fee split for the protocol, prover vault stakers, and prover owner.
                let (protocol_fee, prover_staker_fee, prover_owner_fee) =
                    fee(cost, protocol_fee_bips, staker_fee_bips);

                info!(
                    "├── Account({}): + {} $PROVE (Protocol Fee)",
                    protocol_address, protocol_fee
                );
                self.accounts.entry(protocol_address).or_default().add_balance(protocol_fee);

                info!(
                    "├── Account({}): + {} $PROVE (Staker Reward)",
                    prover_address, prover_staker_fee
                );
                self.accounts.entry(prover_address).or_default().add_balance(prover_staker_fee);

                info!(
                    "├── Account({}): + {} $PROVE (Owner Reward)",
                    prover_owner, prover_owner_fee
                );
                self.accounts.entry(prover_owner).or_default().add_balance(prover_owner_fee);

                Ok(None)
            }
        };

        // Increment the step.
        self.tx_id += 1;

        action
    }
}

#[cfg(test)]
mod tests {
    use crate::{
        sol::{CreateProver, Deposit, Withdraw},
        transactions::{DelegateTransaction, OnchainTransaction, VAppTransaction},
        utils::tests::{
            signers::{clear_vapp_event, delegate_vapp_event, proto_sign, signer},
            test_utils::{setup, VAppTestContext},
        },
        verifier::MockVerifier,
    };
    use alloy_primitives::{address, U256};
    use spn_network_types::{
        ExecutionStatus, FulfillmentStrategy, MessageFormat, RequestProofRequestBody,
        SetDelegationRequest, SetDelegationRequestBody,
    };
    use spn_utils::SPN_SEPOLIA_V1_DOMAIN;

    use super::*;

    /// Creates a deposit event with the specified parameters.
    fn create_deposit_event(
        account: Address,
        amount: U256,
        block: u64,
        log_index: u64,
        onchain_tx: u64,
    ) -> VAppTransaction {
        VAppTransaction::Deposit(OnchainTransaction {
            tx_hash: None,
            block,
            log_index,
            onchain_tx,
            action: Deposit { account, amount },
        })
    }

    /// Asserts that a receipt matches the expected deposit receipt structure.
    #[allow(clippy::ref_option)]
    fn assert_deposit_receipt(
        receipt: &Option<VAppReceipt>,
        expected_account: Address,
        expected_amount: U256,
        expected_onchain_tx: u64,
    ) {
        match receipt.as_ref().unwrap() {
            VAppReceipt::Deposit(deposit) => {
                assert_eq!(deposit.action.account, expected_account);
                assert_eq!(deposit.action.amount, expected_amount);
                assert_eq!(deposit.onchain_tx_id, expected_onchain_tx);
                assert_eq!(deposit.status, TransactionStatus::Completed);
            }
            _ => panic!("Expected a deposit receipt"),
        }
    }

    /// Asserts that an account has the expected balance.
    #[allow(clippy::ref_option)]
    fn assert_account_balance(
        test: &VAppTestContext,
        account: Address,
        expected_balance: U256,
    ) {
        let actual_balance = test.state.accounts.get(&account).unwrap().get_balance();
        assert_eq!(
            actual_balance, expected_balance,
            "Account balance mismatch for {account}: expected {expected_balance}, got {actual_balance}"
        );
    }

    /// Asserts that the state counters match the expected values.
    fn assert_state_counters(
        test: &VAppTestContext,
        expected_tx_id: u64,
        expected_onchain_tx_id: u64,
        expected_block: u64,
        expected_log_index: u64,
    ) {
        assert_eq!(test.state.tx_id, expected_tx_id, "tx_id mismatch");
        assert_eq!(test.state.onchain_tx_id, expected_onchain_tx_id, "onchain_tx_id mismatch");
        assert_eq!(test.state.onchain_block, expected_block, "onchain_block mismatch");
        assert_eq!(test.state.onchain_log_index, expected_log_index, "onchain_log_index mismatch");
    }

    /// Creates a create prover event with the specified parameters.
    fn create_create_prover_event(
        prover: Address,
        owner: Address,
        staker_fee_bips: U256,
        block: u64,
        log_index: u64,
        onchain_tx: u64,
    ) -> VAppTransaction {
        VAppTransaction::CreateProver(OnchainTransaction {
            tx_hash: None,
            block,
            log_index,
            onchain_tx,
            action: CreateProver {
                prover,
                owner,
                stakerFeeBips: staker_fee_bips,
            },
        })
    }

    /// Asserts that a receipt matches the expected create prover receipt structure.
    #[allow(clippy::ref_option)]
    fn assert_create_prover_receipt(
        receipt: &Option<VAppReceipt>,
        expected_prover: Address,
        expected_owner: Address,
        expected_staker_fee_bips: U256,
        expected_onchain_tx: u64,
    ) {
        match receipt.as_ref().unwrap() {
            VAppReceipt::CreateProver(create_prover) => {
                assert_eq!(create_prover.action.prover, expected_prover);
                assert_eq!(create_prover.action.owner, expected_owner);
                assert_eq!(create_prover.action.stakerFeeBips, expected_staker_fee_bips);
                assert_eq!(create_prover.onchain_tx_id, expected_onchain_tx);
                assert_eq!(create_prover.status, TransactionStatus::Completed);
            }
            _ => panic!("Expected a create prover receipt"),
        }
    }

    /// Asserts that a prover account has the expected configuration.
    fn assert_prover_account(
        test: &VAppTestContext,
        prover: Address,
        expected_owner: Address,
        expected_signer: Address,
        expected_staker_fee_bips: U256,
    ) {
        let account = test.state.accounts.get(&prover).unwrap();
        assert_eq!(account.get_owner(), expected_owner, "Prover owner mismatch");
        assert_eq!(account.get_signer(), expected_signer, "Prover signer mismatch");
        assert_eq!(account.get_staker_fee_bips(), expected_staker_fee_bips, "Staker fee bips mismatch");
    }

    /// Creates a delegate event with the specified parameters using the test utility.
    fn create_delegate_event(
        prover_owner: &alloy::signers::local::PrivateKeySigner,
        prover_address: Address,
        delegate_address: Address,
        nonce: u64,
    ) -> VAppTransaction {
        delegate_vapp_event(prover_owner, prover_address, delegate_address, nonce)
    }

    /// Creates a delegate event with custom domain for testing domain validation.
    fn create_delegate_event_with_domain(
        prover_owner: &alloy::signers::local::PrivateKeySigner,
        prover_address: Address,
        delegate_address: Address,
        nonce: u64,
        domain: [u8; 32],
    ) -> VAppTransaction {
        use spn_network_types::{MessageFormat, SetDelegationRequest, SetDelegationRequestBody};
        
        let body = SetDelegationRequestBody {
            nonce,
            delegate: delegate_address.to_vec(),
            prover: prover_address.to_vec(),
            domain: domain.to_vec(),
        };
        let signature = proto_sign(prover_owner, &body);

        VAppTransaction::Delegate(DelegateTransaction {
            delegation: SetDelegationRequest {
                format: MessageFormat::Binary.into(),
                body: Some(body),
                signature: signature.as_bytes().to_vec(),
            },
        })
    }

    /// Creates a delegate event with missing body for testing validation.
    fn create_delegate_event_missing_body() -> VAppTransaction {
        use spn_network_types::{MessageFormat, SetDelegationRequest};

        VAppTransaction::Delegate(DelegateTransaction {
            delegation: SetDelegationRequest {
                format: MessageFormat::Binary.into(),
                body: None,
                signature: vec![],
            },
        })
    }

    /// Asserts that a prover has the expected signer.
    fn assert_prover_signer(test: &VAppTestContext, prover: Address, expected_signer: Address) {
        let account = test.state.accounts.get(&prover).unwrap();
        assert_eq!(account.get_signer(), expected_signer, "Prover signer mismatch");
        assert!(account.is_signer(expected_signer), "Expected address should be a valid signer");
    }

    /// Creates a transfer event with the specified parameters.
    fn create_transfer_event(
        from_signer: &alloy::signers::local::PrivateKeySigner,
        to: Address,
        amount: U256,
        nonce: u64,
    ) -> VAppTransaction {
        use spn_network_types::{MessageFormat, TransferRequest, TransferRequestBody};
        
        let body = TransferRequestBody {
            nonce,
            to: to.to_vec(),
            amount: amount.to_string(),
            domain: spn_utils::SPN_SEPOLIA_V1_DOMAIN.to_vec(),
        };
        let signature = proto_sign(from_signer, &body);

        VAppTransaction::Transfer(TransferTransaction {
            transfer: TransferRequest {
                format: MessageFormat::Binary.into(),
                body: Some(body),
                signature: signature.as_bytes().to_vec(),
            },
        })
    }

    /// Creates a transfer event with custom domain for testing domain validation.
    fn create_transfer_event_with_domain(
        from_signer: &alloy::signers::local::PrivateKeySigner,
        to: Address,
        amount: U256,
        nonce: u64,
        domain: [u8; 32],
    ) -> VAppTransaction {
        use spn_network_types::{MessageFormat, TransferRequest, TransferRequestBody};
        
        let body = TransferRequestBody {
            nonce,
            to: to.to_vec(),
            amount: amount.to_string(),
            domain: domain.to_vec(),
        };
        let signature = proto_sign(from_signer, &body);

        VAppTransaction::Transfer(TransferTransaction {
            transfer: TransferRequest {
                format: MessageFormat::Binary.into(),
                body: Some(body),
                signature: signature.as_bytes().to_vec(),
            },
        })
    }

    /// Creates a transfer event with missing body for testing validation.
    fn create_transfer_event_missing_body() -> VAppTransaction {
        use spn_network_types::{MessageFormat, TransferRequest};

        VAppTransaction::Transfer(TransferTransaction {
            transfer: TransferRequest {
                format: MessageFormat::Binary.into(),
                body: None,
                signature: vec![],
            },
        })
    }

    /// Creates a transfer event with invalid amount string for testing parsing.
    fn create_transfer_event_invalid_amount(
        from_signer: &alloy::signers::local::PrivateKeySigner,
        to: Address,
        invalid_amount: &str,
        nonce: u64,
    ) -> VAppTransaction {
        use spn_network_types::{MessageFormat, TransferRequest, TransferRequestBody};
        
        let body = TransferRequestBody {
            nonce,
            to: to.to_vec(),
            amount: invalid_amount.to_string(),
            domain: spn_utils::SPN_SEPOLIA_V1_DOMAIN.to_vec(),
        };
        let signature = proto_sign(from_signer, &body);

        VAppTransaction::Transfer(TransferTransaction {
            transfer: TransferRequest {
                format: MessageFormat::Binary.into(),
                body: Some(body),
                signature: signature.as_bytes().to_vec(),
            },
        })
    }

    /// Creates a withdraw event with the specified parameters.
    fn create_withdraw_event(
        account: Address,
        amount: U256,
        block: u64,
        log_index: u64,
        onchain_tx: u64,
    ) -> VAppTransaction {
        VAppTransaction::Withdraw(OnchainTransaction {
            tx_hash: None,
            block,
            log_index,
            onchain_tx,
            action: Withdraw { account, amount },
        })
    }

    /// Asserts that a receipt matches the expected withdraw receipt structure.
    #[allow(clippy::ref_option)]
    fn assert_withdraw_receipt(
        receipt: &Option<VAppReceipt>,
        expected_account: Address,
        expected_amount: U256,
        expected_onchain_tx: u64,
    ) {
        match receipt.as_ref().unwrap() {
            VAppReceipt::Withdraw(withdraw) => {
                assert_eq!(withdraw.action.account, expected_account);
                assert_eq!(withdraw.action.amount, expected_amount);
                assert_eq!(withdraw.onchain_tx_id, expected_onchain_tx);
                assert_eq!(withdraw.status, TransactionStatus::Completed);
            }
            _ => panic!("Expected a withdraw receipt"),
        }
    }

    #[test]
    fn test_deposit_basic() {
        let mut test = setup();
        let account = test.requester.address();
        let amount = U256::from(100);

        // Create and execute a basic deposit event.
        let event = create_deposit_event(account, amount, 0, 1, 1);
        let receipt = test.state.execute::<MockVerifier>(&event).unwrap();

        // Verify the account balance was updated correctly.
        assert_account_balance(&test, account, amount);
        assert_deposit_receipt(&receipt, account, amount, 1);
        
        // Verify state counters were incremented.
        assert_state_counters(&test, 2, 2, 0, 1);
    }

    #[test]
    fn test_deposit_multiple_same_account() {
        let mut test = setup();
        let account = test.requester.address();

        // Execute first deposit.
        let event1 = create_deposit_event(account, U256::from(100), 0, 1, 1);
        let receipt1 = test.state.execute::<MockVerifier>(&event1).unwrap();
        assert_deposit_receipt(&receipt1, account, U256::from(100), 1);
        assert_account_balance(&test, account, U256::from(100));

        // Execute second deposit to same account.
        let event2 = create_deposit_event(account, U256::from(200), 0, 2, 2);
        let receipt2 = test.state.execute::<MockVerifier>(&event2).unwrap();
        assert_deposit_receipt(&receipt2, account, U256::from(200), 2);
        assert_account_balance(&test, account, U256::from(300));

        // Execute third deposit to same account.
        let event3 = create_deposit_event(account, U256::from(50), 1, 1, 3);
        let receipt3 = test.state.execute::<MockVerifier>(&event3).unwrap();
        assert_deposit_receipt(&receipt3, account, U256::from(50), 3);
        assert_account_balance(&test, account, U256::from(350));
    }

    #[test]
    fn test_deposit_multiple_different_accounts() {
        let mut test = setup();
        let account1 = test.requester.address();
        let account2 = test.prover.address();
        let account3 = test.auctioneer.address();

        // Execute deposit to account1.
        let event1 = create_deposit_event(account1, U256::from(100), 0, 1, 1);
        test.state.execute::<MockVerifier>(&event1).unwrap();
        assert_account_balance(&test, account1, U256::from(100));

        // Execute deposit to account2.
        let event2 = create_deposit_event(account2, U256::from(200), 0, 2, 2);
        test.state.execute::<MockVerifier>(&event2).unwrap();
        assert_account_balance(&test, account2, U256::from(200));

        // Execute deposit to account3.
        let event3 = create_deposit_event(account3, U256::from(300), 1, 1, 3);
        test.state.execute::<MockVerifier>(&event3).unwrap();
        assert_account_balance(&test, account3, U256::from(300));

        // Verify all accounts maintain correct balances.
        assert_account_balance(&test, account1, U256::from(100));
        assert_account_balance(&test, account2, U256::from(200));
        assert_account_balance(&test, account3, U256::from(300));
    }

    #[test]
    fn test_deposit_large_amounts() {
        let mut test = setup();
        let account = test.requester.address();

        // Execute deposit with maximum U256 value.
        let max_amount = U256::MAX;
        let event = create_deposit_event(account, max_amount, 0, 1, 1);
        let receipt = test.state.execute::<MockVerifier>(&event).unwrap();

        // Verify maximum amount deposit succeeded.
        assert_account_balance(&test, account, max_amount);
        assert_deposit_receipt(&receipt, account, max_amount, 1);
    }

    #[test]
    fn test_deposit_zero_amount() {
        let mut test = setup();
        let account = test.requester.address();

        // Execute deposit with zero amount.
        let event = create_deposit_event(account, U256::ZERO, 0, 1, 1);
        let receipt = test.state.execute::<MockVerifier>(&event).unwrap();

        // Verify zero amount deposit succeeded.
        assert_account_balance(&test, account, U256::ZERO);
        assert_deposit_receipt(&receipt, account, U256::ZERO, 1);
    }

    #[test]
    fn test_deposit_onchain_tx_out_of_order() {
        let mut test = setup();
        let account = test.requester.address();

        // Execute first deposit.
        let event1 = create_deposit_event(account, U256::from(100), 0, 1, 1);
        test.state.execute::<MockVerifier>(&event1).unwrap();

        // Try to execute deposit with wrong onchain_tx (should be 2, but using 3).
        let event2 = create_deposit_event(account, U256::from(100), 0, 2, 3);
        let result = test.state.execute::<MockVerifier>(&event2);

        // Verify the correct panic error is returned.
        assert!(matches!(
            result,
            Err(VAppError::Panic(VAppPanic::OnchainTxOutOfOrder { expected: 2, actual: 3 }))
        ));

        // Verify state remains unchanged after error.
        assert_account_balance(&test, account, U256::from(100));
        assert_state_counters(&test, 2, 2, 0, 1);
    }

    #[test]
    fn test_deposit_block_number_regression() {
        let mut test = setup();
        let account = test.requester.address();

        // Execute first deposit at block 5.
        let event1 = create_deposit_event(account, U256::from(100), 5, 1, 1);
        test.state.execute::<MockVerifier>(&event1).unwrap();

        // Try to execute deposit at earlier block (regression).
        let event2 = create_deposit_event(account, U256::from(100), 3, 1, 2);
        let result = test.state.execute::<MockVerifier>(&event2);

        // Verify the correct panic error is returned.
        assert!(matches!(
            result,
            Err(VAppError::Panic(VAppPanic::BlockNumberOutOfOrder { expected: 5, actual: 3 }))
        ));

        // Verify state remains unchanged after error.
        assert_account_balance(&test, account, U256::from(100));
        assert_state_counters(&test, 2, 2, 5, 1);
    }

    #[test]
    fn test_deposit_log_index_out_of_order() {
        let mut test = setup();
        let account = test.requester.address();

        // Execute first deposit at block 0, log_index 5.
        let event1 = create_deposit_event(account, U256::from(100), 0, 5, 1);
        test.state.execute::<MockVerifier>(&event1).unwrap();

        // Try to execute deposit at same block with same log_index.
        let event2 = create_deposit_event(account, U256::from(100), 0, 5, 2);
        let result = test.state.execute::<MockVerifier>(&event2);

        // Verify the correct panic error is returned.
        assert!(matches!(
            result,
            Err(VAppError::Panic(VAppPanic::LogIndexOutOfOrder { current: 5, next: 5 }))
        ));

        // Try with log_index lower than current.
        let event3 = create_deposit_event(account, U256::from(100), 0, 3, 2);
        let result = test.state.execute::<MockVerifier>(&event3);

        // Verify the correct panic error is returned.
        assert!(matches!(
            result,
            Err(VAppError::Panic(VAppPanic::LogIndexOutOfOrder { current: 5, next: 3 }))
        ));

        // Verify state remains unchanged after error.
        assert_account_balance(&test, account, U256::from(100));
        assert_state_counters(&test, 2, 2, 0, 5);
    }

    #[test]
    fn test_deposit_log_index_valid_progression() {
        let mut test = setup();
        let account = test.requester.address();

        // Execute first deposit at block 0, log_index 5.
        let event1 = create_deposit_event(account, U256::from(100), 0, 5, 1);
        test.state.execute::<MockVerifier>(&event1).unwrap();

        // Execute second deposit at same block with higher log_index (valid).
        let event2 = create_deposit_event(account, U256::from(100), 0, 6, 2);
        let receipt2 = test.state.execute::<MockVerifier>(&event2).unwrap();

        // Verify balance accumulation and state updates.
        assert_account_balance(&test, account, U256::from(200));
        assert_deposit_receipt(&receipt2, account, U256::from(100), 2);
        assert_eq!(test.state.onchain_log_index, 6);

        // Execute third deposit at higher block (log_index can be anything).
        let event3 = create_deposit_event(account, U256::from(100), 1, 1, 3);
        let receipt3 = test.state.execute::<MockVerifier>(&event3).unwrap();

        // Verify final state after block progression.
        assert_account_balance(&test, account, U256::from(300));
        assert_deposit_receipt(&receipt3, account, U256::from(100), 3);
        assert_state_counters(&test, 4, 4, 1, 1);
    }

    #[test]
    fn test_withdraw_basic() {
        let mut test = setup();
        let account = test.requester.address();

        // Set up initial balance with deposit.
        let deposit_event = create_deposit_event(account, U256::from(100), 0, 1, 1);
        test.state.execute::<MockVerifier>(&deposit_event).unwrap();
        assert_account_balance(&test, account, U256::from(100));

        // Execute basic withdraw.
        let withdraw_event = create_withdraw_event(account, U256::from(60), 0, 2, 2);
        let receipt = test.state.execute::<MockVerifier>(&withdraw_event).unwrap();

        // Verify the balance was deducted correctly.
        assert_account_balance(&test, account, U256::from(40));
        assert_withdraw_receipt(&receipt, account, U256::from(60), 2);
        assert_state_counters(&test, 3, 3, 0, 2);
    }

    #[test]
    fn test_withdraw_partial() {
        let mut test = setup();
        let account = test.requester.address();

        // Set up initial balance with deposit.
        let deposit_event = create_deposit_event(account, U256::from(500), 0, 1, 1);
        test.state.execute::<MockVerifier>(&deposit_event).unwrap();

        // Execute first partial withdraw.
        let withdraw1 = create_withdraw_event(account, U256::from(100), 0, 2, 2);
        let receipt1 = test.state.execute::<MockVerifier>(&withdraw1).unwrap();
        assert_account_balance(&test, account, U256::from(400));
        assert_withdraw_receipt(&receipt1, account, U256::from(100), 2);

        // Execute second partial withdraw.
        let withdraw2 = create_withdraw_event(account, U256::from(200), 0, 3, 3);
        let receipt2 = test.state.execute::<MockVerifier>(&withdraw2).unwrap();
        assert_account_balance(&test, account, U256::from(200));
        assert_withdraw_receipt(&receipt2, account, U256::from(200), 3);

        // Execute third partial withdraw.
        let withdraw3 = create_withdraw_event(account, U256::from(50), 1, 1, 4);
        let receipt3 = test.state.execute::<MockVerifier>(&withdraw3).unwrap();
        assert_account_balance(&test, account, U256::from(150));
        assert_withdraw_receipt(&receipt3, account, U256::from(50), 4);
    }

    #[test]
    fn test_withdraw_full_balance_with_max() {
        let mut test = setup();
        let account = test.requester.address();

        // Set up initial balance with deposit.
        let initial_amount = U256::from(12345);
        let deposit_event = create_deposit_event(account, initial_amount, 0, 1, 1);
        test.state.execute::<MockVerifier>(&deposit_event).unwrap();
        assert_account_balance(&test, account, initial_amount);

        // Execute withdraw with U256::MAX to drain entire balance.
        let withdraw_event = create_withdraw_event(account, U256::MAX, 0, 2, 2);
        let receipt = test.state.execute::<MockVerifier>(&withdraw_event).unwrap();

        // Verify entire balance was withdrawn.
        assert_account_balance(&test, account, U256::ZERO);
        // Note: Receipt shows the original withdraw action amount (U256::MAX), not actual withdrawn amount.
        assert_withdraw_receipt(&receipt, account, U256::MAX, 2);
        assert_state_counters(&test, 3, 3, 0, 2);
    }

    #[test]
    fn test_withdraw_exact_balance() {
        let mut test = setup();
        let account = test.requester.address();

        // Set up initial balance with deposit.
        let amount = U256::from(789);
        let deposit_event = create_deposit_event(account, amount, 0, 1, 1);
        test.state.execute::<MockVerifier>(&deposit_event).unwrap();

        // Execute withdraw for exact balance amount.
        let withdraw_event = create_withdraw_event(account, amount, 0, 2, 2);
        let receipt = test.state.execute::<MockVerifier>(&withdraw_event).unwrap();

        // Verify exact amount was withdrawn, leaving zero balance.
        assert_account_balance(&test, account, U256::ZERO);
        assert_withdraw_receipt(&receipt, account, amount, 2);
    }

    #[test]
    fn test_withdraw_insufficient_balance() {
        let mut test = setup();
        let account = test.requester.address();

        // Set up initial balance with deposit.
        let deposit_event = create_deposit_event(account, U256::from(100), 0, 1, 1);
        test.state.execute::<MockVerifier>(&deposit_event).unwrap();

        // Try to withdraw more than balance.
        let withdraw_event = create_withdraw_event(account, U256::from(150), 0, 2, 2);
        let result = test.state.execute::<MockVerifier>(&withdraw_event);

        // Verify the correct revert error is returned.
        assert!(matches!(
            result,
            Err(VAppError::Revert(VAppRevert::InsufficientBalance {
                account: acc,
                amount,
                balance
            })) if acc == account && amount == U256::from(150) && balance == U256::from(100)
        ));

        // Verify state remains unchanged after error (onchain counters increment, but tx_id does not).
        assert_account_balance(&test, account, U256::from(100));
        assert_state_counters(&test, 2, 3, 0, 2);
    }

    #[test]
    fn test_withdraw_zero_balance_account() {
        let mut test = setup();
        let account = test.requester.address();

        // Try to withdraw from account with zero balance (no prior deposit).
        let withdraw_event = create_withdraw_event(account, U256::from(1), 0, 1, 1);
        let result = test.state.execute::<MockVerifier>(&withdraw_event);

        // Verify the correct revert error is returned.
        assert!(matches!(
            result,
            Err(VAppError::Revert(VAppRevert::InsufficientBalance {
                account: acc,
                amount,
                balance
            })) if acc == account && amount == U256::from(1) && balance == U256::ZERO
        ));

        // Verify state counters behavior for failed transaction (onchain counters increment, but tx_id does not).
        assert_state_counters(&test, 1, 2, 0, 1);
    }

    #[test]
    fn test_withdraw_onchain_tx_out_of_order() {
        let mut test = setup();
        let account = test.requester.address();

        // Set up initial balance and execute first withdraw.
        let deposit_event = create_deposit_event(account, U256::from(200), 0, 1, 1);
        test.state.execute::<MockVerifier>(&deposit_event).unwrap();

        let withdraw1 = create_withdraw_event(account, U256::from(50), 0, 2, 2);
        test.state.execute::<MockVerifier>(&withdraw1).unwrap();

        // Try to execute withdraw with wrong onchain_tx (should be 3, but using 5).
        let withdraw2 = create_withdraw_event(account, U256::from(50), 0, 3, 5);
        let result = test.state.execute::<MockVerifier>(&withdraw2);

        // Verify the correct panic error is returned.
        assert!(matches!(
            result,
            Err(VAppError::Panic(VAppPanic::OnchainTxOutOfOrder { expected: 3, actual: 5 }))
        ));

        // Verify state remains unchanged after error.
        assert_account_balance(&test, account, U256::from(150));
        assert_state_counters(&test, 3, 3, 0, 2);
    }

    #[test]
    fn test_withdraw_block_number_regression() {
        let mut test = setup();
        let account = test.requester.address();

        // Set up initial balance at block 10.
        let deposit_event = create_deposit_event(account, U256::from(200), 10, 1, 1);
        test.state.execute::<MockVerifier>(&deposit_event).unwrap();

        // Try to execute withdraw at earlier block (regression).
        let withdraw_event = create_withdraw_event(account, U256::from(50), 8, 1, 2);
        let result = test.state.execute::<MockVerifier>(&withdraw_event);

        // Verify the correct panic error is returned.
        assert!(matches!(
            result,
            Err(VAppError::Panic(VAppPanic::BlockNumberOutOfOrder { expected: 10, actual: 8 }))
        ));

        // Verify state remains unchanged after error.
        assert_account_balance(&test, account, U256::from(200));
        assert_state_counters(&test, 2, 2, 10, 1);
    }

    #[test]
    fn test_withdraw_log_index_out_of_order() {
        let mut test = setup();
        let account = test.requester.address();

        // Set up initial balance at block 0, log_index 10.
        let deposit_event = create_deposit_event(account, U256::from(200), 0, 10, 1);
        test.state.execute::<MockVerifier>(&deposit_event).unwrap();

        // Try to execute withdraw at same block with same log_index.
        let withdraw1 = create_withdraw_event(account, U256::from(50), 0, 10, 2);
        let result = test.state.execute::<MockVerifier>(&withdraw1);

        // Verify the correct panic error is returned.
        assert!(matches!(
            result,
            Err(VAppError::Panic(VAppPanic::LogIndexOutOfOrder { current: 10, next: 10 }))
        ));

        // Try with log_index lower than current.
        let withdraw2 = create_withdraw_event(account, U256::from(50), 0, 5, 2);
        let result = test.state.execute::<MockVerifier>(&withdraw2);

        // Verify the correct panic error is returned.
        assert!(matches!(
            result,
            Err(VAppError::Panic(VAppPanic::LogIndexOutOfOrder { current: 10, next: 5 }))
        ));

        // Verify state remains unchanged after error.
        assert_account_balance(&test, account, U256::from(200));
        assert_state_counters(&test, 2, 2, 0, 10);
    }

    #[test]
    fn test_withdraw_log_index_valid_progression() {
        let mut test = setup();
        let account = test.requester.address();

        // Set up initial balance at block 0, log_index 5.
        let deposit_event = create_deposit_event(account, U256::from(300), 0, 5, 1);
        test.state.execute::<MockVerifier>(&deposit_event).unwrap();

        // Execute withdraw at same block with higher log_index (valid).
        let withdraw1 = create_withdraw_event(account, U256::from(100), 0, 6, 2);
        let receipt1 = test.state.execute::<MockVerifier>(&withdraw1).unwrap();

        // Verify balance deduction and state updates.
        assert_account_balance(&test, account, U256::from(200));
        assert_withdraw_receipt(&receipt1, account, U256::from(100), 2);
        assert_state_counters(&test, 3, 3, 0, 6);

        // Execute withdraw at higher block (log_index can be anything).
        let withdraw2 = create_withdraw_event(account, U256::from(50), 1, 1, 3);
        let receipt2 = test.state.execute::<MockVerifier>(&withdraw2).unwrap();

        // Verify final state after block progression.
        assert_account_balance(&test, account, U256::from(150));
        assert_withdraw_receipt(&receipt2, account, U256::from(50), 3);
        assert_state_counters(&test, 4, 4, 1, 1);
    }

    #[test]
    fn test_create_prover_basic() {
        let mut test = setup();
        let prover_address = test.prover.address();
        let owner_address = test.requester.address();
        let staker_fee_bips = U256::from(500);

        // Execute basic create prover event.
        let event = create_create_prover_event(prover_address, owner_address, staker_fee_bips, 0, 1, 1);
        let receipt = test.state.execute::<MockVerifier>(&event).unwrap();

        // Verify the prover account was created correctly.
        assert_prover_account(&test, prover_address, owner_address, owner_address, staker_fee_bips);
        assert_create_prover_receipt(&receipt, prover_address, owner_address, staker_fee_bips, 1);
        assert_state_counters(&test, 2, 2, 0, 1);
    }

    #[test]
    fn test_create_prover_self_delegated() {
        let mut test = setup();
        let prover_owner = test.prover.address();
        let staker_fee_bips = U256::from(1000);

        // Execute create prover where owner = prover (self-delegated).
        let event = create_create_prover_event(prover_owner, prover_owner, staker_fee_bips, 0, 1, 1);
        let receipt = test.state.execute::<MockVerifier>(&event).unwrap();

        // Verify the prover is self-delegated (owner = signer = prover).
        assert_prover_account(&test, prover_owner, prover_owner, prover_owner, staker_fee_bips);
        assert_create_prover_receipt(&receipt, prover_owner, prover_owner, staker_fee_bips, 1);
    }

    #[test]
    fn test_create_prover_different_owner() {
        let mut test = setup();
        let prover_address = test.signers[0].address();
        let owner_address = test.signers[1].address();
        let staker_fee_bips = U256::from(250);

        // Execute create prover with different owner and prover addresses.
        let event = create_create_prover_event(prover_address, owner_address, staker_fee_bips, 0, 1, 1);
        let receipt = test.state.execute::<MockVerifier>(&event).unwrap();

        // Verify the prover account configuration.
        assert_prover_account(&test, prover_address, owner_address, owner_address, staker_fee_bips);
        assert_create_prover_receipt(&receipt, prover_address, owner_address, staker_fee_bips, 1);
    }

    #[test]
    fn test_create_prover_various_staker_fees() {
        let mut test = setup();

        // Test with zero staker fee.
        let prover1 = test.signers[0].address();
        let owner1 = test.signers[1].address();
        let event1 = create_create_prover_event(prover1, owner1, U256::ZERO, 0, 1, 1);
        let receipt1 = test.state.execute::<MockVerifier>(&event1).unwrap();
        assert_prover_account(&test, prover1, owner1, owner1, U256::ZERO);
        assert_create_prover_receipt(&receipt1, prover1, owner1, U256::ZERO, 1);

        // Test with 5% staker fee (500 basis points).
        let prover2 = test.signers[2].address();
        let owner2 = test.signers[3].address();
        let staker_fee_500 = U256::from(500);
        let event2 = create_create_prover_event(prover2, owner2, staker_fee_500, 0, 2, 2);
        let receipt2 = test.state.execute::<MockVerifier>(&event2).unwrap();
        assert_prover_account(&test, prover2, owner2, owner2, staker_fee_500);
        assert_create_prover_receipt(&receipt2, prover2, owner2, staker_fee_500, 2);

        // Test with 10% staker fee (1000 basis points).
        let prover3 = test.signers[4].address();
        let owner3 = test.signers[5].address();
        let staker_fee_1000 = U256::from(1000);
        let event3 = create_create_prover_event(prover3, owner3, staker_fee_1000, 1, 1, 3);
        let receipt3 = test.state.execute::<MockVerifier>(&event3).unwrap();
        assert_prover_account(&test, prover3, owner3, owner3, staker_fee_1000);
        assert_create_prover_receipt(&receipt3, prover3, owner3, staker_fee_1000, 3);

        // Test with 50% staker fee (5000 basis points).
        let prover4 = test.signers[6].address();
        let owner4 = test.signers[7].address();
        let staker_fee_5000 = U256::from(5000);
        let event4 = create_create_prover_event(prover4, owner4, staker_fee_5000, 1, 2, 4);
        let receipt4 = test.state.execute::<MockVerifier>(&event4).unwrap();
        assert_prover_account(&test, prover4, owner4, owner4, staker_fee_5000);
        assert_create_prover_receipt(&receipt4, prover4, owner4, staker_fee_5000, 4);

        // Verify state progression.
        assert_state_counters(&test, 5, 5, 1, 2);
    }

    #[test]
    fn test_create_prover_max_staker_fee() {
        let mut test = setup();
        let prover_address = test.prover.address();
        let owner_address = test.requester.address();

        // Test with maximum staker fee (100% = 10000 basis points).
        let max_staker_fee = U256::from(10000);
        let event = create_create_prover_event(prover_address, owner_address, max_staker_fee, 0, 1, 1);
        let receipt = test.state.execute::<MockVerifier>(&event).unwrap();

        // Verify maximum staker fee is accepted.
        assert_prover_account(&test, prover_address, owner_address, owner_address, max_staker_fee);
        assert_create_prover_receipt(&receipt, prover_address, owner_address, max_staker_fee, 1);
    }

    #[test]
    fn test_create_prover_multiple_provers() {
        let mut test = setup();

        // Create multiple provers sequentially.
        let prover1 = test.signers[0].address();
        let owner1 = test.signers[1].address();
        let event1 = create_create_prover_event(prover1, owner1, U256::from(100), 0, 1, 1);
        test.state.execute::<MockVerifier>(&event1).unwrap();

        let prover2 = test.signers[2].address();
        let owner2 = test.signers[3].address();
        let event2 = create_create_prover_event(prover2, owner2, U256::from(200), 0, 2, 2);
        test.state.execute::<MockVerifier>(&event2).unwrap();

        let prover3 = test.signers[4].address();
        let owner3 = test.signers[5].address();
        let event3 = create_create_prover_event(prover3, owner3, U256::from(300), 1, 1, 3);
        test.state.execute::<MockVerifier>(&event3).unwrap();

        // Verify all provers were created correctly.
        assert_prover_account(&test, prover1, owner1, owner1, U256::from(100));
        assert_prover_account(&test, prover2, owner2, owner2, U256::from(200));
        assert_prover_account(&test, prover3, owner3, owner3, U256::from(300));
        assert_state_counters(&test, 4, 4, 1, 1);
    }

    #[test]
    fn test_create_prover_onchain_tx_out_of_order() {
        let mut test = setup();
        let prover_address = test.prover.address();
        let owner_address = test.requester.address();

        // Execute first create prover.
        let event1 = create_create_prover_event(prover_address, owner_address, U256::from(500), 0, 1, 1);
        test.state.execute::<MockVerifier>(&event1).unwrap();

        // Try to execute create prover with wrong onchain_tx (should be 2, but using 4).
        let prover2 = test.signers[0].address();
        let owner2 = test.signers[1].address();
        let event2 = create_create_prover_event(prover2, owner2, U256::from(500), 0, 2, 4);
        let result = test.state.execute::<MockVerifier>(&event2);

        // Verify the correct panic error is returned.
        assert!(matches!(
            result,
            Err(VAppError::Panic(VAppPanic::OnchainTxOutOfOrder { expected: 2, actual: 4 }))
        ));

        // Verify state remains unchanged after error.
        assert_prover_account(&test, prover_address, owner_address, owner_address, U256::from(500));
        assert_state_counters(&test, 2, 2, 0, 1);
    }

    #[test]
    fn test_create_prover_block_number_regression() {
        let mut test = setup();
        let prover_address = test.prover.address();
        let owner_address = test.requester.address();

        // Execute first create prover at block 15.
        let event1 = create_create_prover_event(prover_address, owner_address, U256::from(500), 15, 1, 1);
        test.state.execute::<MockVerifier>(&event1).unwrap();

        // Try to execute create prover at earlier block (regression).
        let prover2 = test.signers[0].address();
        let owner2 = test.signers[1].address();
        let event2 = create_create_prover_event(prover2, owner2, U256::from(500), 10, 1, 2);
        let result = test.state.execute::<MockVerifier>(&event2);

        // Verify the correct panic error is returned.
        assert!(matches!(
            result,
            Err(VAppError::Panic(VAppPanic::BlockNumberOutOfOrder { expected: 15, actual: 10 }))
        ));

        // Verify state remains unchanged after error.
        assert_prover_account(&test, prover_address, owner_address, owner_address, U256::from(500));
        assert_state_counters(&test, 2, 2, 15, 1);
    }

    #[test]
    fn test_create_prover_log_index_out_of_order() {
        let mut test = setup();
        let prover_address = test.prover.address();
        let owner_address = test.requester.address();

        // Execute first create prover at block 0, log_index 20.
        let event1 = create_create_prover_event(prover_address, owner_address, U256::from(500), 0, 20, 1);
        test.state.execute::<MockVerifier>(&event1).unwrap();

        // Try to execute create prover at same block with same log_index.
        let prover2 = test.signers[0].address();
        let owner2 = test.signers[1].address();
        let event2 = create_create_prover_event(prover2, owner2, U256::from(500), 0, 20, 2);
        let result = test.state.execute::<MockVerifier>(&event2);

        // Verify the correct panic error is returned.
        assert!(matches!(
            result,
            Err(VAppError::Panic(VAppPanic::LogIndexOutOfOrder { current: 20, next: 20 }))
        ));

        // Try with log_index lower than current.
        let event3 = create_create_prover_event(prover2, owner2, U256::from(500), 0, 15, 2);
        let result = test.state.execute::<MockVerifier>(&event3);

        // Verify the correct panic error is returned.
        assert!(matches!(
            result,
            Err(VAppError::Panic(VAppPanic::LogIndexOutOfOrder { current: 20, next: 15 }))
        ));

        // Verify state remains unchanged after error.
        assert_prover_account(&test, prover_address, owner_address, owner_address, U256::from(500));
        assert_state_counters(&test, 2, 2, 0, 20);
    }

    #[test]
    fn test_create_prover_log_index_valid_progression() {
        let mut test = setup();
        let prover1 = test.prover.address();
        let owner1 = test.requester.address();

        // Execute first create prover at block 0, log_index 10.
        let event1 = create_create_prover_event(prover1, owner1, U256::from(500), 0, 10, 1);
        test.state.execute::<MockVerifier>(&event1).unwrap();

        // Execute second create prover at same block with higher log_index (valid).
        let prover2 = test.signers[0].address();
        let owner2 = test.signers[1].address();
        let event2 = create_create_prover_event(prover2, owner2, U256::from(750), 0, 11, 2);
        let receipt2 = test.state.execute::<MockVerifier>(&event2).unwrap();

        // Verify both provers and state updates.
        assert_prover_account(&test, prover1, owner1, owner1, U256::from(500));
        assert_prover_account(&test, prover2, owner2, owner2, U256::from(750));
        assert_create_prover_receipt(&receipt2, prover2, owner2, U256::from(750), 2);
        assert_state_counters(&test, 3, 3, 0, 11);

        // Execute third create prover at higher block (log_index can be anything).
        let prover3 = test.signers[2].address();
        let owner3 = test.signers[3].address();
        let event3 = create_create_prover_event(prover3, owner3, U256::from(1000), 1, 1, 3);
        let receipt3 = test.state.execute::<MockVerifier>(&event3).unwrap();

        // Verify final state after block progression.
        assert_prover_account(&test, prover3, owner3, owner3, U256::from(1000));
        assert_create_prover_receipt(&receipt3, prover3, owner3, U256::from(1000), 3);
        assert_state_counters(&test, 4, 4, 1, 1);
    }

    #[test]
    fn test_clear() {
        let mut test = setup();

        // Local signers for this test.
        let requester_signer = &test.requester;
        let bidder_signer = &test.prover;
        let fulfiller_signer = &test.prover;
        let settle_signer = &test.auctioneer;
        let executor_signer = &test.executor;
        let verifier_signer = &test.verifier;

        // Deposit event
        let event = VAppTransaction::Deposit(OnchainTransaction {
            tx_hash: None,
            block: 0,
            log_index: 1,
            onchain_tx: 1,
            action: Deposit { account: requester_signer.address(), amount: U256::from(100e6) },
        });
        test.state.execute::<MockVerifier>(&event).unwrap();

        // Set up prover with delegated signer.
        let prover_event = VAppTransaction::CreateProver(OnchainTransaction {
            tx_hash: None,
            block: 1,
            log_index: 2,
            onchain_tx: 2,
            action: CreateProver {
                prover: bidder_signer.address(),
                owner: bidder_signer.address(), // Self-delegated
                stakerFeeBips: U256::from(0),
            },
        });
        test.state.execute::<MockVerifier>(&prover_event).unwrap();

        let account_address: Address = requester_signer.address();
        assert_eq!(
            test.state.accounts.get(&account_address).unwrap().get_balance(),
            U256::from(100e6),
        );

        let request_body = RequestProofRequestBody {
            nonce: 1,
            vk_hash: hex::decode(
                "005b97bb81b9ed64f9321049013a56d9633c115b076ae4144f2622d0da13d683",
            )
            .unwrap(),
            version: "sp1-v3.0.0".to_string(),
            mode: spn_network_types::ProofMode::Groth16 as i32,
            strategy: FulfillmentStrategy::Auction.into(),
            stdin_uri: "s3://spn-artifacts-production3/stdins/artifact_01jqcgtjr7es883amkx30sqkg9"
                .to_string(),
            deadline: 1000,
            cycle_limit: 1000,
            gas_limit: 10000,
            min_auction_period: 0,
            whitelist: vec![],
            domain: SPN_SEPOLIA_V1_DOMAIN.to_vec(),
            auctioneer: test.auctioneer.address().to_vec(),
            executor: test.executor.address().to_vec(),
            verifier: test.verifier.address().to_vec(),
            public_values_hash: None,
            base_fee: "0".to_string(),
            max_price_per_pgu: "1000000000000000000".to_string(),
        };
        let proof = vec![
            17, 182, 160, 157, 40, 242, 129, 34, 129, 204, 131, 191, 247, 169, 187, 69, 119, 90,
            227, 82, 88, 207, 116, 44, 34, 113, 109, 48, 85, 75, 45, 95, 111, 205, 161, 129, 18,
            175, 110, 238, 88, 46, 229, 251, 208, 212, 65, 200, 159, 144, 27, 252, 203, 116, 11,
            243, 245, 60, 193, 115, 19, 186, 8, 52, 108, 195, 11, 30, 31, 12, 176, 52, 162, 22,
            135, 115, 165, 161, 191, 161, 111, 60, 246, 104, 207, 32, 178, 36, 15, 23, 97, 222,
            253, 16, 81, 231, 255, 67, 0, 59, 15, 140, 83, 36, 88, 90, 163, 253, 245, 233, 211,
            239, 210, 154, 16, 4, 68, 40, 3, 4, 146, 9, 82, 199, 52, 237, 208, 4, 31, 61, 16, 233,
            26, 211, 199, 211, 213, 71, 232, 95, 36, 28, 213, 124, 207, 120, 62, 150, 161, 119,
            224, 89, 221, 37, 165, 134, 252, 213, 37, 150, 44, 153, 59, 188, 35, 232, 251, 106, 5,
            232, 17, 110, 39, 254, 70, 27, 250, 124, 44, 184, 109, 168, 69, 19, 165, 122, 114, 91,
            114, 83, 16, 10, 189, 128, 253, 33, 43, 212, 183, 241, 164, 29, 248, 49, 41, 241, 24,
            30, 169, 213, 223, 96, 237, 22, 30, 28, 84, 199, 234, 131, 201, 201, 249, 192, 192, 77,
            227, 62, 45, 12, 12, 93, 125, 238, 122, 154, 204, 35, 9, 170, 231, 68, 120, 183, 29,
            140, 40, 165, 151, 14, 252, 76, 87, 38, 216, 68, 14, 33, 176, 17,
        ];

        // Clear event
        let event = clear_vapp_event(
            requester_signer, // requester
            bidder_signer,    // bidder
            fulfiller_signer, // fulfiller
            settle_signer,    // settle_signer
            executor_signer,  // executor
            verifier_signer,  // verifier
            request_body,
            1,                // bid_nonce
            U256::from(10e6), // bid_amount
            1,                // settle_nonce
            1,                // fulfill_nonce
            proof,
            1, // execute_nonce
            ExecutionStatus::Executed,
            Some([0; 8]), // vk_digest_array
            None,         // pv_digest_array
        );
        test.state.execute::<MockVerifier>(&event).unwrap();

        assert_eq!(
            test.state.accounts.get(&account_address).unwrap().get_balance(),
            U256::from(90e6 as u64),
        );
    }

    #[test]
    #[allow(clippy::too_many_lines)]
    fn test_complex_workflow() {
        let mut test = setup();

        // Counters for maintaining event ordering.
        let mut receipt_counter = 0;
        let mut log_index_counter = 0;
        let mut block_counter = 0;

        // Additional signers for this complex workflow.
        let user1_signer = signer("user1");
        let user2_signer = signer("user2");
        let user3_signer = signer("user3");
        let prover1_signer = signer("prover1");
        let prover2_signer = signer("prover2");
        let delegated_prover1_signer = signer("delegated_prover1");
        let delegated_prover2_signer = signer("delegated_prover2");

        // Helper to create events with proper ordering.
        let mut next_receipt = || {
            receipt_counter += 1;
            receipt_counter
        };
        let mut next_log_index = || {
            log_index_counter += 1;
            log_index_counter
        };
        let mut next_block = || {
            block_counter += 1;
            block_counter
        };

        // === SETUP PHASE: Multiple deposits and delegated signers ===

        let events = vec![
            // User1 deposits 1000 tokens.
            VAppTransaction::Deposit(OnchainTransaction {
                tx_hash: None,
                block: next_block(),
                log_index: next_log_index(),
                onchain_tx: next_receipt(),
                action: Deposit { account: user1_signer.address(), amount: U256::from(1000e6) },
            }),
            // User2 deposits 500 tokens.
            VAppTransaction::Deposit(OnchainTransaction {
                tx_hash: None,
                block: next_block(),
                log_index: next_log_index(),
                onchain_tx: next_receipt(),
                action: Deposit { account: user2_signer.address(), amount: U256::from(500e6) },
            }),
            // User3 deposits 750 tokens.
            VAppTransaction::Deposit(OnchainTransaction {
                tx_hash: None,
                block: next_block(),
                log_index: next_log_index(),
                onchain_tx: next_receipt(),
                action: Deposit { account: user3_signer.address(), amount: U256::from(750e6) },
            }),
            // User1 adds delegated signer1.
            VAppTransaction::CreateProver(OnchainTransaction {
                tx_hash: None,
                block: next_block(),
                log_index: next_log_index(),
                onchain_tx: next_receipt(),
                action: CreateProver {
                    prover: prover1_signer.address(),
                    owner: delegated_prover1_signer.address(),
                    stakerFeeBips: U256::from(0),
                },
            }),
            // User2 adds delegated signer2.
            VAppTransaction::CreateProver(OnchainTransaction {
                tx_hash: None,
                block: next_block(),
                log_index: next_log_index(),
                onchain_tx: next_receipt(),
                action: CreateProver {
                    prover: prover2_signer.address(),
                    owner: delegated_prover2_signer.address(),
                    stakerFeeBips: U256::from(0),
                },
            }),
        ];

        // Apply setup events.
        let mut action_count = 0;
        for event in events {
            if let Ok(Some(_)) = test.state.execute::<MockVerifier>(&event) {
                action_count += 1;
            }
        }

        // Verify initial state after deposits and delegations.
        assert_eq!(
            test.state.accounts.get(&user1_signer.address()).unwrap().get_balance(),
            U256::from(1000e6)
        );
        assert_eq!(
            test.state.accounts.get(&user2_signer.address()).unwrap().get_balance(),
            U256::from(500e6)
        );
        assert_eq!(
            test.state.accounts.get(&user3_signer.address()).unwrap().get_balance(),
            U256::from(750e6)
        );
        assert_eq!(action_count, 5);

        // === CLEAR PHASE: Multiple proof clearing operations ===

        let proof = vec![
            17, 182, 160, 157, 40, 242, 129, 34, 129, 204, 131, 191, 247, 169, 187, 69, 119, 90,
            227, 82, 88, 207, 116, 44, 34, 113, 109, 48, 85, 75, 45, 95, 111, 205, 161, 129, 18,
            175, 110, 238, 88, 46, 229, 251, 208, 212, 65, 200, 159, 144, 27, 252, 203, 116, 11,
            243, 245, 60, 193, 115, 19, 186, 8, 52, 108, 195, 11, 30, 31, 12, 176, 52, 162, 22,
            135, 115, 165, 161, 191, 161, 111, 60, 246, 104, 207, 32, 178, 36, 15, 23, 97, 222,
            253, 16, 81, 231, 255, 67, 0, 59, 15, 140, 83, 36, 88, 90, 163, 253, 245, 233, 211,
            239, 210, 154, 16, 4, 68, 40, 3, 4, 146, 9, 82, 199, 52, 237, 208, 4, 31, 61, 16, 233,
            26, 211, 199, 211, 213, 71, 232, 95, 36, 28, 213, 124, 207, 120, 62, 150, 161, 119,
            224, 89, 221, 37, 165, 134, 252, 213, 37, 150, 44, 153, 59, 188, 35, 232, 251, 106, 5,
            232, 17, 110, 39, 254, 70, 27, 250, 124, 44, 184, 109, 168, 69, 19, 165, 122, 114, 91,
            114, 83, 16, 10, 189, 128, 253, 33, 43, 212, 183, 241, 164, 29, 248, 49, 41, 241, 24,
            30, 169, 213, 223, 96, 237, 22, 30, 28, 84, 199, 234, 131, 201, 201, 249, 192, 192, 77,
            227, 62, 45, 12, 12, 93, 125, 238, 122, 154, 204, 35, 9, 170, 231, 68, 120, 183, 29,
            140, 40, 165, 151, 14, 252, 76, 87, 38, 216, 68, 14, 33, 176, 17,
        ];

        // Clear 1: User1 requests proof, prover1 fulfills (cost: 100 tokens)
        let request_body1 = RequestProofRequestBody {
            nonce: 1,
            vk_hash: hex::decode(
                "005b97bb81b9ed64f9321049013a56d9633c115b076ae4144f2622d0da13d683",
            )
            .unwrap(),
            version: "sp1-v3.0.0".to_string(),
            mode: spn_network_types::ProofMode::Groth16 as i32,
            strategy: FulfillmentStrategy::Auction.into(),
            stdin_uri: "s3://spn-artifacts-production3/stdins/artifact_01jqcgtjr7es883amkx30sqkg9"
                .to_string(),
            deadline: 1000,
            cycle_limit: 1000,
            gas_limit: 10000,
            min_auction_period: 0,
            whitelist: vec![],
            domain: SPN_SEPOLIA_V1_DOMAIN.to_vec(),
            auctioneer: test.auctioneer.address().to_vec(),
            executor: test.executor.address().to_vec(),
            verifier: test.verifier.address().to_vec(),
            public_values_hash: None,
            base_fee: "0".to_string(),
            max_price_per_pgu: "1000000000000000000".to_string(),
        };

        let clear_event1 = clear_vapp_event(
            &user1_signer,             // requester
            &prover1_signer,           // bidder
            &delegated_prover1_signer, // prover1 (fulfiller)
            &test.auctioneer,          // settle_signer
            &test.executor,            // executor
            &test.verifier,            // verifier
            request_body1,
            1,                 // bid_nonce
            U256::from(100e6), // bid amount
            1,                 // settle_nonce
            1,                 // fulfill_nonce
            proof.clone(),
            1, // execute_nonce
            ExecutionStatus::Executed,
            Some([0; 8]), // vk_digest_array
            None,         // pv_digest_array
        );

        test.state.execute::<MockVerifier>(&clear_event1).unwrap();

        // Verify balances after first clear.
        assert_eq!(
            test.state.accounts.get(&user1_signer.address()).unwrap().get_balance(),
            U256::from(900e6)
        );
        assert_eq!(
            test.state.accounts.get(&delegated_prover1_signer.address()).unwrap().get_balance(),
            U256::from(100000000)
        );
    }

    #[test]
    fn test_merkle_verify_none_value_succeeds() {
        use crate::{
            merkle::{MerkleProof, MerkleStorage},
            sol::Account,
        };
        use alloy_primitives::{address, Address, Keccak256};

        // Create an empty Merkle tree over Account leaves.
        let mut tree: MerkleStorage<Address, Account> = MerkleStorage::new();

        // Pick an address with no corresponding leaf.
        let addr = address!("0x0000000000000000000000000000000000000003");

        // Generate the proof – since the leaf is empty, `proof.value` will be `None`.
        let proof: MerkleProof<Address, Account, Keccak256> = tree.proof(&addr).unwrap();

        // Sanity-check that the proof's value is indeed `None`.
        assert!(proof.value.is_none(), "expected proof.value to be None for an empty leaf");

        // Verify the proof against the (empty) root. This should succeed.
        let root = tree.root();
        assert!(
            MerkleStorage::<Address, Account>::verify_proof(root, &proof).is_ok(),
            "proof with None value should verify for non-existent leaf"
        );
    }

    #[test]
    fn test_transfer_basic() {
        let mut test = setup();
        let from_signer = &test.signers[0];
        let to_address = test.signers[1].address();
        let amount = U256::from(100);

        // Set up initial balance for sender.
        let deposit_event = create_deposit_event(from_signer.address(), U256::from(500), 0, 1, 1);
        test.state.execute::<MockVerifier>(&deposit_event).unwrap();
        assert_account_balance(&test, from_signer.address(), U256::from(500));

        // Execute transfer.
        let transfer_event = create_transfer_event(from_signer, to_address, amount, 1);
        let result = test.state.execute::<MockVerifier>(&transfer_event).unwrap();

        // Verify transfer does not return a receipt.
        assert!(result.is_none());

        // Verify balances were updated correctly.
        assert_account_balance(&test, from_signer.address(), U256::from(400));
        assert_account_balance(&test, to_address, amount);

        // Verify state counters (only tx_id increments for off-chain transactions).
        assert_state_counters(&test, 3, 2, 0, 1);
    }

    #[test]
    fn test_transfer_self_transfer() {
        let mut test = setup();
        let signer = &test.signers[0];
        let amount = U256::from(100);

        // Set up initial balance.
        let deposit_event = create_deposit_event(signer.address(), U256::from(500), 0, 1, 1);
        test.state.execute::<MockVerifier>(&deposit_event).unwrap();

        // Execute self-transfer.
        let transfer_event = create_transfer_event(signer, signer.address(), amount, 1);
        let result = test.state.execute::<MockVerifier>(&transfer_event).unwrap();

        // Verify transfer succeeds and balance remains unchanged.
        assert!(result.is_none());
        assert_account_balance(&test, signer.address(), U256::from(500));
    }

    #[test]
    fn test_transfer_multiple_transfers() {
        let mut test = setup();
        let from_signer = &test.signers[0];
        let to1 = test.signers[1].address();
        let to2 = test.signers[2].address();
        let to3 = test.signers[3].address();

        // Set up initial balance.
        let deposit_event = create_deposit_event(from_signer.address(), U256::from(1000), 0, 1, 1);
        test.state.execute::<MockVerifier>(&deposit_event).unwrap();

        // Execute first transfer.
        let transfer1 = create_transfer_event(from_signer, to1, U256::from(200), 1);
        test.state.execute::<MockVerifier>(&transfer1).unwrap();
        assert_account_balance(&test, from_signer.address(), U256::from(800));
        assert_account_balance(&test, to1, U256::from(200));

        // Execute second transfer.
        let transfer2 = create_transfer_event(from_signer, to2, U256::from(300), 2);
        test.state.execute::<MockVerifier>(&transfer2).unwrap();
        assert_account_balance(&test, from_signer.address(), U256::from(500));
        assert_account_balance(&test, to2, U256::from(300));

        // Execute third transfer.
        let transfer3 = create_transfer_event(from_signer, to3, U256::from(150), 3);
        test.state.execute::<MockVerifier>(&transfer3).unwrap();
        assert_account_balance(&test, from_signer.address(), U256::from(350));
        assert_account_balance(&test, to3, U256::from(150));

        // Verify state progression.
        assert_state_counters(&test, 5, 2, 0, 1);
    }

    #[test]
    fn test_transfer_to_new_account() {
        let mut test = setup();
        let from_signer = &test.signers[0];
        let new_account = test.signers[1].address();
        let amount = U256::from(250);

        // Set up initial balance.
        let deposit_event = create_deposit_event(from_signer.address(), U256::from(500), 0, 1, 1);
        test.state.execute::<MockVerifier>(&deposit_event).unwrap();

        // Verify new account has zero balance initially.
        assert_account_balance(&test, new_account, U256::ZERO);

        // Execute transfer to new account.
        let transfer_event = create_transfer_event(from_signer, new_account, amount, 1);
        test.state.execute::<MockVerifier>(&transfer_event).unwrap();

        // Verify new account was created with correct balance.
        assert_account_balance(&test, from_signer.address(), U256::from(250));
        assert_account_balance(&test, new_account, amount);
    }

    #[test]
    fn test_transfer_entire_balance() {
        let mut test = setup();
        let from_signer = &test.signers[0];
        let to_address = test.signers[1].address();
        let initial_balance = U256::from(789);

        // Set up initial balance.
        let deposit_event = create_deposit_event(from_signer.address(), initial_balance, 0, 1, 1);
        test.state.execute::<MockVerifier>(&deposit_event).unwrap();

        // Execute transfer of entire balance.
        let transfer_event = create_transfer_event(from_signer, to_address, initial_balance, 1);
        test.state.execute::<MockVerifier>(&transfer_event).unwrap();

        // Verify entire balance was transferred.
        assert_account_balance(&test, from_signer.address(), U256::ZERO);
        assert_account_balance(&test, to_address, initial_balance);
    }

    #[test]
    fn test_transfer_zero_amount() {
        let mut test = setup();
        let from_signer = &test.signers[0];
        let to_address = test.signers[1].address();

        // Set up initial balance.
        let deposit_event = create_deposit_event(from_signer.address(), U256::from(500), 0, 1, 1);
        test.state.execute::<MockVerifier>(&deposit_event).unwrap();

        // Execute zero amount transfer.
        let transfer_event = create_transfer_event(from_signer, to_address, U256::ZERO, 1);
        test.state.execute::<MockVerifier>(&transfer_event).unwrap();

        // Verify balances remain unchanged.
        assert_account_balance(&test, from_signer.address(), U256::from(500));
        assert_account_balance(&test, to_address, U256::ZERO);
    }

    #[test]
    fn test_transfer_insufficient_balance() {
        let mut test = setup();
        let from_signer = &test.signers[0];
        let to_address = test.signers[1].address();

        // Set up initial balance.
        let deposit_event = create_deposit_event(from_signer.address(), U256::from(100), 0, 1, 1);
        test.state.execute::<MockVerifier>(&deposit_event).unwrap();

        // Try to transfer more than balance.
        let transfer_event = create_transfer_event(from_signer, to_address, U256::from(150), 1);
        let result = test.state.execute::<MockVerifier>(&transfer_event);

        // Verify the correct panic error is returned.
        assert!(matches!(
            result,
            Err(VAppError::Panic(VAppPanic::InsufficientBalance {
                account,
                amount,
                balance
            })) if account == from_signer.address() && amount == U256::from(150) && balance == U256::from(100)
        ));

        // Verify balances remain unchanged.
        assert_account_balance(&test, from_signer.address(), U256::from(100));
        assert_account_balance(&test, to_address, U256::ZERO);
        assert_state_counters(&test, 2, 2, 0, 1);
    }

    #[test]
    fn test_transfer_from_zero_balance_account() {
        let mut test = setup();
        let from_signer = &test.signers[0];
        let to_address = test.signers[1].address();

        // Try to transfer from account with zero balance.
        let transfer_event = create_transfer_event(from_signer, to_address, U256::from(1), 1);
        let result = test.state.execute::<MockVerifier>(&transfer_event);

        // Verify the correct panic error is returned.
        assert!(matches!(
            result,
            Err(VAppError::Panic(VAppPanic::InsufficientBalance {
                account,
                amount,
                balance
            })) if account == from_signer.address() && amount == U256::from(1) && balance == U256::ZERO
        ));

        // Verify state remains unchanged.
        assert_state_counters(&test, 1, 1, 0, 0);
    }

    #[test]
    fn test_transfer_from_signer_without_balance() {
        let mut test = setup();
        let from_signer_with_balance = &test.signers[0];
        let from_signer_without_balance = &test.signers[1];
        let to_address = test.signers[2].address();

        // Set up initial balance for one signer.
        let deposit_event = create_deposit_event(from_signer_with_balance.address(), U256::from(500), 0, 1, 1);
        test.state.execute::<MockVerifier>(&deposit_event).unwrap();

        // Create transfer signed by signer without balance (this tests the logic properly).
        let transfer_event = create_transfer_event(from_signer_without_balance, to_address, U256::from(100), 1);
        let result = test.state.execute::<MockVerifier>(&transfer_event);

        // Verify the correct panic error is returned (signer has insufficient balance).
        assert!(matches!(
            result,
            Err(VAppError::Panic(VAppPanic::InsufficientBalance {
                account,
                amount,
                balance
            })) if account == from_signer_without_balance.address() && amount == U256::from(100) && balance == U256::ZERO
        ));

        // Verify balances remain unchanged.
        assert_account_balance(&test, from_signer_with_balance.address(), U256::from(500));
        assert_account_balance(&test, from_signer_without_balance.address(), U256::ZERO);
        assert_account_balance(&test, to_address, U256::ZERO);
    }

    #[test]
    fn test_transfer_domain_mismatch() {
        let mut test = setup();
        let from_signer = &test.signers[0];
        let to_address = test.signers[1].address();

        // Set up initial balance.
        let deposit_event = create_deposit_event(from_signer.address(), U256::from(500), 0, 1, 1);
        test.state.execute::<MockVerifier>(&deposit_event).unwrap();

        // Try to transfer with wrong domain.
        let wrong_domain = [1u8; 32];
        let transfer_event = create_transfer_event_with_domain(
            from_signer,
            to_address,
            U256::from(100),
            1,
            wrong_domain,
        );
        let result = test.state.execute::<MockVerifier>(&transfer_event);

        // Verify the correct panic error is returned.
        assert!(matches!(
            result,
            Err(VAppError::Panic(VAppPanic::DomainMismatch { .. }))
        ));

        // Verify balances remain unchanged.
        assert_account_balance(&test, from_signer.address(), U256::from(500));
        assert_account_balance(&test, to_address, U256::ZERO);
    }

    #[test]
    fn test_transfer_missing_body() {
        let mut test = setup();

        // Try to execute transfer with missing body.
        let transfer_event = create_transfer_event_missing_body();
        let result = test.state.execute::<MockVerifier>(&transfer_event);

        // Verify the correct panic error is returned.
        assert!(matches!(
            result,
            Err(VAppError::Panic(VAppPanic::MissingProtoBody))
        ));

        // Verify state remains unchanged.
        assert_state_counters(&test, 1, 1, 0, 0);
    }

    #[test]
    fn test_transfer_invalid_amount_parsing() {
        let mut test = setup();
        let from_signer = &test.signers[0];
        let to_address = test.signers[1].address();

        // Set up initial balance.
        let deposit_event = create_deposit_event(from_signer.address(), U256::from(500), 0, 1, 1);
        test.state.execute::<MockVerifier>(&deposit_event).unwrap();

        // Try to transfer with invalid amount string.
        let transfer_event = create_transfer_event_invalid_amount(from_signer, to_address, "invalid_amount", 1);
        let result = test.state.execute::<MockVerifier>(&transfer_event);

        // Verify the correct panic error is returned.
        assert!(matches!(
            result,
            Err(VAppError::Panic(VAppPanic::InvalidTransferAmount { .. }))
        ));

        // Verify balances remain unchanged.
        assert_account_balance(&test, from_signer.address(), U256::from(500));
        assert_account_balance(&test, to_address, U256::ZERO);
    }

    #[test]
    fn test_transfer_invalid_to_address() {
        let mut test = setup();
        let from_signer = &test.signers[0];

        // Set up initial balance.
        let deposit_event = create_deposit_event(from_signer.address(), U256::from(500), 0, 1, 1);
        test.state.execute::<MockVerifier>(&deposit_event).unwrap();

        // Create transfer with invalid to address (too short).
        use spn_network_types::{MessageFormat, TransferRequest, TransferRequestBody};
        
        let body = TransferRequestBody {
            nonce: 1,
            to: vec![0x12, 0x34], // Invalid - too short
            amount: U256::from(100).to_string(),
            domain: spn_utils::SPN_SEPOLIA_V1_DOMAIN.to_vec(),
        };
        let signature = proto_sign(from_signer, &body);

        let transfer_event = VAppTransaction::Transfer(TransferTransaction {
            transfer: TransferRequest {
                format: MessageFormat::Binary.into(),
                body: Some(body),
                signature: signature.as_bytes().to_vec(),
            },
        });

        let result = test.state.execute::<MockVerifier>(&transfer_event);

        // Verify the correct panic error is returned.
        assert!(matches!(
            result,
            Err(VAppError::Panic(VAppPanic::AddressDeserializationFailed))
        ));

        // Verify balance remains unchanged.
        assert_account_balance(&test, from_signer.address(), U256::from(500));
    }

    #[test]
    fn test_delegate_basic() {
        let mut test = setup();
        let prover_owner = &test.signers[0];
        let prover_address = test.signers[1].address();
        let delegate_address = test.signers[2].address();

        // Create prover first.
        let create_prover_event = create_create_prover_event(
            prover_address,
            prover_owner.address(),
            U256::from(500),
            0,
            1,
            1,
        );
        test.state.execute::<MockVerifier>(&create_prover_event).unwrap();

        // Verify initial signer is the owner.
        assert_prover_signer(&test, prover_address, prover_owner.address());

        // Execute delegation.
        let delegate_event = create_delegate_event(prover_owner, prover_address, delegate_address, 1);
        let result = test.state.execute::<MockVerifier>(&delegate_event).unwrap();

        // Verify delegation does not return a receipt.
        assert!(result.is_none());

        // Verify the signer was updated.
        assert_prover_signer(&test, prover_address, delegate_address);

        // Verify state counters (only tx_id increments for off-chain transactions).
        assert_state_counters(&test, 3, 2, 0, 1);
    }

    #[test]
    fn test_delegate_self_delegation() {
        let mut test = setup();
        let prover_owner = &test.signers[0];
        let prover_address = test.signers[1].address();

        // Create prover first.
        let create_prover_event = create_create_prover_event(
            prover_address,
            prover_owner.address(),
            U256::from(500),
            0,
            1,
            1,
        );
        test.state.execute::<MockVerifier>(&create_prover_event).unwrap();

        // Execute self-delegation (owner delegates to themselves).
        let delegate_event = create_delegate_event(prover_owner, prover_address, prover_owner.address(), 1);
        let result = test.state.execute::<MockVerifier>(&delegate_event).unwrap();

        // Verify delegation succeeds and signer remains the owner.
        assert!(result.is_none());
        assert_prover_signer(&test, prover_address, prover_owner.address());
    }

    #[test]
    fn test_delegate_multiple_delegations() {
        let mut test = setup();
        let prover_owner = &test.signers[0];
        let prover_address = test.signers[1].address();
        let delegate1 = test.signers[2].address();
        let delegate2 = test.signers[3].address();
        let delegate3 = test.signers[4].address();

        // Create prover first.
        let create_prover_event = create_create_prover_event(
            prover_address,
            prover_owner.address(),
            U256::from(500),
            0,
            1,
            1,
        );
        test.state.execute::<MockVerifier>(&create_prover_event).unwrap();

        // Execute first delegation.
        let delegate_event1 = create_delegate_event(prover_owner, prover_address, delegate1, 1);
        test.state.execute::<MockVerifier>(&delegate_event1).unwrap();
        assert_prover_signer(&test, prover_address, delegate1);

        // Execute second delegation (replaces first).
        let delegate_event2 = create_delegate_event(prover_owner, prover_address, delegate2, 2);
        test.state.execute::<MockVerifier>(&delegate_event2).unwrap();
        assert_prover_signer(&test, prover_address, delegate2);

        // Execute third delegation (replaces second).
        let delegate_event3 = create_delegate_event(prover_owner, prover_address, delegate3, 3);
        test.state.execute::<MockVerifier>(&delegate_event3).unwrap();
        assert_prover_signer(&test, prover_address, delegate3);

        // Verify state progression.
        assert_state_counters(&test, 5, 2, 0, 1);
    }

    #[test]
    fn test_delegate_multiple_provers() {
        let mut test = setup();
        let owner1 = &test.signers[0];
        let owner2 = &test.signers[1];
        let prover1 = test.signers[2].address();
        let prover2 = test.signers[3].address();
        let delegate1 = test.signers[4].address();
        let delegate2 = test.signers[5].address();

        // Create first prover.
        let create_prover1 = create_create_prover_event(prover1, owner1.address(), U256::from(500), 0, 1, 1);
        test.state.execute::<MockVerifier>(&create_prover1).unwrap();

        // Create second prover.
        let create_prover2 = create_create_prover_event(prover2, owner2.address(), U256::from(750), 0, 2, 2);
        test.state.execute::<MockVerifier>(&create_prover2).unwrap();

        // Delegate for first prover.
        let delegate_event1 = create_delegate_event(owner1, prover1, delegate1, 1);
        test.state.execute::<MockVerifier>(&delegate_event1).unwrap();

        // Delegate for second prover.
        let delegate_event2 = create_delegate_event(owner2, prover2, delegate2, 1);
        test.state.execute::<MockVerifier>(&delegate_event2).unwrap();

        // Verify both delegations.
        assert_prover_signer(&test, prover1, delegate1);
        assert_prover_signer(&test, prover2, delegate2);
    }

    #[test]
    fn test_delegate_non_existent_prover() {
        let mut test = setup();
        let prover_owner = &test.signers[0];
        let non_existent_prover = test.signers[1].address();
        let delegate_address = test.signers[2].address();

        // Try to delegate for non-existent prover.
        let delegate_event = create_delegate_event(prover_owner, non_existent_prover, delegate_address, 1);
        let result = test.state.execute::<MockVerifier>(&delegate_event);

        // Verify the correct revert error is returned.
        assert!(matches!(
            result,
            Err(VAppError::Revert(VAppRevert::ProverDoesNotExist { prover })) if prover == non_existent_prover
        ));

        // Verify state remains unchanged.
        assert_state_counters(&test, 1, 1, 0, 0);
    }

    #[test]
    fn test_delegate_only_owner_can_delegate() {
        let mut test = setup();
        let prover_owner = &test.signers[0];
        let non_owner = &test.signers[1];
        let prover_address = test.signers[2].address();
        let delegate_address = test.signers[3].address();

        // Create prover first.
        let create_prover_event = create_create_prover_event(
            prover_address,
            prover_owner.address(),
            U256::from(500),
            0,
            1,
            1,
        );
        test.state.execute::<MockVerifier>(&create_prover_event).unwrap();

        // Try to delegate using non-owner signer.
        let delegate_event = create_delegate_event(non_owner, prover_address, delegate_address, 1);
        let result = test.state.execute::<MockVerifier>(&delegate_event);

        // Verify the correct panic error is returned.
        assert!(matches!(
            result,
            Err(VAppError::Panic(VAppPanic::OnlyOwnerCanDelegate))
        ));

        // Verify signer remains unchanged.
        assert_prover_signer(&test, prover_address, prover_owner.address());
        assert_state_counters(&test, 2, 2, 0, 1);
    }

    #[test]
    fn test_delegate_domain_mismatch() {
        let mut test = setup();
        let prover_owner = &test.signers[0];
        let prover_address = test.signers[1].address();
        let delegate_address = test.signers[2].address();

        // Create prover first.
        let create_prover_event = create_create_prover_event(
            prover_address,
            prover_owner.address(),
            U256::from(500),
            0,
            1,
            1,
        );
        test.state.execute::<MockVerifier>(&create_prover_event).unwrap();

        // Try to delegate with wrong domain.
        let wrong_domain = [1u8; 32];
        let delegate_event = create_delegate_event_with_domain(
            prover_owner,
            prover_address,
            delegate_address,
            1,
            wrong_domain,
        );
        let result = test.state.execute::<MockVerifier>(&delegate_event);

        // Verify the correct panic error is returned.
        assert!(matches!(
            result,
            Err(VAppError::Panic(VAppPanic::DomainMismatch { .. }))
        ));

        // Verify signer remains unchanged.
        assert_prover_signer(&test, prover_address, prover_owner.address());
    }

    #[test]
    fn test_delegate_missing_body() {
        let mut test = setup();

        // Try to execute delegation with missing body.
        let delegate_event = create_delegate_event_missing_body();
        let result = test.state.execute::<MockVerifier>(&delegate_event);

        // Verify the correct panic error is returned.
        assert!(matches!(
            result,
            Err(VAppError::Panic(VAppPanic::MissingProtoBody))
        ));

        // Verify state remains unchanged.
        assert_state_counters(&test, 1, 1, 0, 0);
    }

    #[test]
    fn test_delegate_invalid_prover_address() {
        let mut test = setup();
        let prover_owner = &test.signers[0];
        let delegate_address = test.signers[1].address();

        // Create delegate event with invalid prover address (too short).
        use spn_network_types::{MessageFormat, SetDelegationRequest, SetDelegationRequestBody};
        
        let body = SetDelegationRequestBody {
            nonce: 1,
            delegate: delegate_address.to_vec(),
            prover: vec![0x12, 0x34], // Invalid - too short
            domain: spn_utils::SPN_SEPOLIA_V1_DOMAIN.to_vec(),
        };
        let signature = proto_sign(prover_owner, &body);

        let delegate_event = VAppTransaction::Delegate(DelegateTransaction {
            delegation: SetDelegationRequest {
                format: MessageFormat::Binary.into(),
                body: Some(body),
                signature: signature.as_bytes().to_vec(),
            },
        });

        let result = test.state.execute::<MockVerifier>(&delegate_event);

        // Verify the correct panic error is returned.
        assert!(matches!(
            result,
            Err(VAppError::Panic(VAppPanic::AddressDeserializationFailed))
        ));
    }

    #[test]
    fn test_delegate_invalid_delegate_address() {
        let mut test = setup();
        let prover_owner = &test.signers[0];
        let prover_address = test.signers[1].address();

        // Create prover first.
        let create_prover_event = create_create_prover_event(
            prover_address,
            prover_owner.address(),
            U256::from(500),
            0,
            1,
            1,
        );
        test.state.execute::<MockVerifier>(&create_prover_event).unwrap();

        // Create delegate event with invalid delegate address (too short).
        use spn_network_types::{MessageFormat, SetDelegationRequest, SetDelegationRequestBody};
        
        let body = SetDelegationRequestBody {
            nonce: 1,
            delegate: vec![0x56, 0x78], // Invalid - too short
            prover: prover_address.to_vec(),
            domain: spn_utils::SPN_SEPOLIA_V1_DOMAIN.to_vec(),
        };
        let signature = proto_sign(prover_owner, &body);

        let delegate_event = VAppTransaction::Delegate(DelegateTransaction {
            delegation: SetDelegationRequest {
                format: MessageFormat::Binary.into(),
                body: Some(body),
                signature: signature.as_bytes().to_vec(),
            },
        });

        let result = test.state.execute::<MockVerifier>(&delegate_event);

        // Verify the correct panic error is returned.
        assert!(matches!(
            result,
            Err(VAppError::Panic(VAppPanic::AddressDeserializationFailed))
        ));

        // Verify signer remains unchanged.
        assert_prover_signer(&test, prover_address, prover_owner.address());
    }

    #[test]
    fn test_delegation_basic() {
        let mut test = setup();

        // Setup: prover owner, prover address, and delegate.
        let prover_owner = &test.signers[0];
        let prover_address = test.signers[1].address();
        let delegate_address = test.signers[2].address();

        // Execute the CREATE PROVER event.
        let create_prover_event = VAppTransaction::CreateProver(OnchainTransaction {
            tx_hash: None,
            block: 0,
            log_index: 1,
            onchain_tx: 1,
            action: CreateProver {
                prover: prover_address,
                owner: prover_owner.address(),
                stakerFeeBips: U256::from(0),
            },
        });
        test.state.execute::<MockVerifier>(&create_prover_event).unwrap();

        // Execute the DELEGATE event.
        let delegation_event =
            delegate_vapp_event(prover_owner, prover_address, delegate_address, 1);
        let result = test.state.execute::<MockVerifier>(&delegation_event).unwrap();
        assert!(result.is_none());

        // Verify the delegate was added as a signer for the prover account
        let prover_account = test.state.accounts.get(&prover_address).unwrap();
        assert!(prover_account.is_signer(delegate_address));
    }

    #[test]
    fn test_delegation_invalid_signature() {
        let mut test = setup();

        let prover_owner = &test.signers[0];
        let wrong_signer = &test.signers[1];
        let prover_address = test.signers[2].address();
        let delegate_address = test.signers[3].address();

        // Execute the CREATE PROVER event.
        let create_prover_event = VAppTransaction::CreateProver(OnchainTransaction {
            tx_hash: None,
            block: 0,
            log_index: 1,
            onchain_tx: 1,
            action: CreateProver {
                prover: prover_address,
                owner: prover_owner.address(),
                stakerFeeBips: U256::from(0),
            },
        });
        test.state.execute::<MockVerifier>(&create_prover_event).unwrap();

        // Create the DELEGATE event.
        let delegation_event =
            delegate_vapp_event(wrong_signer, prover_address, delegate_address, 1);

        let result = test.state.execute::<MockVerifier>(&delegation_event);
        assert!(matches!(result, Err(VAppError::Panic(VAppPanic::OnlyOwnerCanDelegate))));
    }

    #[test]
    fn test_delegation_domain_mismatch() {
        let mut test = setup();
        let prover_owner = &test.signers[0];
        let prover_address = test.signers[1].address();
        let delegate_address = test.signers[2].address();

        // Create the DELEGATE event.
        let wrong_domain = [1u8; 32];
        let body = SetDelegationRequestBody {
            nonce: 1,
            delegate: delegate_address.to_vec(),
            prover: prover_address.to_vec(),
            domain: wrong_domain.to_vec(),
        };
        let signature = proto_sign(prover_owner, &body);

        let delegation_event = VAppTransaction::Delegate(DelegateTransaction {
            delegation: SetDelegationRequest {
                format: MessageFormat::Binary.into(),
                body: Some(body),
                signature: signature.as_bytes().to_vec(),
            },
        });

        // Should fail with domain mismatch
        let result = test.state.execute::<MockVerifier>(&delegation_event);
        assert!(matches!(result, Err(VAppError::Panic(VAppPanic::DomainMismatch { .. }))));
    }

    #[test]
    fn test_delegation_missing_body() {
        use spn_network_types::{MessageFormat, SetDelegationRequest};

        let mut test = setup();

        // Create delegation with missing body
        let delegation_event = VAppTransaction::Delegate(DelegateTransaction {
            delegation: SetDelegationRequest {
                format: MessageFormat::Binary.into(),
                body: None, // Missing body
                signature: vec![],
            },
        });

        // Should fail with missing delegation
        let result = test.state.execute::<MockVerifier>(&delegation_event);
        assert!(matches!(
            result,
            Err(crate::errors::VAppError::Panic(crate::errors::VAppPanic::MissingProtoBody))
        ));
    }

    #[test]
    fn test_delegation_signer_replacement() {
        let mut test = setup();

        let prover_owner = &test.signers[0];
        let prover_address = test.signers[1].address();
        let delegate1 = test.signers[2].address();
        let delegate2 = test.signers[3].address();

        // Execute the CREATE PROVER event.
        let create_prover_event = VAppTransaction::CreateProver(OnchainTransaction {
            tx_hash: None,
            block: 0,
            log_index: 1,
            onchain_tx: 1,
            action: CreateProver {
                prover: prover_address,
                owner: prover_owner.address(),
                stakerFeeBips: U256::from(0),
            },
        });
        test.state.execute::<MockVerifier>(&create_prover_event).unwrap();

        // Add first delegate
        let delegation1 = delegate_vapp_event(prover_owner, prover_address, delegate1, 1);
        let result1 = test.state.execute::<MockVerifier>(&delegation1);
        assert!(result1.is_ok());

        // Verify first delegate is a signer
        let prover_account = test.state.accounts.get(&prover_address).unwrap();
        assert!(prover_account.is_signer(delegate1));

        // Add second delegate (replaces first)
        let delegation2 = delegate_vapp_event(prover_owner, prover_address, delegate2, 2);
        let result2 = test.state.execute::<MockVerifier>(&delegation2);
        assert!(result2.is_ok());

        // Verify only the second delegate is a signer (first was replaced)
        let prover_account = test.state.accounts.get(&prover_address).unwrap();
        assert!(!prover_account.is_signer(delegate1)); // First delegate was replaced
        assert!(prover_account.is_signer(delegate2)); // Only second delegate is valid
    }
}
