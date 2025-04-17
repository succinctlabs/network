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
    --private-key <privateKey> \
    --s3-bucket <s3Bucket> \
    --s3-region <s3Region> \
```