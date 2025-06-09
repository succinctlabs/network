#!/bin/bash

# Build the STF program.
echo "Building STF program..."
cd programs/vapp/stf
cargo prove build --elf-name spn-vapp-stf --docker --tag v4.0.0 --output-directory ../../../elf
cd ../../..
echo "Done!"
echo ""

# Build the aggregation program.
echo "Building aggregation program..."
cd programs/vapp/aggregation
cargo prove build --elf-name spn-vapp-aggregation --docker --tag v4.0.0 --output-directory ../../../elf
cd ../../..
echo "Done!"