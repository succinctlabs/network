//! State.
//!
//! This module contains the state and the logic of the state transition function of the vApp.

use alloy_primitives::{Address, B256, U256};
use eyre::Result;
use serde::{Deserialize, Serialize};
use tracing::{debug, info};

use spn_network_types::{ExecutionStatus, HashableWithSender, ProofMode, TransactionVariant};

use crate::{
    errors::VAppPanic,
    fee::{fee, PROTOCOL_FEE_BIPS},
    merkle::{MerkleStorage, MerkleTreeHasher},
    receipts::{OffchainReceipt, OnchainReceipt, VAppReceipt},
    signing::{eth_sign_verify, verify_signed_message},
    sol::{Account, TransactionStatus, VAppStateContainer, Withdraw},
    sparse::SparseStorage,
    storage::{RequestId, Storage},
    transactions::{OnchainTransaction, VAppTransaction},
    u256,
    utils::{address, bytes_to_words_be, tx_variant},
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
            transactionsRoot: self.transactions.root(),
        };
        H::hash(&state)
    }
}

impl VAppState<SparseStorage<Address, Account>, SparseStorage<RequestId, bool>> {
    /// Computes the state root.
    #[must_use]
    pub fn root<H: MerkleTreeHasher>(&self, account_root: B256, transactions_root: B256) -> B256 {
        let state = VAppStateContainer {
            domain: self.domain,
            txId: self.tx_id,
            onchainTxId: self.onchain_tx_id,
            onchainBlock: self.onchain_block,
            onchainLogIndex: self.onchain_log_index,
            accountsRoot: account_root,
            transactionsRoot: transactions_root,
        };
        H::hash(&state)
    }
}

impl<A: Storage<Address, Account>, R: Storage<RequestId, bool>> VAppState<A, R> {
    /// Creates a new [`VAppState`].
    #[must_use]
    pub fn new(domain: B256) -> Self {
        Self {
            domain,
            tx_id: 1,
            onchain_tx_id: 1,
            onchain_block: 0,
            onchain_log_index: 0,
            accounts: A::new(),
            transactions: R::new(),
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
                    .entry(deposit.action.account)?
                    .or_default()
                    .add_balance(deposit.action.amount)?;

                // Return the deposit action.
                return Ok(Some(VAppReceipt::Deposit(OnchainReceipt {
                    onchain_tx_id: deposit.onchain_tx,
                    action: deposit.action.clone(),
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
                    .entry(prover.action.prover)?
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

                // Verify the variant.
                debug!("verify variant");
                let variant = tx_variant(body.variant)?;
                if variant != TransactionVariant::DelegateVariant {
                    return Err(VAppPanic::InvalidTransactionVariant);
                }

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
                let format =
                    spn_network_types::MessageFormat::try_from(delegation.delegation.format)
                        .map_err(|_| VAppPanic::InvalidMessageFormat)?;
                let prover_owner =
                    verify_signed_message(body, &delegation.delegation.signature, format)?;

                // Verify that the transaction is not already processed.
                let delegate_id = body
                    .hash_with_signer(prover_owner.as_slice())
                    .map_err(|_| VAppPanic::HashingBodyFailed)?;
                if *self.transactions.entry(delegate_id)?.or_default() {
                    return Err(VAppPanic::TransactionAlreadyProcessed {
                        id: hex::encode(delegate_id),
                    });
                }

                // Mark the transaction as processed.
                self.transactions.insert(delegate_id, true)?;

                // Extract the prover address.
                debug!("extract prover address");
                let prover = Address::try_from(body.prover.as_slice())
                    .map_err(|_| VAppPanic::AddressDeserializationFailed)?;

                // Parse the fee from the request body.
                debug!("parse delegation fee");
                let auctioneer_fee = body
                    .fee
                    .parse::<U256>()
                    .map_err(|_| VAppPanic::InvalidU256Amount { amount: body.fee.clone() })?;

                // Parse the auctioneer address from the request body.
                debug!("parse auctioneer address");
                let auctioneer = Address::try_from(body.auctioneer.as_slice())
                    .map_err(|_| VAppPanic::AddressDeserializationFailed)?;

                // Verify that the prover exists and get its owner.
                debug!("verify prover exists");
                let Some(prover_account) = self.accounts.get(&prover)? else {
                    return Err(VAppPanic::ProverDoesNotExist { prover });
                };

                // Verify that the signer of the delegation is the owner of the prover.
                debug!("verify signer is owner");
                if prover_owner != prover_account.get_owner() {
                    return Err(VAppPanic::OnlyOwnerCanDelegate);
                }

                // Check that the prover owner has sufficient balance for the delegation fee.
                //
                // The prover owner must have a non-zero balance to set a delegate, which they can
                // accomplish by making a deposit.
                debug!("validate prover owner has sufficient balance for delegation fee");
                let owner_balance = self.accounts.entry(prover_owner)?.or_default().get_balance();
                if owner_balance < auctioneer_fee {
                    return Err(VAppPanic::InsufficientBalance {
                        account: prover_owner,
                        amount: auctioneer_fee,
                        balance: owner_balance,
                    });
                }

                // Deduct the delegation fee from the prover owner.
                debug!("deduct delegation fee from prover owner");
                self.accounts.entry(prover_owner)?.or_default().deduct_balance(auctioneer_fee)?;

                // Transfer the fee to the auctioneer.
                debug!("transfer delegation fee to auctioneer");
                self.accounts.entry(auctioneer)?.or_default().add_balance(auctioneer_fee)?;

                // Extract the delegate address.
                debug!("extract delegate address");
                let delegate = Address::try_from(body.delegate.as_slice())
                    .map_err(|_| VAppPanic::AddressDeserializationFailed)?;

                // Set the delegate as a signer for the prover's account.
                debug!("set delegate as signer");
                let Some(prover_account) = self.accounts.get_mut(&prover)? else {
                    return Err(VAppPanic::ProverDoesNotExist { prover });
                };
                prover_account.set_signer(delegate);

                // No action returned since delegation is off-chain.
                return Ok(None);
            }
            VAppTransaction::Transfer(transfer) => {
                // Log the transfer event.
                info!("TX {}: TRANSFER({:?})", self.tx_id, transfer);

                // Make sure the transfer body is present.
                debug!("validate proto body");
                let body = transfer.transfer.body.as_ref().ok_or(VAppPanic::MissingProtoBody)?;

                // Verify the variant.
                debug!("verify variant");
                let variant = tx_variant(body.variant)?;
                if variant != TransactionVariant::TransferVariant {
                    return Err(VAppPanic::InvalidTransactionVariant);
                }

                // Verify the proto signature.
                debug!("verify proto signature");
                let format = spn_network_types::MessageFormat::try_from(transfer.transfer.format)
                    .map_err(|_| VAppPanic::InvalidMessageFormat)?;
                let from = verify_signed_message(body, &transfer.transfer.signature, format)?;

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
                if *self.transactions.entry(transfer_id)?.or_default() {
                    return Err(VAppPanic::TransactionAlreadyProcessed {
                        id: hex::encode(transfer_id),
                    });
                }

                // Mark the transaction as processed.
                self.transactions.insert(transfer_id, true)?;

                // Transfer the amount from the requester to the recipient.
                debug!("extract to address");
                let to = Address::try_from(body.to.as_slice())
                    .map_err(|_| VAppPanic::AddressDeserializationFailed)?;
                let amount = body.amount.parse::<U256>().map_err(|_| {
                    VAppPanic::InvalidTransferAmount { amount: body.amount.clone() }
                })?;

                // Parse the fee from the request body.
                debug!("parse transfer fee");
                let auctioneer_fee = body
                    .fee
                    .parse::<U256>()
                    .map_err(|_| VAppPanic::InvalidU256Amount { amount: body.fee.clone() })?;

                // Parse the auctioneer address from the request body.
                debug!("parse auctioneer address");
                let auctioneer = Address::try_from(body.auctioneer.as_slice())
                    .map_err(|_| VAppPanic::AddressDeserializationFailed)?;

                // Validate that the from account has sufficient balance for transfer + auctioneer fee.
                debug!("validate from account has sufficient balance");
                let balance = self.accounts.entry(from)?.or_default().get_balance();
                let total_amount = u256::add(amount, auctioneer_fee)?;
                if balance < total_amount {
                    return Err(VAppPanic::InsufficientBalance {
                        account: from,
                        amount: total_amount,
                        balance,
                    });
                }

                // Transfer the amount from the transferer to the recipient.
                info!("├── Account({}): - {} $PROVE", from, amount);
                self.accounts.entry(from)?.or_default().deduct_balance(amount)?;
                info!("├── Account({}): + {} $PROVE", to, amount);
                self.accounts.entry(to)?.or_default().add_balance(amount)?;

                // Deduct and transfer the auctioneer fee.
                info!("├── Account({}): - {} $PROVE (fee)", from, auctioneer_fee);
                self.accounts.entry(from)?.or_default().deduct_balance(auctioneer_fee)?;
                info!("└── Auctioneer({}): + {} $PROVE (fee)", auctioneer, auctioneer_fee);
                self.accounts.entry(auctioneer)?.or_default().add_balance(auctioneer_fee)?;

                return Ok(None);
            }
            VAppTransaction::Withdraw(withdraw) => {
                // Log the withdraw event.
                info!("TX {}: WITHDRAW({:?})", self.tx_id, withdraw);

                // Make sure the transfer body is present.
                debug!("validate proto body");
                let body = withdraw.withdraw.body.as_ref().ok_or(VAppPanic::MissingProtoBody)?;

                // Verify the variant.
                debug!("verify variant");
                let variant = tx_variant(body.variant)?;
                if variant != TransactionVariant::WithdrawVariant {
                    return Err(VAppPanic::InvalidTransactionVariant);
                }

                // Verify the proto signature.
                debug!("verify proto signature");
                let format = spn_network_types::MessageFormat::try_from(withdraw.withdraw.format)
                    .map_err(|_| VAppPanic::InvalidMessageFormat)?;
                let from = verify_signed_message(body, &withdraw.withdraw.signature, format)?;

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
                let withdraw_id = body
                    .hash_with_signer(from.as_slice())
                    .map_err(|_| VAppPanic::HashingBodyFailed)?;
                if *self.transactions.entry(withdraw_id)?.or_default() {
                    return Err(VAppPanic::TransactionAlreadyProcessed {
                        id: hex::encode(withdraw_id),
                    });
                }

                // Mark the transaction as processed.
                self.transactions.insert(withdraw_id, true)?;

                // Extract the account address.
                debug!("extract account address");
                let account = address(body.account.as_slice())?;
                let owner = self.accounts.entry(account)?.or_default().get_owner();

                // If the account is not a prover (provers always have a non-zero owner address),
                // then only the account itself can withdraw.
                if owner == Address::ZERO && account != from {
                    return Err(VAppPanic::OnlyAccountCanWithdraw);
                }

                // Extract the amount to withdraw.
                debug!("extract amount to withdraw");
                let amount = body
                    .amount
                    .parse::<U256>()
                    .map_err(|_| VAppPanic::InvalidU256Amount { amount: body.amount.clone() })?;

                // Parse the fee from the request body.
                debug!("parse withdrawal fee");
                let auctioneer_fee = body
                    .fee
                    .parse::<U256>()
                    .map_err(|_| VAppPanic::InvalidU256Amount { amount: body.fee.clone() })?;

                // Parse the auctioneer address from the request body.
                debug!("parse auctioneer address");
                let auctioneer = Address::try_from(body.auctioneer.as_slice())
                    .map_err(|_| VAppPanic::AddressDeserializationFailed)?;

                if account == from {
                    // Self withdraw (normal user or prover owner).
                    debug!("validate balance for self withdraw (account pays amount + fee)");
                    let balance = self.accounts.entry(account)?.or_default().get_balance();
                    let total = u256::add(amount, auctioneer_fee)?;
                    if balance < total {
                        return Err(VAppPanic::InsufficientBalance {
                            account,
                            amount: total,
                            balance,
                        });
                    }

                    // Deduct the amount from the withdrawing account.
                    info!("├── Account({}): - {} $PROVE", account, amount);
                    self.accounts.entry(account)?.or_default().deduct_balance(amount)?;
                    // Deduct the fee from the withdrawing account.
                    info!("├── Account({}): - {} $PROVE (fee)", account, auctioneer_fee);
                    self.accounts.entry(account)?.or_default().deduct_balance(auctioneer_fee)?;
                } else {
                    // Someone else withdrawing for a prover.
                    debug!("validate balances for prover withdraw (prover pays amount, signer pays fee)");

                    let prover_balance = self.accounts.entry(account)?.or_default().get_balance();
                    if prover_balance < amount {
                        return Err(VAppPanic::InsufficientBalance {
                            account,
                            amount,
                            balance: prover_balance,
                        });
                    }

                    let from_balance = self.accounts.entry(from)?.or_default().get_balance();
                    if from_balance < auctioneer_fee {
                        return Err(VAppPanic::InsufficientBalance {
                            account: from,
                            amount: auctioneer_fee,
                            balance: from_balance,
                        });
                    }

                    // Deduct the amount from the prover.
                    info!("├── Account({}): - {} $PROVE", account, amount);
                    self.accounts.entry(account)?.or_default().deduct_balance(amount)?;
                    // Deduct the fee from the signer.
                    info!("├── Account({}): - {} $PROVE (fee)", from, auctioneer_fee);
                    self.accounts.entry(from)?.or_default().deduct_balance(auctioneer_fee)?;
                }

                // Credit the fee to the auctioneer.
                info!("└── Auctioneer({}): + {} $PROVE (fee)", auctioneer, auctioneer_fee);
                self.accounts.entry(auctioneer)?.or_default().add_balance(auctioneer_fee)?;

                // Return the withdraw action.
                return Ok(Some(VAppReceipt::Withdraw(OffchainReceipt {
                    action: Withdraw { account, amount },
                    status: TransactionStatus::Completed,
                })));
            }
            VAppTransaction::Clear(clear) => {
                // Make sure the proto bodies are present for (request, bid, settle, execute).
                let request = clear.request.body.as_ref().ok_or(VAppPanic::MissingProtoBody)?;
                let bid = clear.bid.body.as_ref().ok_or(VAppPanic::MissingProtoBody)?;
                let settle = clear.settle.body.as_ref().ok_or(VAppPanic::MissingProtoBody)?;
                let execute = clear.execute.body.as_ref().ok_or(VAppPanic::MissingProtoBody)?;

                // Verify the proto signatures for (request, bid, settle, execute).
                let request_format =
                    spn_network_types::MessageFormat::try_from(clear.request.format)
                        .map_err(|_| VAppPanic::InvalidMessageFormat)?;
                let bid_format = spn_network_types::MessageFormat::try_from(clear.bid.format)
                    .map_err(|_| VAppPanic::InvalidMessageFormat)?;
                let settle_format = spn_network_types::MessageFormat::try_from(clear.settle.format)
                    .map_err(|_| VAppPanic::InvalidMessageFormat)?;
                let execute_format =
                    spn_network_types::MessageFormat::try_from(clear.execute.format)
                        .map_err(|_| VAppPanic::InvalidMessageFormat)?;

                let request_signer =
                    verify_signed_message(request, &clear.request.signature, request_format)?;
                let bid_signer = verify_signed_message(bid, &clear.bid.signature, bid_format)?;
                let settle_signer =
                    verify_signed_message(settle, &clear.settle.signature, settle_format)?;
                let execute_signer =
                    verify_signed_message(execute, &clear.execute.signature, execute_format)?;

                // Verify the variants for (request, bid, settle, execute).
                let request_variant = tx_variant(request.variant)?;
                let bid_variant = tx_variant(bid.variant)?;
                let settle_variant = tx_variant(settle.variant)?;
                let execute_variant = tx_variant(execute.variant)?;
                if request_variant != TransactionVariant::RequestVariant {
                    return Err(VAppPanic::InvalidTransactionVariant);
                }
                if bid_variant != TransactionVariant::BidVariant {
                    return Err(VAppPanic::InvalidTransactionVariant);
                }
                if settle_variant != TransactionVariant::SettleVariant {
                    return Err(VAppPanic::InvalidTransactionVariant);
                }
                if execute_variant != TransactionVariant::ExecuteVariant {
                    return Err(VAppPanic::InvalidTransactionVariant);
                }

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
                if *self.transactions.entry(request_id)?.or_default() {
                    return Err(VAppPanic::TransactionAlreadyProcessed {
                        id: hex::encode(request_id),
                    });
                }

                // Validate the the bidder has the right to bid on behalf of the prover.
                //
                // Provers are liable for their bids, so it's imported to verify that they are the
                // ones that are bidding.
                let prover_address = address(bid.prover.as_slice())?;
                let prover_account = self.accounts.entry(prover_address)?.or_default();
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
                if request_auctioneer != settle_signer {
                    return Err(VAppPanic::AuctioneerMismatch {
                        request_auctioneer,
                        settle_signer,
                    });
                }

                // Validate that the request, execute, and executor addresses match.
                let request_executor = address(request.executor.as_slice())?;
                if request_executor != execute_signer {
                    return Err(VAppPanic::ExecutorMismatch { request_executor, execute_signer });
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
                    let gas_limit = U256::from(request.gas_limit);
                    let max_price = u256::add(u256::mul(max_price_per_pgu, gas_limit)?, base_fee)?;
                    if punishment > max_price {
                        return Err(VAppPanic::PunishmentExceedsMaxCost { punishment, max_price });
                    }

                    // Validate that the requester has sufficient balance to pay the punishment.
                    let balance = self.accounts.entry(request_signer)?.or_default().get_balance();
                    if balance < punishment {
                        return Err(VAppPanic::InsufficientBalance {
                            account: request_signer,
                            amount: punishment,
                            balance,
                        });
                    }

                    // Deduct the punishment from the requester.
                    self.accounts.entry(request_signer)?.or_default().deduct_balance(punishment)?;

                    // Parse the treasury address from the request.
                    let treasury = address(request.treasury.as_slice())?;

                    // Send the punishment to the treasury
                    self.accounts.entry(treasury)?.or_default().add_balance(punishment)?;

                    // Set the transaction as processed.
                    self.transactions.insert(request_id, true)?;

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
                let fulfill_format = spn_network_types::MessageFormat::try_from(fulfill.format)
                    .map_err(|_| VAppPanic::InvalidMessageFormat)?;
                let fulfill_signer =
                    verify_signed_message(fulfill_body, &fulfill.signature, fulfill_format)?;

                // Verify the domain of the fulfill.
                let fulfill_domain = B256::try_from(fulfill_body.domain.as_slice())
                    .map_err(|_| VAppPanic::DomainDeserializationFailed)?;
                if fulfill_domain != self.domain {
                    return Err(VAppPanic::DomainMismatch {
                        expected: self.domain,
                        actual: fulfill_domain,
                    });
                }

                // Verify the variant of the fulfill.
                let fulfill_variant = tx_variant(fulfill_body.variant)?;
                if fulfill_variant != TransactionVariant::FulfillVariant {
                    return Err(VAppPanic::InvalidTransactionVariant);
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
                        let verifier = eth_sign_verify(&fulfillment_id, verify)?;
                        if verifier != address(request.verifier.as_slice())? {
                            return Err(VAppPanic::InvalidVerifierSignature);
                        }
                    }
                    _ => {
                        return Err(VAppPanic::UnsupportedProofMode { mode: request.mode });
                    }
                }

                // Calculate the cost of the proof.
                let pgus = U256::from(execute.pgus.ok_or(VAppPanic::MissingPgusUsed)?);
                let cost = u256::add(u256::mul(price, pgus)?, base_fee)?;

                // Validate that the execute gas_used was lower than the request gas_limit.
                let gas_limit = U256::from(request.gas_limit);
                if pgus > gas_limit {
                    return Err(VAppPanic::GasLimitExceeded { pgus, gas_limit });
                }

                // Ensure the user can afford the cost of the proof.
                let account = self
                    .accounts
                    .get(&request_signer)?
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
                self.transactions.insert(request_id, true)?;

                // Deduct the cost from the requester.
                info!("├── Account({}): - {} $PROVE (Requester Fee)", request_signer, cost);
                self.accounts.entry(request_signer)?.or_default().deduct_balance(cost)?;

                // Get the protocol fee.
                let treasury = address(request.treasury.as_slice())?;
                let protocol_fee_bips = PROTOCOL_FEE_BIPS;

                // Get the staker fee from the prover account.
                let prover_account = self
                    .accounts
                    .get(&prover_address)?
                    .ok_or(VAppPanic::AccountDoesNotExist { account: prover_address })?;
                let staker_fee_bips = prover_account.get_staker_fee_bips();

                // Calculate the fee split for the protocol, prover vault stakers, and prover owner.
                let (protocol_fee, prover_staker_fee, prover_owner_fee) =
                    fee(cost, protocol_fee_bips, staker_fee_bips)?;

                info!("├── Account({}): + {} $PROVE (Protocol Fee)", treasury, protocol_fee);
                self.accounts.entry(treasury)?.or_default().add_balance(protocol_fee)?;

                info!(
                    "├── Account({}): + {} $PROVE (Staker Reward)",
                    prover_address, prover_staker_fee
                );
                self.accounts.entry(prover_address)?.or_default().add_balance(prover_staker_fee)?;

                info!(
                    "├── Account({}): + {} $PROVE (Owner Reward)",
                    prover_owner, prover_owner_fee
                );
                self.accounts.entry(prover_owner)?.or_default().add_balance(prover_owner_fee)?;

                return Ok(None);
            }
        }
    }
}
