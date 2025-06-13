//! State.
//!
//! This module contains the state and the logic of the state transition function of the vApp.

use alloy_primitives::{Address, B256, U256};
use eyre::Result;
use serde::{Deserialize, Serialize};
use tracing::{debug, info};

use spn_network_types::{ExecutionStatus, HashableWithSender, ProofMode};

use crate::{
    errors::VAppPanic,
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
    pub transactions: R,
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
            requestsRoot: self.transactions.root(),
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
            transactions: R::new(),
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
    ) -> Result<(), VAppPanic> {
        debug!("check l1 tx is not out of order");
        if l1_tx != self.onchain_tx_id {
            return Err(VAppPanic::OnchainTxOutOfOrder {
                expected: self.onchain_tx_id,
                actual: l1_tx,
            });
        }

        debug!("check l1 block is not out of order");
        if event.block < self.onchain_block {
            return Err(VAppPanic::BlockNumberOutOfOrder {
                expected: self.onchain_block,
                actual: event.block,
            });
        }

        debug!("check l1 log index is not out of order");
        if event.block == self.onchain_block && event.log_index <= self.onchain_log_index {
            return Err(VAppPanic::LogIndexOutOfOrder {
                current: self.onchain_log_index,
                next: event.log_index,
            });
        }

        Ok(())
    }

    /// Executes a [`VAppTransaction`] and returns an optional [`VAppReceipt`].
    pub fn execute<V: VAppVerifier>(
        &mut self,
        event: &VAppTransaction,
    ) -> Result<Option<VAppReceipt>, VAppPanic> {
        let action = self.execute_inner::<V>(event)?;

        // Increment the tx counter.
        self.tx_id += 1;

        Ok(action)
    }

    #[allow(clippy::needless_return)]
    #[allow(clippy::too_many_lines)]
    fn execute_inner<V: VAppVerifier>(
        &mut self,
        event: &VAppTransaction,
    ) -> Result<Option<VAppReceipt>, VAppPanic> {
        match event {
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
                return Ok(Some(VAppReceipt::Deposit(OnchainReceipt {
                    onchain_tx_id: deposit.onchain_tx,
                    action: deposit.action.clone(),
                    status: TransactionStatus::Completed,
                })));
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
                        // Return the withdraw action with a reverted status.
                        return Ok(Some(VAppReceipt::Withdraw(OnchainReceipt {
                            onchain_tx_id: withdraw.onchain_tx,
                            action: withdraw.action.clone(),
                            status: TransactionStatus::Reverted,
                        })));
                    }
                    withdraw.action.amount
                };

                // Process the withdraw by deducting from account balance.
                info!("├── Account({}): - {} $PROVE", withdraw.action.account, withdrawal_amount);
                account.deduct_balance(withdrawal_amount);

                // Return the withdraw action.
                return Ok(Some(VAppReceipt::Withdraw(OnchainReceipt {
                    onchain_tx_id: withdraw.onchain_tx,
                    action: withdraw.action.clone(),
                    status: TransactionStatus::Completed,
                })));
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
                return Ok(Some(VAppReceipt::CreateProver(OnchainReceipt {
                    action: prover.action.clone(),
                    onchain_tx_id: prover.onchain_tx,
                    status: TransactionStatus::Completed,
                })));
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
                    });
                }

                // Verify the proto signature.
                debug!("verify proto signature");
                let signer = proto_verify(body, &delegation.delegation.signature)
                    .map_err(|_| VAppPanic::InvalidDelegationSignature)?;

                // Verify that the transaction is not already processed.
                let delegate_id = body
                    .hash_with_signer(signer.as_slice())
                    .map_err(|_| VAppPanic::HashingBodyFailed)?;
                if self.transactions.get(&delegate_id).copied().unwrap_or_default() {
                    return Err(VAppPanic::TransactionAlreadyProcessed {
                        id: hex::encode(delegate_id),
                    });
                }

                // Mark the transaction as processed.
                self.transactions.entry(delegate_id).or_insert(true);

                // Extract the prover address.
                debug!("extract prover address");
                let prover = Address::try_from(body.prover.as_slice())
                    .map_err(|_| VAppPanic::AddressDeserializationFailed)?;

                // Verify that the prover exists.
                debug!("verify prover exists");
                let Some(prover) = self.accounts.get_mut(&prover) else {
                    return Err(VAppPanic::ProverDoesNotExist { prover });
                };

                // Verify that the signer of the delegation is the owner of the prover.
                debug!("verify signer is owner");
                if signer != prover.get_owner() {
                    return Err(VAppPanic::OnlyOwnerCanDelegate);
                }

                // Extract the delegate address.
                debug!("extract delegate address");
                let delegate = Address::try_from(body.delegate.as_slice())
                    .map_err(|_| VAppPanic::AddressDeserializationFailed)?;

                // Set the delegate as a signer for the prover's account.
                debug!("set delegate as signer");
                prover.set_signer(delegate);

                // No action returned since delegation is off-chain.
                return Ok(None);
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
                    });
                }

                // Verify that the transaction is not already processed.
                let transfer_id = body
                    .hash_with_signer(from.as_slice())
                    .map_err(|_| VAppPanic::HashingBodyFailed)?;
                if self.transactions.get(&transfer_id).copied().unwrap_or_default() {
                    return Err(VAppPanic::TransactionAlreadyProcessed {
                        id: hex::encode(transfer_id),
                    });
                }

                // Mark the transaction as processed.
                self.transactions.entry(transfer_id).or_insert(true);

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
                    return Err(VAppPanic::InsufficientBalance { account: from, amount, balance });
                }

                // Transfer the amount from the transferer to the recipient.
                info!("├── Account({}): - {} $PROVE", from, amount);
                self.accounts.entry(from).or_default().deduct_balance(amount);
                info!("├── Account({}): + {} $PROVE", to, amount);
                self.accounts.entry(to).or_default().add_balance(amount);

                return Ok(None);
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
                        });
                    }
                }

                // Validate that the request ID is the same for (request, bid, settle, execute).
                let request_id: RequestId = request
                    .hash_with_signer(request_signer.as_slice())
                    .map_err(|_| VAppPanic::HashingBodyFailed)?;
                for other_request_id in [&bid.request_id, &settle.request_id, &execute.request_id] {
                    if request_id.as_slice() != other_request_id.as_slice() {
                        return Err(VAppPanic::RequestIdMismatch {
                            found: request_id.to_vec(),
                            expected: other_request_id.clone(),
                        });
                    }
                }

                // Check that the request ID has not been fulfilled yet.
                //
                // This check ensures that a request can't be used multiple times to pay a prover.
                if self.transactions.get(&request_id).copied().unwrap_or_default() {
                    return Err(VAppPanic::TransactionAlreadyProcessed {
                        id: hex::encode(request_id),
                    });
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
                    });
                }

                // Validate that the prover is in the request whitelist, if a whitelist is provided.
                //
                // Requesters may whitelist what provers they want to work with to ensure better
                // SLAs and quality of service.
                if !request.whitelist.is_empty()
                    && !request.whitelist.contains(&prover_address.to_vec())
                {
                    return Err(VAppPanic::ProverNotInWhitelist { prover: prover_address });
                }

                // Validate that the request, settle, and auctioneer addresses match.
                let request_auctioneer = address(request.auctioneer.as_slice())?;
                if !(request_auctioneer == settle_signer && settle_signer == self.auctioneer) {
                    return Err(VAppPanic::AuctioneerMismatch {
                        request_auctioneer,
                        settle_signer,
                        auctioneer: self.auctioneer,
                    });
                }

                // Validate that the request, execute, and executor addresses match.
                let request_executor = address(request.executor.as_slice())?;
                if !(request_executor == execute_signer && request_executor == self.executor) {
                    return Err(VAppPanic::ExecutorMismatch {
                        request_executor,
                        execute_signer,
                        executor: self.executor,
                    });
                }

                // Ensure that the bid price is less than the max price per pgu.
                let base_fee =
                    request.base_fee.parse::<U256>().map_err(VAppPanic::U256ParseError)?;
                let max_price_per_pgu =
                    request.max_price_per_pgu.parse::<U256>().map_err(VAppPanic::U256ParseError)?;
                let price = bid.amount.parse::<U256>().map_err(VAppPanic::U256ParseError)?;
                if price > max_price_per_pgu {
                    return Err(VAppPanic::MaxPricePerPguExceeded { max_price_per_pgu, price });
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
                        return Err(VAppPanic::PunishmentExceedsMaxCost { punishment, max_price });
                    }

                    // Deduct the punishment from the requester.
                    self.accounts.entry(request_signer).or_default().deduct_balance(punishment);

                    // Send the punishment to the treasury
                    self.accounts.entry(self.treasury).or_default().add_balance(punishment);

                    return Ok(None);
                }

                // Validate that the execution status is successful.
                //
                // If this is true, then a prover should definitely be able to prove the request.
                if execute.execution_status != ExecutionStatus::Executed as i32 {
                    return Err(VAppPanic::ExecutionFailed { status: execute.execution_status });
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
                    });
                }

                // Validate that the fulfill request ID matches the request ID.
                let fulfill_request_id = fulfill_body.request_id.clone();
                if fulfill_request_id != request_id {
                    return Err(VAppPanic::RequestIdMismatch {
                        found: fulfill_request_id.clone(),
                        expected: request_id.to_vec(),
                    });
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
                            return Err(VAppPanic::PublicValuesHashMismatch);
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
                            return Err(VAppPanic::InvalidVerifierSignature);
                        }
                    }
                    _ => {
                        return Err(VAppPanic::UnsupportedProofMode { mode: request.mode });
                    }
                }

                // Calculate the cost of the proof.
                let pgus = execute.pgus.ok_or(VAppPanic::MissingPgusUsed)?;
                let cost = price * U256::from(pgus) + base_fee;

                // Validate that the execute gas_used was lower than the request gas_limit.
                if pgus > request.gas_limit {
                    return Err(VAppPanic::GasLimitExceeded { pgus, gas_limit: request.gas_limit });
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
                    });
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
                self.transactions.entry(request_id).or_insert(true);

                // Deduct the cost from the requester.
                info!("├── Account({}): - {} $PROVE (Requester Fee)", request_signer, cost);
                self.accounts.entry(request_signer).or_default().deduct_balance(cost);

                // Get the protocol fee.
                let protocol_address = self.treasury;
                let protocol_fee_bips = U256::ZERO;

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

                return Ok(None);
            }
        }
    }
}
