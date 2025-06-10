# Succinct Prover Network (SPN) Protocol Specification

## Overview

The Succinct Prover Network (SPN) is a decentralized marketplace for zero-knowledge proof generation and verification. The protocol connects proof requesters with a network of provers through a verifiable application (vApp) that executes its state transition function off-chain in the SP1 RISC-V zkVM, generating cryptographic proofs of correct execution that are verified on Ethereum L1 for settlement.

## System Architecture

The SPN protocol consists of three main layers:

### 1. Ethereum Layer 1 (Settlement Layer)
- **SuccinctVApp**: Main settlement contract managing deposits, withdrawals, and state verification
- **SuccinctStaking**: Handles prover registration, staking, slashing, and reward distribution
- **SuccinctGovernor**: Governance contract for protocol parameter updates
- **Token Contracts**: $PROVE (base token), $iPROVE (intermediate token), $stPROVE (staking receipt tokens)

### 2. vApp Layer (State Transition Function)
- **Off-Chain Execution**: Processes batches of transactions in the SP1 zkVM
- **State Management**: Tracks account balances, prover registrations, and request fulfillment
- **Transaction Processing**: Handles deposits, withdrawals, proof clearing, and delegation
- **Recursive Verification**: Validates SP1 proofs within the STF for proof clearing transactions

### 3. Off-Chain Infrastructure
- **Provers**: People who fulfill proof generation requests for requesters
- **Auctioneer**: Off-chain auction and pricing coordination service
- **Executor**: Executes the RISC-V programs to provide auxiliary metadata
- **Verifier**: Used to provide cheaper recursive verification for Groth16/Plonk proofs

## Core Participants

### Requesters
Requesters are users or applications that need zero-knowledge proofs generated for their programs. They submit proof generation requests by depositing $PROVE tokens to fund the computation and specifying their requirements including the verification key, public inputs, and gas limits for execution. Requesters can optionally whitelist specific provers if they have preferences for who processes their requests, allowing for reputation-based selection or specialized hardware requirements.

### Provers
Provers are the backbone of the network, responsible for generating zero-knowledge proofs for submitted requests. To participate in the network, provers must stake $PROVE tokens, which serves as both an economic bond and enables them to earn fees from successful proof generation. The staking requirement creates skin-in-the-game and enables the protocol to slash misbehaving provers. Provers can delegate their signing authority to operators, enabling professional prover services to manage multiple nodes while maintaining security through the owner-operator separation model.

### Stakers
Stakers provide additional economic security to the network by staking their $PROVE tokens with specific provers they trust. In return for taking on the slashing risk associated with their chosen prover's behavior, stakers earn a portion of the rewards from successful proof generation. This creates a delegation economy where token holders can participate in network security without running prover infrastructure themselves. Stakers can unstake their tokens subject to a time delay that protects the network from sudden capital flight during disputes.

## Transaction Types

### On-Chain Transactions (L1)

#### Deposit
```solidity
struct Deposit {
    address account;    // Account receiving the deposit
    uint256 amount;     // Amount of $PROVE tokens
}
```
Deposit transactions enable users to fund their vApp accounts by transferring $PROVE tokens from their Ethereum wallet to the vApp contract. When a deposit is made on L1, it creates a transaction receipt that gets processed in the next state transition proof, crediting the specified amount to the user's vApp balance. This mechanism bridges L1 assets into the vApp's off-chain state system while maintaining cryptographic guarantees of correctness.

#### Withdraw
```solidity
struct Withdraw {
    address account;    // Account requesting withdrawal
    uint256 amount;     // Amount to withdraw (or uint256.max for full balance)
}
```
Withdraw transactions allow users to move their $PROVE tokens from the vApp back to their Ethereum wallet. Users can specify an exact amount or use `uint256.max` to withdraw their entire balance. The withdrawal is processed in two phases: first, a withdrawal request is created and processed in the STF to deduct the balance, then the user can claim their tokens from the L1 contract after the state transition proof is verified.

#### CreateProver
```solidity
struct CreateProver {
    address prover;         // Prover vault address
    address owner;          // Owner of the prover
    uint256 stakerFeeBips;  // Fee share for stakers (basis points)
}
```
CreateProver transactions register new provers in the system and are initiated by the staking contract when someone sets up a new prover vault. This transaction establishes the prover's identity, assigns ownership, and sets the fee structure that determines how much of the prover's earnings will be shared with stakers. The owner initially serves as the prover's signer but can later delegate signing authority to operators.

### Off-Chain Transactions (vApp)

#### Delegation
Delegation transactions enable prover owners to grant signing authority to other accounts, facilitating operator models where the capital provider (owner) and infrastructure operator can be separate entities. These transactions are signed using EIP-712 structured data signing with domain separation to prevent replay attacks across different networks. This flexibility allows for professional prover services and reduces the operational burden on token holders who want to participate as provers.

#### Transfer
Transfer transactions enable direct $PROVE token transfers between accounts within the vApp state, bypassing the need for L1 transactions and their associated gas costs. The sender signs a message specifying the recipient and amount, and the transfer is processed atomically within the state transition function. This creates an efficient payment rail within the prover network ecosystem.

#### Clear (Proof Fulfillment)
Clear transactions represent the most complex and economically significant transaction type, settling completed proof requests through a multi-party process. The transaction aggregates six signed messages: the original proof request from the requester, a winning bid from the assigned prover, settlement confirmation from the auctioneer, execution metadata from the executor, proof fulfillment from the prover, and optional verification signature for non-SP1 proofs. The STF validates all signatures, verifies the proof itself, calculates fees based on actual resource consumption, and distributes payments to the protocol treasury, prover stakers, and prover owner according to the established fee structure.

## State Transition Proof Flow

The vApp operates by generating SP1 proofs of correct state transitions, which are then verified on L1. This architecture enables the protocol to process complex off-chain logic with cryptographic guarantees while batching multiple transactions for efficiency and maintaining verifiable state transitions on L1.

The process begins with off-chain transaction batching, where multiple transactions are collected and prepared for efficient processing. These transactions include both L1 events such as deposits and withdrawals, as well as off-chain events like proof clearing and delegation. The system prepares the current state root and generates Merkle proofs for all accounts and requests that will be affected by the transaction batch.

The state transition function then executes inside the SP1 zkVM using carefully prepared inputs including the previous state root, account and request Merkle proofs, the batch of transactions to process, and a timestamp for the new state. The SP1 program follows a rigorous validation process: it first verifies that the previous state root matches the provided state, validates all Merkle proofs against the existing state trees, executes each transaction in the batch sequentially (handling deposits, withdrawals, proof clearing, delegation, and other operations), computes the new state root reflecting all changes, and finally outputs public values that include the old root, new root, timestamp, and detailed transaction receipts.

Once the SP1 proof is generated, it gets submitted to the `SuccinctVApp.step()` function on L1 for verification. This function verifies the SP1 proof using the vApp program's verification key, validates that the old root matches the current on-chain state root, processes the transaction receipts (such as crediting withdrawals and updating contract state), updates the on-chain state root to the new root provided by the proof, and emits events for all processed transactions. This design supports both on-chain and off-chain transaction types in a unified system while maintaining the security guarantees of Ethereum's consensus mechanism.

## Proof Request Flow

The proof request flow begins when a requester submits a comprehensive proof generation request that specifies all the parameters needed for execution. The request includes technical details such as the verification key hash, SP1 version, and proof mode (Compressed, Groth16, or Plonk), along with execution constraints like the input data location, deadline, cycle limit, and gas limit for execution. Requesters can also specify an optional prover whitelist to restrict who can fulfill their request, and must designate authorized parties including the auctioneer, executor, and verifier that will participate in the fulfillment process.

```rust
struct RequestProofRequestBody {
    nonce: u64,
    vk_hash: Vec<u8>,           // Verification key hash
    version: String,            // SP1 version
    mode: ProofMode,            // Compressed, Groth16, or Plonk
    stdin_uri: String,          // Input data location
    deadline: u64,              // Request deadline
    cycle_limit: u64,           // Maximum computation cycles
    gas_limit: u64,             // Gas limit for execution
    whitelist: Vec<Vec<u8>>,    // Optional prover whitelist
    domain: Vec<u8>,            // EIP-712 domain
    auctioneer: Vec<u8>,        // Authorized auctioneer
    executor: Vec<u8>,          // Authorized executor
}
```

Once a request is submitted, the auction process begins where eligible provers submit sealed bids specifying their price per gas unit for executing the computation. The designated auctioneer evaluates all submitted bids and settles the auction by assigning the winning prover, typically based on the lowest price bid that meets the request criteria. During this process, bid verification ensures that each prover has the proper delegation rights and staking requirements to fulfill the request.

After auction settlement, the assigned prover begins execution by generating the requested proof using the SP1 zkVM or other specified proof system. The executor plays a crucial role by providing auxiliary data needed for proof generation and monitoring the execution process to ensure it stays within the specified resource limits. Throughout execution, gas usage is carefully tracked to enable accurate fee calculation based on actual computational resources consumed rather than estimates.

The final phase involves verification and settlement of the completed proof. For SP1 proofs, verification happens recursively within the vApp's state transition function, while Groth16 and Plonk proofs require verification by a trusted verifier whose signature attests to the proof's validity. Upon successful verification, fees are calculated based on the actual gas consumed and distributed according to the established fee structure between the protocol treasury, prover stakers, and prover owner, completing the end-to-end proof request fulfillment process.


## Staking Mechanism

The staking mechanism operates through a multi-layered token system designed to enable efficient reward distribution and risk management. When users want to stake with a prover, they first deposit their $PROVE tokens to mint $iPROVE (intermediate tokens), which serves as a yield-bearing wrapper that accumulates rewards from across the entire prover network. These $iPROVE tokens are then deposited to a specific prover vault where they are converted to $stPROVE tokens that represent the user's staking position with that particular prover. As provers successfully complete proof requests and earn fees, the rewards automatically compound within the vault, increasing the value of the underlying $iPROVE holdings.

The unstaking process includes a mandatory waiting period to protect the network from sudden capital flight during disputes or market volatility. When users decide to unstake, they first request the unstaking of a specific $stPROVE amount, which triggers a configurable waiting period (typically 7 days). After this period expires, the $stPROVE tokens are burned and redeemed for the underlying $iPROVE tokens, which can then be further redeemed for the original $PROVE tokens. This time delay ensures that malicious provers cannot quickly exit their positions after misbehavior is detected.

The slashing mechanism provides economic security by enabling the protocol to penalize misbehaving provers and their stakers. When slashing occurs, it affects all stakers proportionally to their stake with the penalized prover, creating aligned incentives for stakers to choose trustworthy provers. The protocol includes a slashing period that allows for dispute resolution before penalties are finalized, providing due process while maintaining network security. When slashing is executed, it burns both $iPROVE and the underlying $PROVE tokens from the prover vault, permanently reducing the stake and serving as a strong deterrent against malicious behavior. Note that slashing functionality is not yet implemented but will be added to the protocol soon to enhance economic security.



## Security Considerations

The Succinct Prover Network protocol relies on several key assumptions that users should understand when participating in the system. The protocol assumes that the auctioneer, executor, and verifier are honest actors who will perform their designated roles correctly without attempting to manipulate the system. The auctioneer is trusted to fairly conduct auctions and assign requests to the appropriate winning provers, the executor is trusted to provide accurate auxiliary data and execution metadata, and the verifier is trusted to honestly verify Groth16 and Plonk proofs for non-SP1 proof modes. Note that the executor and verifier trust assumptions are temporary limitations that the protocol aims to eliminate in future versions through improved cryptographic techniques and decentralization mechanisms.

However, these trust assumptions are reasonable because the potential damage from malicious behavior is strictly bounded. For any individual proof request, the maximum damage an attacker can cause is limited to `price * max_gas`, where the price is set by the winning bid and max_gas is the gas limit specified in the original request. This creates a natural economic bound on the impact of any single malicious action, making the cost-benefit analysis unfavorable for attackers in most scenarios. Requesters have full control over their risk exposure by setting appropriate gas limits and can choose to work only with reputable auctioneers, executors, and verifiers.

Additionally, the protocol does not provide data availability guarantees for the off-chain components of the system. While the state transitions are cryptographically verified through SP1 proofs, the underlying transaction data and execution details are not stored on-chain, creating a dependency on off-chain infrastructure to maintain and provide access to this information. Users must trust that the necessary data will remain available for verification and dispute resolution purposes.

This specification provides the foundation for understanding and implementing the Succinct Prover Network protocol. The modular design enables efficient proof generation while maintaining security and decentralization through blockchain settlement and cryptographic verification.