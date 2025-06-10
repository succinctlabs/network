# Succinct Prover Network

<div>
  <img src="" alt="Succinct Banner" />
  &nbsp;

[gha-badge]: https://img.shields.io/github/actions/workflow/status/succinctlabs/network/pr.yml?branch=main
[gha-url]: https://github.com/foundry-rs/foundry/actions
[tg-badge]: https://img.shields.io/endpoint?color=neon&logo=telegram&label=chat&style=flat-square&url=https%3A%2F%2Ftg.sumanjay.workers.dev%2Ffoundry_rs
[tg-url]: https://t.me/foundry_rs

[Install](https://getfoundry.sh/getting-started/installation)
| [Docs](https://docs.succinct.xyz/docs/network/introduction)
| [Explorer](https://explorer.succinct.xyz/)

</div>

This is the monorepo for the Succinct Prover Network, a protocol on Ethereum that coordinates a 
distributed network of provers to generate zero knowledge proofs for any piece of software. This 
protocol creates a two-sided marketplace between provers and requesters, enabling anyone to receive 
proofs for applications such as blockchains, bridges, oracles, AI agents, video games, and more.

## Overview

This repository offers the following components:

- **Contracts**: Solidity smart contracts for the protocol, including the $PROVE ERC20 token, 
staking mechanisms, and the network's settlement contract.
- **Verifiable Application**: The network’s state transition function, handling tasks such as balance
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
./target/release/node --help
```

To build and test the contracts, run:

```bash
cd contracts
forge test
```

## License

Licensed under either of

* Apache License, Version 2.0, ([LICENSE-APACHE](LICENSE-APACHE) or http://www.apache.org/licenses/LICENSE-2.0)
* MIT license ([LICENSE-MIT](LICENSE-MIT) or http://opensource.org/licenses/MIT)

at your option.