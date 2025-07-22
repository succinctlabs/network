# Succinct Prover Network (SPN) Protocol Specification

## Overview

The Succinct Prover Network (SPN) is a decentralized marketplace for zero-knowledge proof generation and verification. The protocol connects proof requesters with a network of provers through a verifiable application (vApp) that executes its state transition function off-chain in the SP1 RISC-V zkVM, generating cryptographic proofs of correct execution that are verified on Ethereum L1 for settlement.

## System Architecture

The network is architected as a verifiable application (vApp) that settles to Ethereum, providing users with the experience of interacting with a high performance web application while giving them the assurance that their deposits are secure and enabling them to independently verify the state of the network.

This architecture separates execution from settlement, similar to how L2 sequencers operate:

### Off-Chain Components (High Performance Execution)
- **Auctioneer Service**: Main off-chain entity responsible for matching user requests to provers through real-time auctions
- **Verifiable Database**: Stores user balances, pending proof requests, and proof fulfillments with Merkle proof commitments
- **Provers**: Infrastructure operators who fulfill proof generation requests for requesters
- **Executor**: Executes RISC-V programs to provide auxiliary metadata and ensure requests are well-formed
- **Verifier**: Validates Groth16/PLONK proofs that are too expensive to verify inside SP1

### On-Chain Components (Settlement Layer)
- **SuccinctVApp**: Main settlement contract that verifies SP1 proofs of state transitions and manages deposits/withdrawals
- **SuccinctStaking**: Handles prover registration, staking, slashing, and reward distribution
- **SuccinctGovernor**: Governance contract for protocol parameter updates
- **Token Contracts**: $PROVE (base token), $iPROVE (intermediate token), $stPROVE (staking receipt tokens)

### Key Benefits of This Architecture
- **Real-time Performance**: Users interact directly with fast off-chain components, avoiding blockchain latency
- **Verifiable Security**: Periodic SP1 proofs allow anyone to independently verify the network's state transitions
- **Non-custodial**: The auctioneer never holds user funds, all deposits remain on Ethereum

## Participants

| Participant | Short Description | Privileges | Controlled By |
|-------------|-------------------|------------|---------------|
| **Requester** | Users who need ZK proofs generated | Request proofs, deposit, withdraw | Individual users/applications |
| **Prover** | Infrastructure operators who generate proofs | Stake, fulfill proofs to earn fees, claim fees, delegate signing authority, subject to slashing (not implemented yet) | Prover owners (can delegate to operators) |
| **Staker** | Token holders providing economic security | Stake to a prover, earn rewards, subject to slashing (not implemented yet) | Individual token holders |
| **Auctioneer** | Matches requests to fulfillers/provers, also orders transactions in the ledger | Conduct auctions, choose winner, call `step` on contract | Trusted third-party service |
| **Executor** | Oracle ensuring requests are well-formed so that provers can actually prove | Execute programs and report PGUs used, exit status, etc., determine punishment for requester | Trusted third-party service |
| **Verifier** | Verifies Groth16/PLONK proofs or other proofs that are too expensive to verify inside SP1 | Attest to verification of proofs | Trusted third-party service |

## Contracts

| Contract | Short Description | Key Functions | Controlled By |
|----------|-------------------|---------------|---------------|
| **SuccinctVApp** | Main settlement contract managing deposits, withdrawals, and state verification | `step()`, `deposit()`, `withdraw()` | Auctioneer (step), Users and provers (deposit/withdraw) |
| **SuccinctStaking** | Handles prover registration, staking, slashing, and reward distribution | `stake()`, `unstake()`, `createProver()`, `slash()` | Users and provers (stake/unstake), Protocol (slash) |
| **SuccinctGovernor** | Governance contract for protocol parameter updates | `propose()`, `vote()`, `execute()` | Token holders via governance |


## Proof Requests


The `RequestProofRequestBody` structure represents a fundamental concept in the Succinct Prover Network: an **intent** for proof generation. Similar to how intents work in other decentralized systems, a proof request declares the desired outcome (a valid zero-knowledge proof) along with the constraints and requirements, without specifying exactly how or by whom it should be fulfilled.

```rust
struct RequestProofRequestBody {
    nonce: u64,                         // Account nonce of the sender
    vk_hash: Vec<u8>,                   // Verification key hash of the program
    version: String,                    // Version of the prover to use
    mode: ProofMode,                    // Compressed, Groth16, or Plonk
    strategy: FulfillmentStrategy,      // Strategy for fulfiller assignment
    stdin_uri: String,                  // Stdin resource identifier
    deadline: u64,                      // Deadline for the request
    cycle_limit: u64,                   // Cycle limit for the request (DEPRECATED)
    gas_limit: u64,                     // Gas limit for the request (if 0, cycle_limit is used)
    min_auction_period: u64,            // Minimum auction period in seconds (auction strategy only)
    whitelist: Vec<Vec<u8>>,            // Whitelist of provers (empty = any prover, auction strategy only)
    domain: Vec<u8>,                    // Domain separator for the request
    auctioneer: Vec<u8>,                // Auctioneer address
    executor: Vec<u8>,                  // Executor address
    verifier: Vec<u8>,                  // Verifier address
    public_values_hash: Option<Vec<u8>>, // Optional public values hash
    base_fee: String,                   // Base fee for the request
    max_price_per_pgu: String,          // Max price per prover gas unit
}
```

This intent-based design enables several key benefits:

#### Declarative Specification
Rather than requiring requesters to coordinate directly with specific provers, the request structure allows them to declare their intent by specifying:

- **What to prove**: The verification key hash (`vk_hash`) and prover version (`version`) define the program to be proven
- **How to prove it**: The proof mode (`mode`) determines whether to generate a Compressed, Groth16, or Plonk proof
- **Fulfillment strategy**: The strategy (`strategy`) determines how provers are assigned (auction vs. direct assignment)
- **Resource constraints**: The gas limit (`gas_limit`) bounds computational requirements (note: `cycle_limit` is deprecated)
- **Quality requirements**: The deadline (`deadline`) ensures timely fulfillment
- **Data and verification**: The stdin URI (`stdin_uri`) points to input data, with optional public values hash (`public_values_hash`) for verification
- **Auction parameters**: Minimum auction period (`min_auction_period`) and prover whitelist (`whitelist`) control auction behavior
- **Economic terms**: Base fee (`base_fee`) and maximum price per prover gas unit (`max_price_per_pgu`) set pricing bounds

#### Separation of Concerns
The intent structure cleanly separates the requester's needs from the fulfillment mechanism:

- **Requesters** focus on specifying their requirements without needing to understand prover capabilities or availability
- **The auction mechanism** handles matching intents to capable provers based on price and constraints
- **Provers** compete to fulfill intents that match their capabilities and economic incentives

#### Authorized Party System
The intent includes designated parties that will participate in fulfillment, creating a trust framework:

- **Auctioneer** (`auctioneer`): Authorized to conduct the auction and assign the request
- **Executor** (`executor`): Authorized to execute the program and provide auxiliary metadata
- **Verifier** (`verifier`): Authorized to verify non-SP1 proofs (Groth16/PLONK)

This design allows requesters to choose their preferred service providers while maintaining the benefits of a competitive marketplace.

#### Cryptographic Integrity
The EIP-712 domain (`domain`) and nonce (`nonce`) ensure that each intent is:

- **Unique**: The nonce prevents replay attacks and ensures each request is distinct
- **Domain-separated**: The domain prevents cross-network replay attacks
- **Cryptographically signed**: The entire intent is signed by the requester, providing authenticity

#### Economic Guarantees
The request structure provides sophisticated economic protections for both requesters and provers through a multi-layered fee structure:

**Base Fee Protection**: The `base_fee` covers fixed costs that apply to any proof regardless of size, such as setup overhead, bid preparation, and baseline infrastructure costs. This base fee is enforced at the RPC layer, which will reject requests that don't provide sufficient base fee coverage. This ensures provers are compensated for fixed costs before variable execution costs are considered, making participation economically viable even for small requests.

**Price Ceiling Control**: The `max_price_per_pgu` (maximum price per prover gas unit) creates a hard ceiling on variable costs, protecting requesters from unexpected price escalation due to complex execution paths or resource consumption. Combined with the `gas_limit`, this enables requesters to calculate their maximum possible payment exposure as `base_fee + (max_price_per_pgu × gas_limit)`.

**Resource Bound Enforcement**: The `gas_limit` serves multiple protective functions:
- **Computational bounds**: Prevents runaway execution from consuming unlimited resources
- **Economic bounds**: Caps the variable portion of fees to protect requesters from unexpectedly high costs
- **Network protection**: Prevents individual requests from monopolizing prover resources indefinitely

**Predictable Cost Structure**: This three-parameter system enables requesters to make informed economic decisions:
```
Total Maximum Cost = base_fee + (max_price_per_pgu × min(actual_gas_used, gas_limit))
```

If execution exceeds the gas limit, the request fails but the requester only pays the base fee plus the capped gas amount, protecting them from unbounded costs while still compensating the prover for their computational work.

This intent-based architecture transforms proof generation from a point-to-point coordination problem into a declarative marketplace where requesters express their needs and the network efficiently matches them with capable provers.

Once a request is submitted, the auction process begins where eligible provers submit sealed bids specifying their price per gas unit for executing the computation. The designated auctioneer evaluates all submitted bids and settles the auction by assigning the winning prover, typically based on the lowest price bid that meets the request criteria. During this process, bid verification ensures that each prover has the proper delegation rights and staking requirements to fulfill the request.

After auction settlement, the assigned prover begins execution by generating the requested proof using the SP1 zkVM or other specified proof system. The executor plays a crucial role by providing auxiliary data needed for proof generation and monitoring the execution process to ensure it stays within the specified resource limits. Throughout execution, gas usage is carefully tracked to enable accurate fee calculation based on actual computational resources consumed rather than estimates.

The final phase involves verification and settlement of the completed proof. For SP1 proofs, verification happens recursively within the vApp's state transition function, while Groth16 and Plonk proofs require verification by a trusted verifier whose signature attests to the proof's validity. Upon successful verification, fees are calculated based on the actual gas consumed and distributed according to the established fee structure between the protocol treasury, prover stakers, and prover owner, completing the end-to-end proof request fulfillment process.

## Auctioneer

The auctioneer serves as the critical real-time matching engine of the Succinct Prover Network, functioning as a pre-confirmation layer for the marketplace. It bridges the gap between requesters who need proofs and provers who can fulfill them, operating with the speed and responsiveness of a traditional web service while maintaining cryptographic verifiability through periodic settlement to Ethereum.

### Real-Time Matching Engine

The auctioneer operates as a sophisticated matching system that processes proof requests as they arrive and instantly connects them with available provers. Unlike traditional blockchain systems where users must wait for block confirmation, the auctioneer provides immediate feedback on request acceptance, prover assignment, and execution status. This real-time operation is essential for applications that require low-latency proof generation, such as live trading systems, interactive games, or real-time fraud detection.

When a requester submits an intent, the auctioneer immediately evaluates it against current prover availability, validates the economic parameters against network minimums, and either accepts the request into the auction process or rejects it with specific feedback. This instant response enables requesters to adjust their parameters and resubmit quickly, creating a responsive marketplace experience.

### Auction Mechanism

The auctioneer executes a reverse auction to determine the winning prover for each request; in a reverse auction, the lowest bidder wins the proof. After collecting bids from eligible provers, the auctioneer determines the winner and signs off on the auction result. This cryptographic signature from the auctioneer is then used in the State Transition Function (STF) to validate that the auction was conducted properly and the correct prover was assigned.

### Trust Model and Limitations

The protocol is designed around a bounded trust model for the auctioneer, acknowledging specific limitations while ensuring they cannot cause catastrophic harm:

**Worst-Case Price Execution**: The most significant harm the auctioneer can inflict is providing the worst possible price execution within the bounds of a requester's intent. Since requesters specify their `max_price_per_pgu` and `base_fee`, the auctioneer cannot charge more than these limits, but it could theoretically assign requests to the most expensive eligible prover rather than the cheapest. However, this behavior would be economically irrational for a profit-seeking auctioneer and easily detectable through monitoring.

**Censorship and DoS**: The auctioneer can censor specific requesters or provers, or deny service entirely (DoS). While disruptive, this limitation is bounded because:
- Requesters retain full control over their deposited funds on Ethereum
- The network can switch to alternative auctioneers if one becomes unreliable
- Censorship is publicly observable through on-chain settlement patterns
- The economic incentives favor serving all profitable requests

**What the Auctioneer Cannot Do**: Critically, the auctioneer cannot:
- Steal user funds (funds remain on Ethereum under smart contract control)
- Forge proofs or verification results (cryptographically prevented)
- Charge more than the specified maximum prices (economically bounded)

This bounded trust model represents a pragmatic approach to decentralization, accepting limited trust assumptions in exchange for significantly improved performance and user experience while maintaining the core security properties that matter most to users.

## Executor

The executor serves as an oracle that ensures proof requests are well-formed and executable, acting as a validation layer before provers attempt to generate proofs. It executes the requested programs to provide essential metadata and determines whether requests should proceed to fulfillment.

### Program Execution and Validation

The executor runs the requested programs to validate that they are executable within the specified constraints and generates crucial metadata needed for proof generation. This includes determining the actual Prover Gas Units (PGUs) consumed, exit status, and other execution details that inform the final fee calculation and proof validation process.

### Trust Model and Limitations

**Request Rejection**: The executor can reject requests it deems invalid or problematic, potentially censoring specific requesters or types of computation.

**Punishment Authority**: The executor can determine punishments for requesters whose programs fail to execute properly or violate network policies.

## Verifier

The verifier validates Groth16 and PLONK proofs that are too computationally expensive to verify recursively within the SP1 zkVM. It provides cryptographic attestations that enable the protocol to accept these proof types while maintaining security guarantees. Note that COMPRESSED proofs do not rely on the verifier and are verified directly within the SP1 recursive environment.

### Proof Validation

The verifier performs computationally intensive verification of Groth16 and PLONK proofs, ensuring they are cryptographically valid before the protocol accepts them. This off-chain verification enables support for proof systems that would be prohibitively expensive to verify on-chain or within the SP1 recursive environment.

### Trust Model and Limitations

**False Attestations**: The worst case scenario is that the verifier provides false attestations about proof validity. However, this is cryptographically bounded - a malicious verifier can only accept invalid proofs, not forge valid ones, and such behavior is detectable through independent verification.

**Censorship**: The verifier can refuse to verify specific proofs, effectively censoring certain types of requests.

The verifier trust assumption will be eliminated in the next protocol upgrade through improved recursive verification capabilities.

## vApp (Verifiable Application)

The Succinct Prover Network operates as a verifiable application (vApp) that executes its state transition function off-chain in the SP1 RISC-V zkVM while settling to Ethereum for final verification. This architecture enables the protocol to process complex logic with high throughput and low latency while maintaining cryptographic guarantees of correctness.

The vApp maintains a comprehensive state that tracks user account balances, pending proof requests, prover registrations, and staking positions. All state changes are processed through carefully designed transactions that are batched and proven using SP1, with the resulting proofs verified on Ethereum to ensure the integrity of the entire system.

The state transition function validates all transactions, manages economic interactions between participants, and enforces protocol rules while generating cryptographic proofs that anyone can independently verify. This design provides users with web2-like performance while preserving web3's verifiability and security guarantees.

### Transaction Types

#### On-Chain Transactions (L1)

##### Deposit
```solidity
struct Deposit {
    address account;    // Account receiving the deposit
    uint256 amount;     // Amount of $PROVE tokens
}
```
Deposit transactions enable users to fund their vApp accounts by transferring $PROVE tokens from their Ethereum wallet to the vApp contract. When a deposit is made on L1, it creates a transaction receipt that gets processed in the next state transition proof, crediting the specified amount to the user's vApp balance. This mechanism bridges L1 assets into the vApp's off-chain state system while maintaining cryptographic guarantees of correctness.

##### Withdraw
```solidity
struct Withdraw {
    address account;    // Account requesting withdrawal
    uint256 amount;     // Amount to withdraw (or uint256.max for full balance)
}
```
Withdraw transactions allow users to move their $PROVE tokens from the vApp back to their Ethereum wallet. Users can specify an exact amount or use `uint256.max` to withdraw their entire balance. The withdrawal is processed in two phases: first, a withdrawal request is created and processed in the STF to deduct the balance, then the user can claim their tokens from the L1 contract after the state transition proof is verified.

##### CreateProver
```solidity
struct CreateProver {
    address prover;         // Prover vault address
    address owner;          // Owner of the prover
    uint256 stakerFeeBips;  // Fee share for stakers (basis points)
}
```
CreateProver transactions register new provers in the system and are initiated by the staking contract when someone sets up a new prover vault. This transaction establishes the prover's identity, assigns ownership, and sets the fee structure that determines how much of the prover's earnings will be shared with stakers. The owner initially serves as the prover's signer but can later delegate signing authority to operators.

#### Off-Chain Transactions (vApp)

##### Delegation
Delegation transactions enable prover owners to grant signing authority to other accounts, facilitating operator models where the capital provider (owner) and infrastructure operator can be separate entities. These transactions are signed using EIP-712 structured data signing with domain separation to prevent replay attacks across different networks. This flexibility allows for professional prover services and reduces the operational burden on token holders who want to participate as provers.

##### Transfer
Transfer transactions enable direct $PROVE token transfers between accounts within the vApp state, bypassing the need for L1 transactions and their associated gas costs. The sender signs a message specifying the recipient and amount, and the transfer is processed atomically within the state transition function. This creates an efficient payment rail within the prover network ecosystem.

##### Clear (Proof Fulfillment)
Clear transactions represent the most complex and economically significant transaction type, settling completed proof requests through a multi-party process. The transaction aggregates six signed messages: the original proof request from the requester, a winning bid from the assigned prover, settlement confirmation from the auctioneer, execution metadata from the executor, proof fulfillment from the prover, and optional verification signature for non-SP1 proofs. The STF validates all signatures, verifies the proof itself, calculates fees based on actual resource consumption, and distributes payments to the protocol treasury, prover stakers, and prover owner according to the established fee structure.

### State Transition Function

The vApp operates through periodic execution of batched transactions that update the `VAppState` struct and settle the results on Ethereum L1. This process enables high-throughput off-chain execution while maintaining cryptographic guarantees through SP1 proofs.

```rust
struct VAppState<A: Storage<Address, Account>, R: Storage<RequestId, bool>> {
    /// The domain separator, used to avoid replay attacks
    pub domain: B256,
    /// The current transaction counter
    pub tx_id: u64,
    /// The current L1 transaction counter
    pub onchain_tx_id: u64,
    /// The current L1 block number
    pub onchain_block: u64,
    /// The current L1 log index
    pub onchain_log_index: u64,
    /// The accounts in the system for both requesters and provers
    /// Stores balances, nonces, prover vault owners, and prover delegated signers
    pub accounts: A,
    /// The processed requests in the system
    /// Keeps track of which request IDs have been processed to avoid replay attacks
    pub requests: R,
    /// The treasury address - fees earned by the protocol are sent here
    pub treasury: Address,
    /// The auctioneer address - trusted party that matches requests to provers
    pub auctioneer: Address,
    /// The executor address - trusted party that executes requests and provides auxiliary info
    pub executor: Address,
    /// The verifier address - trusted party that verifies proofs and provides auxiliary info
    pub verifier: Address,
}
```

#### State Transition Process

The state transition function (STF) executes within SP1 using the `VAppStfInput` structure, which contains:

- **State roots**: Current state root, accounts root, and requests root
- **Sparse state**: The current `VAppState` with sparse storage for efficient proving
- **Merkle proofs**: Account and request proofs for verification
- **Transaction batch**: Ordered transactions with position indices
- **Timestamp**: The prover's timestamp for this batch

Each batch execution follows this process within the SP1 program:

1. **Input validation**: Verify the provided state root matches the computed root from accounts and requests
2. **Merkle verification**: Validate all account and request Merkle proofs against their respective roots
3. **Sequential execution**: Process each transaction in order, calling `state.execute()` for each one
4. **Error handling**: Log successful transactions, handle reverts gracefully, and panic on critical errors
5. **Root computation**: Calculate new accounts and requests roots using sparse Merkle tree updates
6. **Public values output**: Generate `StepPublicValues` containing old root, new root, timestamp, and receipts

The SP1 program outputs public values in the format:
```rust
struct StepPublicValues {
    oldRoot: B256,        // Starting state root
    newRoot: B256,        // Final state root after all transactions
    timestamp: u64,       // Timestamp for this batch
    receipts: Vec<Receipt>, // Transaction receipts for L1 settlement
}
```

#### L1 Settlement

The generated SP1 proof is submitted to the `SuccinctVApp.step()` function on Ethereum, which performs the following operations:

1. **Proof verification**: Verifies the SP1 proof using the vApp program's verification key via `ISP1Verifier.verifyProof()`
2. **Public values validation**: Decodes and validates the `StepPublicValues` structure from the proof
3. **State root consistency**: Ensures the `oldRoot` matches the current on-chain state root
4. **Timestamp validation**: Validates the timestamp is not in the future and is increasing
5. **State update**: Increments the block number and updates the on-chain state root to `newRoot`
6. **Receipt processing**: Calls `_handleReceipts()` to process all transaction receipts, which:
   - Validates each receipt matches the corresponding pending transaction
   - Updates transaction statuses from Pending to Completed/Reverted
   - Processes withdrawals by adding claimable amounts for users
   - Emits events for completed and reverted transactions
7. **Event emission**: Emits a `Block` event with the new block number and state roots

The function returns the new block number, old root, and new root, enabling applications to track state progression.

#### Proof Aggregation

For improved efficiency, multiple STF proofs can be aggregated into a single proof using the aggregation program. This enables batching multiple state transition batches before settling on L1.

The aggregation process works as follows:

1. **Input collection**: Multiple STF proof public values are collected as input
2. **STF proof verification**: Each individual STF proof is verified using recursive SP1 verification with the STF verification key
3. **Sequential validation**: The aggregator ensures state root consistency between consecutive proofs:
   - Each proof's `newRoot` must equal the next proof's `oldRoot`
   - Timestamps must be in non-decreasing order across proofs
4. **Receipt aggregation**: All transaction receipts from all aggregated proofs are combined into a single list
5. **Aggregated output**: A single `StepPublicValues` is generated with:
   - `oldRoot`: The first proof's starting state root
   - `newRoot`: The final proof's ending state root  
   - `timestamp`: The timestamp from the final proof
   - `receipts`: All receipts from all aggregated proofs

This aggregation capability allows the protocol to achieve higher throughput by proving multiple batches off-chain before submitting a single aggregated proof to L1, significantly reducing settlement costs while maintaining full cryptographic guarantees.

This architecture provides cryptographic guarantees that all state transitions were executed correctly while enabling high throughput through batched off-chain execution.