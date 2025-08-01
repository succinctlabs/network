#!/bin/bash

# Exit on any error and make pipelines fail if any command fails.
set -e
set -o pipefail

# If you're not on Linux, warn that the ELF and VKey will be different.
if [ "$(uname)" != "Linux" ]; then
  echo "WARNING: You are not on Linux. The ELF and VKey will be different."
fi

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
cargo prove build --elf-name spn-vapp-stf $USE_DOCKER --tag v5.1.0 --output-directory ../../../elf
cd ../../..
echo "Done!"
echo ""

# Build the aggregation program.
echo "Building aggregation program..."
cd programs/vapp/aggregation
cargo prove build --elf-name spn-vapp-aggregation $USE_DOCKER --tag v5.1.0 --output-directory ../../../elf
cd ../../..
echo "Done!"
echo ""