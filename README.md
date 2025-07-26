# Succinct Prover Network

<div>
  <img src=".github/assets/image.png" alt="Succinct Banner" />
  &nbsp;
</div>

This is the monorepo for the Succinct Prover Network, a protocol on Ethereum that coordinates a distributed network of provers to generate zero knowledge proofs for any piece of software. This protocol creates a two-sided marketplace between provers and requesters, enabling anyone to receive proofs for applications such as blockchains, bridges, oracles, AI agents, video games, and more.

For more details, refer to the [network](https://docs.succinct.xyz/docs/network/introduction) and [provers](https://docs.succinct.xyz/docs/provers/introduction) section of our documentation.

## Overview

This repository offers the following components:

- **Contracts**: Solidity smart contracts for the protocol, including the $PROVE ERC20 token,
staking mechanisms, and the network's settlement contract.
- **Verifiable Application**: The network's state transition function, handling tasks such as balance
management, proof clearing, and more, is implemented as verifiable RISC-V programs, proven using SP1.
- **Reference Prover**: We provide a reference prover implementation that demonstrates a basic
interaction with the network, including bidding and generating a proof.

## Getting Started

To get started, you will need to install the following prerequisites:

- [Foundry](https://book.getfoundry.sh/)
- [Rust](https://www.rust-lang.org/tools/install)
- [SP1](https://docs.succinct.xyz/docs/sp1/getting-started/install)

Then, clone the repository:

```bash
git clone https://github.com/succinctlabs/network.git
cd network
```

To build the prover node and rust crates, run:

```bash
cargo build --release
./target/release/spn-node --help
```

To build and test the contracts, run:

```bash
cd contracts
forge test
```

## Security

The Succinct Prover Network has undergone audits from [Trail of Bits](https://www.trailofbits.com/) and [Cantina](https://cantina.xyz/). The audit reports are available [here](./audits).

## License

Licensed under either of

- Apache License, Version 2.0, ([LICENSE-APACHE](LICENSE-APACHE) or <http://www.apache.org/licenses/LICENSE-2.0>)
- MIT license ([LICENSE-MIT](LICENSE-MIT) or <http://opensource.org/licenses/MIT>)

at your option.
