# SPN Node

This repository provides a prover node implementation that can be deployed on a single GPU machine 
or across a cluster of GPU machines to provide proving capacity on the [Succinct Prover Network](https://docs.succinct.xyz/docs/network/introduction). It 
also includes a collection of crates that serve as building blocks for creating your own custom 
proving node implementations.

> Note: This repository currently supports GPU proving only. CPU proving is not supported at this time.

## Prerequisites

Before installing the CLI, ensure the following prerequisites are met:

- [SP1 Prerequisites](https://docs.succinct.xyz/docs/sp1/getting-started/install)
- [SP1 GPU Prerequsites](https://docs.succinct.xyz/docs/sp1/generating-proofs/hardware-acceleration)

## Install

To install the CLI, navigate to the `bin/cli` directory and run the following command:

```
cd bin/cli
cargo install --path .
```

## Usage

After installing, you can run the CLI using the following command template:

```
spn prove \
    --rpc-url <rpcUrl> \
    --throughput <throughput> \
    --bid-amount <bidAmount> \
    --private-key <privateKey>
```

Example Output:
```
███████╗██╗   ██╗ ██████╗ ██████╗██╗███╗   ██╗ ██████╗████████╗
██╔════╝██║   ██║██╔════╝██╔════╝██║████╗  ██║██╔════╝╚══██╔══╝
███████╗██║   ██║██║     ██║     ██║██╔██╗ ██║██║        ██║   
╚════██║██║   ██║██║     ██║     ██║██║╚██╗██║██║        ██║   
███████║╚██████╔╝╚██████╗╚██████╗██║██║ ╚████║╚██████╗   ██║   
╚══════╝ ╚═════╝  ╚═════╝ ╚═════╝╚═╝╚═╝  ╚═══╝ ╚═════╝   ╚═╝   

Welcome to the Succinct Prover Node CLI! You're about to start your proving journey.

Fire up your machine and join a global network of provers where your compute helps prove the world's software. 

Learn more: https://docs.succinct.xyz

  2025-04-17T03:46:11.031581Z  INFO  Starting Node on Succinct Network..., wallet: 0x07770d0CfB05D66c3397842C1e2d90DD434820b0, rpc: https://rpc.testnet-private.succinct.xyz, throughput: 895350, bid_amount: 1, s3_bucket: spn-artifacts-testnet-private, s3_region: us-east-2

  2025-04-17T03:46:11.093124Z  INFO  [SerialBidder] Fetched owner., owner: 07770d0cfb05d66c3397842c1e2d90dd434820b0

  2025-04-17T03:46:11.167505Z  INFO  [SerialBidder] Fetched unassigned proof requests., count: 1

  2025-04-17T03:46:11.167521Z  INFO  [SerialBidder] Found one unassigned request to bid on.

  2025-04-17T03:46:11.228458Z  INFO  [SerialBidder] Fetched account nonce., nonce: 442

  2025-04-17T03:46:11.290751Z  INFO  [SerialBidder] Fetched request details., request_id: 4092742637e0d16097b16d1cb0871eda2f30c6dadc391a73f67d15aed16c9a03, vk_hash: 0018b32c74d38cdbbcf62bd30414e413fdd5553ed5d33e9ea432a11d6d7ebcf8, version: sp1-v4.0.0-rc.3, mode: 1, strategy: 3, requester: 444a83fddbc650179cd02266d43f4a8d85fb1d84, tx_hash: 53dea9179e8bf88a56396a90764b3d6ce0f4b4508b12dd8b08c2bff4e84ef1b2, program_uri: s3://spn-artifacts-testnet-private/programs/artifact_01jqz2b9h3e788fmy6bds8vehr, stdin_uri: s3://spn-artifacts-testnet-private/stdins/artifact_01js0xn3knefrah22873pxwp0s, cycle_limit: 1249, created_at: 1744861564, created_at_utc: 2025-04-17 03:46:04 UTC, deadline: 1744861864, deadline_utc: 2025-04-17 03:51:04 UTC, remaining_time: 293, remaining_time_minutes: 4, remaining_time_seconds: 53, required_time: 0, required_time_minutes: 0, required_time_seconds: 0

  2025-04-17T03:46:11.290789Z  INFO  [SerialBidder] Submitting a bid for request, request_id: 4092742637e0d16097b16d1cb0871eda2f30c6dadc391a73f67d15aed16c9a03, bid_amount: 1

  2025-04-17T03:46:11.446887Z  INFO  [SerialProver] Fetched owner., owner: 07770d0cfb05d66c3397842c1e2d90dd434820b0

  2025-04-17T03:46:11.517291Z  INFO  [SerialProver] Fetched assigned proof requests., count: 1

  2025-04-17T03:46:11.517310Z  INFO  [SerialProver] Proving request..., request_id: 42a7e4cda5da3cd6372919cf98e4241163b642ec8f2310655e9f72193caa4212, vk_hash: 006a6605490f749d015f23676d09aab60bc2e3704edec852425795e0b4e2a530, version: sp1-v4.0.0-rc.3, mode: 2, strategy: 3, requester: 444a83fddbc650179cd02266d43f4a8d85fb1d84, tx_hash: 7ee5f447e66d0b87f231e981049f461fb27e519680de8b1084368362bff96cf1, program_uri: s3://spn-artifacts-testnet-private/programs/artifact_01jqz2ccptfp8t9gm2jnqvcx66, stdin_uri: s3://spn-artifacts-testnet-private/stdins/artifact_01js0xeamxekgtm03cgydagjg4, cycle_limit: 500000000, created_at: 1744861342, created_at_utc: 2025-04-17 03:42:22 UTC, deadline: 1744863142, deadline_utc: 2025-04-17 04:12:22 UTC

  2025-04-17T03:46:12.250171Z  INFO  [SerialProver] Downloaded program., program_size: 6028848, artifact_id: 61727469666163745f30316a717a32636370746670387439676d326a6e717663783636

  2025-04-17T03:46:12.438153Z  INFO  [SerialProver] Downloaded stdin., stdin_size: 3907629, artifact_id: 61727469666163745f30316a73307865616d78656b67746d30336367796461676a6734

  2025-04-17T03:46:14.352536Z  INFO  [SerialProver] Setup complete., duration: 1.91431943

  2025-04-17T03:47:55.528272Z  INFO  [SerialProver] Proof generation complete., duration: 103.090057557

  2025-04-17T03:47:55.624026Z  INFO  [SerialProver] Fetched account nonce., nonce: 443

  2025-04-17T03:47:56.593337Z  INFO  [SerialProver] Proof fulfillment submitted., request_id: 42a7e4cda5da3cd6372919cf98e4241163b642ec8f2310655e9f72193caa4212, proof_size: 1477239
```