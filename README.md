# Succinct Prover Node

This repository provides a prover node implementation that can be deployed on a single machine 
or across a cluster of machines to provide proving capacity on the [Succinct Prover
Network](https://docs.succinct.xyz/docs/network/introduction).

It also includes a collection of crates that serve as building blocks for creating your own custom 
proving node implementations.

## Prerequisites

Before installing the CLI, ensure the following prerequisites are met:

- [SP1 Prerequisites](https://docs.succinct.xyz/docs/sp1/getting-started/install)
- [SP1 GPU Prerequsites](https://docs.succinct.xyz/docs/sp1/generating-proofs/hardware-acceleration)

## Run the node

To run the node locally, you can use the following command:

```sh
cargo run --bin node prove --rpc-url <rpc-url> --throughput <throughput> --bid-amount <bid-amount> --private-key <private-key>
```

For more details, see [GETTING_STARTED.md](GETTING_STARTED.md) to setup your prover on the Succinct Prover Network.

## Run the node via Docker

If you'd like to run the node in Docker using CPU to prove, you can use the following command:

```sh
docker run public.ecr.aws/succinct-labs/prover-cpu:fa81dd4 prove --rpc-url <rpc-url> --throughput <throughput> --bid-amount <bid-amount> --private-key <private-key>
```

Or if you'd like to use GPU to prove, you can use the following command:

```sh
docker run --gpus all --network host -v /var/run/docker.sock:/var/run/docker.sock public.ecr.aws/succinct-labs/prover-cpu:fa81dd4 prove --rpc-url <rpc-url> --throughput <throughput> --bid-amount <bid-amount> --private-key <private-key>
```
