#!/bin/bash

# Parse command line arguments.
USE_DOCKER=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --docker)
      USE_DOCKER="--docker"
      shift
      ;;
    *)
      echo "Unknown option $1"
      echo "Usage: $0 [--docker]"
      exit 1
      ;;
  esac
done

# Build the STF program.
echo "Building STF program..."
cd programs/vapp/stf
cargo prove build --elf-name spn-vapp-stf $USE_DOCKER --tag v4.0.0 --output-directory ../../../elf
cd ../../..
echo "Done!"
echo ""

# Build the aggregation program.
echo "Building aggregation program..."
cd programs/vapp/aggregation
cargo prove build --elf-name spn-vapp-aggregation $USE_DOCKER --tag v4.0.0 --output-directory ../../../elf
cd ../../..
echo "Done!"
echo ""

# Build the CLI.
cargo build --bin spn-cli --release

# Compute the verification key of the STF program.
echo "Computing verification key of STF program..."
cargo run --bin spn-cli --release -- vkey --elf-path elf/spn-vapp-stf
echo "Done!"
echo ""

# Compute the verification key of the aggregation program.
echo "Computing verification key of aggregation program..."
cargo run --bin spn-cli --release -- vkey --elf-path elf/spn-vapp-aggregation
echo "Done!"