# Unit Test Specification for VAppState

This document outlines comprehensive test cases for the `VAppState::execute` method in `crates/vapp/src/state.rs`. The tests cover all transaction types, success scenarios, and failure edge cases.

## Overview

The VAppState handles 6 types of transactions:
- `Deposit` - On-chain deposits of $PROVE tokens
- `Withdraw` - On-chain withdrawals of $PROVE tokens  
- `CreateProver` - On-chain prover registration
- `Delegate` - Off-chain delegation of signing authority
- `Transfer` - Off-chain transfers between accounts
- `Clear` - Off-chain proof clearing and settlement

## 1. Deposit Transaction Tests

### Success Cases
- **`test_deposit_basic`**: Valid deposit with correct ordering
- **`test_deposit_multiple_same_account`**: Sequential deposits to same account
- **`test_deposit_multiple_different_accounts`**: Deposits to multiple different accounts
- **`test_deposit_large_amounts`**: Deposit with maximum U256 values
- **`test_deposit_zero_amount`**: Edge case with zero deposit

### Failure Cases
- **`test_deposit_onchain_tx_out_of_order`**: `onchain_tx != expected`
- **`test_deposit_block_number_regression`**: `block < current_block`
- **`test_deposit_log_index_out_of_order`**: Same block but `log_index <= current_log_index`

## 2. Withdraw Transaction Tests

### Success Cases
- **`test_withdraw_basic`**: Valid withdrawal with sufficient balance
- **`test_withdraw_partial`**: Withdraw less than full balance
- **`test_withdraw_full_balance_with_max`**: Using `U256::MAX` to withdraw entire balance
- **`test_withdraw_exact_balance`**: Withdraw exactly the account balance

### Failure Cases
- **`test_withdraw_insufficient_balance`**: Amount > account balance
- **`test_withdraw_onchain_tx_out_of_order`**: Same onchain ordering failures as deposits
- **`test_withdraw_block_number_regression`**: Block number goes backwards
- **`test_withdraw_log_index_out_of_order`**: Log index ordering violation
- **`test_withdraw_zero_balance_account`**: Withdraw from account with zero balance

## 3. CreateProver Transaction Tests

### Success Cases
- **`test_create_prover_basic`**: Valid prover with owner and staker fee
- **`test_create_prover_self_delegated`**: Owner = prover address
- **`test_create_prover_different_owner`**: Owner != prover address
- **`test_create_prover_various_staker_fees`**: Different `stakerFeeBips` values (0, 500, 1000, 5000, 10000)
- **`test_create_prover_max_staker_fee`**: Maximum allowed staker fee

### Failure Cases
- **`test_create_prover_onchain_tx_out_of_order`**: Same onchain ordering failures
- **`test_create_prover_block_regression`**: Block number regression
- **`test_create_prover_log_index_out_of_order`**: Log index ordering violation

## 4. Delegate Transaction Tests

### Success Cases
- **`test_delegate_basic`**: Valid owner delegating to new signer
- **`test_delegate_signer_replacement`**: Replace existing delegated signer
- **`test_delegate_self_delegation`**: Owner delegating to themselves
- **`test_delegate_multiple_provers`**: Delegate multiple provers sequentially

### Failure Cases
- **`test_delegate_missing_proto_body`**: `body` field is None
- **`test_delegate_invalid_signature`**: Wrong signer for delegation
- **`test_delegate_domain_mismatch`**: Wrong domain in delegation body
- **`test_delegate_non_existent_prover`**: Delegating for prover that doesn't exist
- **`test_delegate_non_owner_delegation`**: Someone other than owner trying to delegate
- **`test_delegate_invalid_prover_address`**: Invalid prover address bytes
- **`test_delegate_invalid_delegate_address`**: Invalid delegate address bytes

## 5. Transfer Transaction Tests

### Success Cases
- **`test_transfer_basic`**: Valid transfer between accounts
- **`test_transfer_self_transfer`**: Account transferring to itself
- **`test_transfer_multiple_transfers`**: Sequential transfers
- **`test_transfer_to_new_account`**: Create new account via transfer
- **`test_transfer_entire_balance`**: Transfer full account balance

### Failure Cases
- **`test_transfer_missing_proto_body`**: `body` field is None
- **`test_transfer_invalid_signature`**: Wrong signer for transfer
- **`test_transfer_domain_mismatch`**: Wrong domain in transfer body
- **`test_transfer_insufficient_balance`**: Transfer amount > sender balance
- **`test_transfer_invalid_amount_parsing`**: Malformed amount string
- **`test_transfer_invalid_to_address`**: Invalid `to` address bytes
- **`test_transfer_zero_amount`**: Transfer of zero amount

## 6. Clear Transaction Tests (Most Complex)

### Success Cases
- **`test_clear_basic_compressed`**: Full valid proof request flow with Compressed mode
- **`test_clear_groth16_mode`**: Using `ProofMode::Groth16` with verifier signature
- **`test_clear_plonk_mode`**: Using `ProofMode::Plonk` with verifier signature
- **`test_clear_with_whitelist`**: Prover in request whitelist
- **`test_clear_empty_whitelist`**: No whitelist restriction
- **`test_clear_various_fee_combinations`**: Different protocol fee and staker fee combinations
- **`test_clear_gas_limit_boundary`**: PGUs exactly at gas_limit
- **`test_clear_with_public_values_hash`**: Request with public values hash matching execute
- **`test_clear_without_public_values_hash`**: Request without public values hash

### Failure Cases - Proto Body/Signature Validation
- **`test_clear_missing_request_body`**: Request body is None
- **`test_clear_missing_bid_body`**: Bid body is None
- **`test_clear_missing_settle_body`**: Settle body is None
- **`test_clear_missing_execute_body`**: Execute body is None
- **`test_clear_missing_fulfill_body`**: Fulfill body is None
- **`test_clear_invalid_request_signature`**: Invalid request signature
- **`test_clear_invalid_bid_signature`**: Invalid bid signature
- **`test_clear_invalid_settle_signature`**: Invalid settle signature
- **`test_clear_invalid_execute_signature`**: Invalid execute signature
- **`test_clear_invalid_fulfill_signature`**: Invalid fulfill signature
- **`test_clear_domain_mismatch_request`**: Wrong domain in request
- **`test_clear_domain_mismatch_bid`**: Wrong domain in bid
- **`test_clear_domain_mismatch_settle`**: Wrong domain in settle
- **`test_clear_domain_mismatch_execute`**: Wrong domain in execute
- **`test_clear_domain_mismatch_fulfill`**: Wrong domain in fulfill

### Failure Cases - Request ID Validation
- **`test_clear_request_id_mismatch_bid`**: Bid request ID != request ID
- **`test_clear_request_id_mismatch_settle`**: Settle request ID != request ID
- **`test_clear_request_id_mismatch_execute`**: Execute request ID != request ID
- **`test_clear_request_id_mismatch_fulfill`**: Fulfill request ID != request ID
- **`test_clear_already_fulfilled_request`**: Attempting to fulfill same request twice

### Failure Cases - Prover Validation
- **`test_clear_prover_does_not_exist`**: Bidding prover not in accounts
- **`test_clear_delegated_signer_mismatch`**: Bid signer != prover's delegated signer
- **`test_clear_prover_not_in_whitelist`**: Prover not in request whitelist

### Failure Cases - Pricing/Cost Validation
- **`test_clear_max_price_exceeded`**: Bid price > max_price_per_pgu
- **`test_clear_gas_limit_exceeded`**: PGUs used > request gas_limit
- **`test_clear_insufficient_requester_balance`**: Cost > requester balance
- **`test_clear_invalid_base_fee_parsing`**: Malformed base fee string
- **`test_clear_invalid_max_price_parsing`**: Malformed max price string
- **`test_clear_invalid_bid_amount_parsing`**: Malformed bid amount string

### Failure Cases - Authority Validation
- **`test_clear_auctioneer_mismatch_request`**: Request auctioneer != settle signer
- **`test_clear_auctioneer_mismatch_global`**: Settle signer != global auctioneer
- **`test_clear_executor_mismatch_request`**: Request executor != execute signer
- **`test_clear_executor_mismatch_global`**: Execute signer != global executor

### Failure Cases - Execution Status Handling
- **`test_clear_unexecutable_with_punishment`**: ExecutionStatus::Unexecutable with valid punishment
- **`test_clear_unexecutable_missing_punishment`**: Unexecutable without punishment value
- **`test_clear_punishment_exceeds_max_cost`**: Punishment > calculated max cost
- **`test_clear_invalid_execution_status`**: Status other than Executed/Unexecutable

### Failure Cases - Proof Verification
- **`test_clear_invalid_proof_compressed`**: Proof verification fails for Compressed mode
- **`test_clear_unsupported_proof_mode`**: Invalid proof mode value
- **`test_clear_missing_verifier_signature_groth16`**: Groth16 without verifier signature
- **`test_clear_missing_verifier_signature_plonk`**: Plonk without verifier signature
- **`test_clear_invalid_verifier_signature`**: Wrong verifier signature
- **`test_clear_verifier_address_mismatch`**: Verifier signature from wrong address

### Failure Cases - Hash Validation
- **`test_clear_public_values_hash_mismatch`**: Request vs execute public values hash mismatch
- **`test_clear_missing_execute_public_values_hash`**: Execute without public values hash
- **`test_clear_invalid_vk_hash_format`**: Invalid verification key hash format

### Failure Cases - Missing Fields
- **`test_clear_missing_fulfill_field`**: Clear without fulfill field
- **`test_clear_missing_pgus_value`**: Execute without pgus value
- **`test_clear_missing_verify_field`**: Missing verifier signature for Groth16/Plonk

### Failure Cases - Data Parsing
- **`test_clear_invalid_prover_address`**: Invalid prover address bytes
- **`test_clear_invalid_auctioneer_address`**: Invalid auctioneer address bytes
- **`test_clear_invalid_executor_address`**: Invalid executor address bytes
- **`test_clear_invalid_domain_bytes`**: Invalid domain bytes
- **`test_clear_request_hashing_failed`**: Request ID hashing failure

## 7. State Validation Tests

### Ordering Validation
- **`test_state_transaction_counter_increment`**: `tx_id` increments correctly after each transaction
- **`test_state_onchain_counter_tracking`**: `onchain_tx_id` progression for onchain transactions
- **`test_state_block_progression`**: Monotonic block number increases
- **`test_state_log_index_ordering`**: Within-block log index ordering

### Domain Validation
- **`test_state_domain_initialization`**: State created with correct domain
- **`test_state_cross_transaction_domain_consistency`**: All transactions use same domain

## 8. Account State Tests

### Balance Management
- **`test_account_balance_arithmetic`**: Additions and subtractions work correctly
- **`test_account_balance_precision`**: Large number arithmetic precision
- **`test_account_multiple_operations`**: Complex sequences of balance changes

### Prover Account Management
- **`test_prover_owner_signer_relationships`**: Owner vs delegated signer tracking
- **`test_prover_staker_fee_management`**: Fee percentage handling and calculations
- **`test_prover_signer_replacement`**: Only one active signer at a time
- **`test_prover_default_signer_is_owner`**: Owner is default signer after creation

## 9. Request Tracking Tests

### Request Lifecycle
- **`test_request_consumption_tracking`**: Requests marked as consumed after clearing
- **`test_request_replay_protection`**: Same request ID cannot be used twice
- **`test_request_id_generation_consistency`**: Consistent hashing with signer
- **`test_request_id_uniqueness`**: Different requests generate different IDs

## 10. Fee Calculation Tests

### Protocol and Staker Fees
- **`test_fee_calculation_zero_protocol_fee`**: Fee calculation with zero protocol fee
- **`test_fee_calculation_zero_staker_fee`**: Fee calculation with zero staker fee
- **`test_fee_calculation_both_fees`**: Fee calculation with both protocol and staker fees
- **`test_fee_calculation_max_fees`**: Fee calculation with maximum fee percentages
- **`test_fee_distribution_accuracy`**: Verify correct fee distribution to all parties

## 11. Edge Case Tests

### Boundary Conditions
- **`test_edge_case_max_uint256_values`**: U256::MAX for various fields
- **`test_edge_case_zero_values`**: Zero amounts, fees, gas limits
- **`test_edge_case_empty_collections`**: Empty whitelists, empty storage
- **`test_edge_case_single_element_collections`**: Single-item whitelists

### Error Propagation
- **`test_error_type_classification`**: VAppRevert vs VAppPanic classification
- **`test_error_context_information`**: Error messages include relevant context
- **`test_error_chain_consistency`**: Error conversion chain works correctly

## 12. Integration Scenarios

### Multi-Transaction Workflows
- **`test_integration_full_proof_lifecycle`**: Complete proof request to clearing flow
- **`test_integration_multiple_users_provers`**: Complex multi-party interactions
- **`test_integration_concurrent_operations`**: Overlapping operations on same accounts
- **`test_integration_state_consistency`**: State remains consistent across complex workflows

### Recovery Scenarios
- **`test_recovery_after_revert`**: State unchanged after revert errors
- **`test_recovery_partial_operations`**: Handling of partially completed operations

## Test Implementation Guidelines

### Test Structure
- Use descriptive test function names following the specification
- Each test should focus on a single scenario or edge case
- Use the existing `setup()` helper function for test initialization
- Create realistic test data that exercises the specific case being tested

### Assertion Strategy
- Verify both success/failure outcomes and state changes
- Check account balances, counters, and storage state after operations
- Validate error types and error context information
- Ensure side effects (like request consumption) are properly tested

### Test Data Management
- Create helper functions for common test data patterns
- Use constants for repeated values (addresses, amounts, etc.)
- Generate unique test data to avoid interference between tests

### Mock and Stub Usage
- Use `MockVerifier` for proof verification tests
- Create test signers using the existing `signer()` helper
- Mock external dependencies consistently across tests