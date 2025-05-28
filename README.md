# Succinct Prover Network

This is the monorepo for the Succinct Prover Network, a protocol on Ethereum that coordinates a distributed network of provers for universal zero-knowledge proof generation. Succinct enables the generation of zero-knowledge proofs for any piece of software, whether it's a blockchain, bridge, oracle, AI agent, video game, or anything in between.

## Overview

This repository is organized in the following way:

- **Contracts**: The Solidity contracts for the protocol.
- **Prover Node**: The reference prover node implemenation for fulfilling proofs on the network.
- **Network SDK**: There are several crates that help you interact with the network directly and build your own prover.

## Getting Started

To get started, you will need to install the following prerequisites:

- [Git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)
- [Rust](https://www.rust-lang.org/tools/install)
- [Docker](https://docs.docker.com/get-docker/)

If you want to use your GPU to run the prover node, you will need to install the following prerequisites:

- [CUDA 12](https://developer.nvidia.com/cuda-12-0-0-download-archive?target_os=Linux&target_arch=x86_64&Distribution=Ubuntu&target_version=22.04&target_type=deb_local)
- [CUDA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)

Then, clone the repository:

```bash
git clone https://github.com/succinctlabs/network.git
cd network
```

To build the prover node and rust crates, run:

```bash
cargo build --release
./target/release/node --help
```

To build and test the contracts, run:

```bash
cd contracts
forge test
```

## Documentation

We maintain extensive documentation on the protocol and how to get started with the prover node [here](https://docs.succinct.xyz/docs/network/introduction).
