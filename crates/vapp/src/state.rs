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
                    return Err(
                        VAppPanic::DomainMismatch { expected: self.domain, actual: domain }.into()
                    );
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
                    return Err(
                        VAppPanic::DomainMismatch { expected: self.domain, actual: domain }.into()
                    );
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
                // Make sure all the proto bodies are present.
                debug!("validate proto bodies");
                let request = clear.request.body.as_ref().ok_or(VAppPanic::MissingProtoBody)?;
                let bid = clear.bid.body.as_ref().ok_or(VAppPanic::MissingProtoBody)?;
                let settle = clear.settle.body.as_ref().ok_or(VAppPanic::MissingProtoBody)?;
                let execute = clear.execute.body.as_ref().ok_or(VAppPanic::MissingProtoBody)?;
                let fulfill = clear.fulfill.body.as_ref().ok_or(VAppPanic::MissingProtoBody)?;

                // Verify the proto signatures.
                debug!("verify proto signatures");
                let request_signer = proto_verify(request, &clear.request.signature)
                    .map_err(|_| VAppPanic::InvalidRequestSignature)?;
                let bid_signer = proto_verify(bid, &clear.bid.signature)
                    .map_err(|_| VAppPanic::InvalidBidSignature)?;
                let settle_signer = proto_verify(settle, &clear.settle.signature)
                    .map_err(|_| VAppPanic::InvalidSettleSignature)?;
                let execute_signer = proto_verify(execute, &clear.execute.signature)
                    .map_err(|_| VAppPanic::InvalidExecuteSignature)?;

                // Verify the domain.
                debug!("verify domains");
                for domain in
                    [&request.domain, &bid.domain, &settle.domain, &execute.domain, &fulfill.domain]
                {
                    let domain = B256::try_from(domain.as_slice())
                        .map_err(|_| VAppPanic::DomainDeserializationFailed)?;
                    if domain != self.domain {
                        return Err(VAppPanic::DomainMismatch {
                            expected: self.domain,
                            actual: domain,
                        }
                        .into());
                    }
                }

                // Hash the request to get the request ID.
                debug!("hash request to get request ID");
                let request_id: RequestId = request
                    .hash_with_signer(request_signer.as_slice())
                    .map_err(|_| VAppPanic::HashingBodyFailed)?;

                // Check that this request ID has not been consumed yet.
                debug!("check that request ID has not been consumed yet");
                if self.requests.get(&request_id).copied().unwrap_or_default() {
                    return Err(
                        VAppPanic::RequestAlreadyConsumed { id: hex::encode(request_id) }.into()
                    );
                }

                // Validate that the request ID is the same for all proto bodies.
                debug!("validate that request ID is the same for all proto bodies");
                if request_id.as_slice() != bid.request_id.as_slice() ||
                    request_id.as_slice() != settle.request_id.as_slice() ||
                    request_id.as_slice() != execute.request_id.as_slice() ||
                    request_id.as_slice() != fulfill.request_id.as_slice()
                {
                    return Err(VAppPanic::RequestIdMismatch {
                        request_id: address(&request_id)?,
                        bid_request_id: address(&bid.request_id)?,
                        settle_request_id: address(&settle.request_id)?,
                        execute_request_id: address(&execute.request_id)?,
                        fulfill_request_id: address(&fulfill.request_id)?,
                    }
                    .into());
                }

                // Validate the the bidder has the right to bid on behalf of the prover.
                debug!("validate bidder has right to bid on behalf of prover");
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
                debug!("validate prover is in whitelist");
                if !request.whitelist.is_empty() &&
                    !request.whitelist.contains(&prover_address.to_vec())
                {
                    return Err(VAppPanic::ProverNotInWhitelist { prover: prover_address }.into());
                }

                // Validate that the request, settle, and auctioneer addresses match.
                debug!("validate request, settle, and auctioneer addresses match");
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
                debug!("validate request, execute, and executor addresses match");
                let request_executor = address(request.executor.as_slice())?;
                if request_executor != execute_signer && request_executor != self.executor {
                    return Err(VAppPanic::ExecutorMismatch {
                        request_executor,
                        execute_signer,
                        executor: self.executor,
                    }
                    .into());
                }

                // Validate that the execution status is successful.
                debug!("validate execution status is successful");
                if execute.execution_status != ExecutionStatus::Executed as i32 {
                    return Err(
                        VAppPanic::ExecutionFailed { status: execute.execution_status }.into()
                    );
                }

                // Verify the proof.
                debug!("verify proof");
                let mode = ProofMode::try_from(request.mode)
                    .map_err(|_| VAppPanic::UnsupportedProofMode { mode: request.mode })?;
                let vk = bytes_to_words_be(
                    &request
                        .vk_hash
                        .clone()
                        .try_into()
                        .map_err(|_| VAppPanic::FailedToParseBytes)?,
                )?;
                match mode {
                    ProofMode::Compressed => {
                        let verifier = V::default();
                        verifier
                            .verify(
                                vk,
                                // TODO(jtguibas): this should be either execute.public_values_hash
                                // or request.public_values_hash
                                execute
                                    .public_values_hash
                                    .clone()
                                    .ok_or(VAppPanic::MissingPublicValuesHash)?
                                    .try_into()
                                    .map_err(|_| VAppPanic::FailedToParseBytes)?,
                            )
                            .map_err(|_| VAppPanic::InvalidProof)?;
                    }
                    ProofMode::Groth16 | ProofMode::Plonk => {
                        // Verify the signature of the verifier signing the fulfillment.
                        let fulfill_signer = proto_verify(fulfill, &clear.fulfill.signature)
                            .map_err(|_| VAppPanic::InvalidFulfillSignature)?;
                        let fulfillment_id = fulfill
                            .hash_with_signer(fulfill_signer.as_slice())
                            .map_err(|_| VAppPanic::HashingBodyFailed)?;
                        let verifier = eth_sign_verify(&fulfillment_id, &clear.verify)
                            .map_err(|_| VAppPanic::InvalidVerifierSignature)?;
                        if verifier != self.verifier {
                            return Err(VAppPanic::InvalidVerifierSignature.into());
                        }
                    }
                    _ => {
                        return Err(VAppPanic::UnsupportedProofMode { mode: request.mode }.into());
                    }
                }

                // Parse the bid price.
                debug!("parse bid price");
                let price = bid
                    .amount
                    .parse::<U256>()
                    .map_err(|_| VAppPanic::InvalidBidAmount { amount: bid.amount.clone() })?;

                // Calculate the cost of the proof.
                // TODO(jtguibas): rename to gas_used to pgus
                debug!("calculate cost of proof");
                let pgus = execute.gas_used.ok_or(VAppPanic::MissingGasUsed)?;
                let cost = price * U256::from(pgus);

                // Validate that the execute gas_used was lower than the request gas_limit.
                debug!("validate execute gas_used was lower than request gas_limit");
                if pgus > request.gas_limit {
                    return Err(VAppPanic::GasLimitExceeded {
                        gas_used: pgus,
                        gas_limit: request.gas_limit,
                    }
                    .into());
                }

                // Ensure the user can afford the cost of the proof.
                debug!("ensure user can afford cost of proof");
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
                debug!("log clear event");
                let request_id: [u8; 32] = clear
                    .fulfill
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
                debug!("mark request as consumed before processing payment");
                self.requests.entry(request_id).or_insert(true);

                // Deduct the cost from the requester.
                info!("├── Account({}): - {} $PROVE (Requester Fee)", request_signer, cost);
                self.accounts.entry(request_signer).or_default().deduct_balance(cost);

                // Deposit the cost into the protocol, prover vault, and prover owner.
                debug!("deposit cost into protocol, prover vault, and prover owner");

                // Get the protocol fee.
                debug!("get protocol fee");
                let protocol_address = self.treasury;
                let protocol_fee_bips = U256::from(30); // 0.3%

                // Get the staker fee from the prover account.
                debug!("get staker fee from prover account");
                let prover_account = self
                    .accounts
                    .get(&prover_address)
                    .ok_or(VAppPanic::AccountDoesNotExist { account: prover_address })?;
                let staker_fee_bips = prover_account.get_staker_fee_bips();

                // Calculate the fee split for the protocol, prover vault stakers, and prover owner.
                debug!("calculate fee split for protocol, prover vault stakers, and prover owner");
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
            test_utils::setup,
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

    #[test]
    fn test_deposit() {
        let mut test = setup();
        let account = test.requester.address();

        // Deposit event
        let event = VAppTransaction::Deposit(OnchainTransaction {
            tx_hash: None,
            block: 0,
            log_index: 1,
            onchain_tx: 1,
            action: Deposit { account, amount: U256::from(100) },
        });

        let action = test.state.execute::<MockVerifier>(&event).unwrap();
        assert_eq!(test.state.accounts.get(&account).unwrap().get_balance(), U256::from(100),);

        // Assert the action
        match &action.unwrap() {
            VAppReceipt::Deposit(deposit) => {
                assert_eq!(deposit.action.account, account);
                assert_eq!(deposit.action.amount, U256::from(100));
                assert_eq!(deposit.status, TransactionStatus::Completed);
            }
            _ => panic!("Expected a deposit action"),
        }
    }

    #[test]
    fn test_withdraw() {
        let mut test = setup();

        // Deposit event
        let event = VAppTransaction::Deposit(OnchainTransaction {
            tx_hash: None,
            block: 0,
            log_index: 1,
            onchain_tx: 1,
            action: Deposit { account: test.requester.address(), amount: U256::from(100) },
        });
        let _ = test.state.execute::<MockVerifier>(&event);

        let account_address: Address = test.requester.address();
        assert_eq!(
            test.state.accounts.get(&account_address).unwrap().get_balance(),
            U256::from(100),
        );

        // Withdraw event
        let event = VAppTransaction::Withdraw(OnchainTransaction {
            tx_hash: None,
            block: 0,
            log_index: 2,
            onchain_tx: 2,
            action: Withdraw { account: test.requester.address(), amount: U256::from(100) },
        });
        let action = test.state.execute::<MockVerifier>(&event).unwrap();

        assert_eq!(test.state.accounts.get(&account_address).unwrap().get_balance(), U256::from(0),);

        // Assert the action
        match &action.unwrap() {
            VAppReceipt::Withdraw(withdraw) => {
                assert_eq!(withdraw.action.account, account_address,);
                assert_eq!(withdraw.action.amount, U256::from(100));
                assert_eq!(withdraw.status, TransactionStatus::Completed);
            }
            _ => panic!("Expected a withdraw action"),
        }
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
            U256::from(99700000)
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
