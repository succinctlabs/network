# Succinct Prover Network Contracts

This folder contains the smart contracts for the Succinct Prover Network.

## Design

For design and architecture information, see [DESIGN.md](./DESIGN.md).

## Installation

To install the dependencies:

```sh
forge install
```

## Tests

To run the tests:

```sh
forge test
```

To run with additional fuzz runs:

```sh
FOUNDRY_PROFILE=fuzz forge test
```

## Gas Report

To generate a gas report (exclude fuzz tests for reproducibility):

```sh
FOUNDRY_PROFILE=deploy forge snapshot --no-match-test "Fuzz"
```

## Deployment

Deployment guide is available in [DEPLOYMENT.md](./DEPLOYMENT.md).

## Operations

Operations guide is available in [OPERATIONS.md](./OPERATIONS.md).
