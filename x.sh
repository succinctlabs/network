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

# Compute the SHA-512 hash of the ELF files.
echo "Computing SHA-512 hash of ELF files..."
shasum -a 512 elf/spn-vapp-stf
shasum -a 512 elf/spn-vapp-aggregation
echo "Done!"