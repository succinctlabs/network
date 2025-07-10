#!/bin/bash

# Succinct Prover Network Node Setup Script
#
# This script sets up and configures a prover node for the Succinct Prover Network.
# It installs Docker, NVIDIA Container Toolkit, CUDA drivers, and runs the prover node.
#
# SYSTEM REQUIREMENTS:
#   - Operating System: Ubuntu 22.04 or 24.04
#   - GPU: NVIDIA RTX 3090, 4090, or L4 with at least 24GB VRAM  
#   - CPU: At least 4 cores
#   - Storage: At least 100GB available disk space
#   - Memory: 16GB+ RAM recommended
#   - Network: Stable internet connection
#
# USAGE:
#   sudo ./ubuntu.sh
#
# NOTE: This script must be run as root (with sudo) and will reboot the system
#       if NVIDIA drivers need to be installed.

# Exit on any error
set -e

# Function to check if command was successful
check_status() {
    if [ $? -eq 0 ]; then
        echo "✓ $1"
    else
        echo "Error: $1 failed" >&2
        exit 1
    fi
}

# Function to check CUDA version
check_cuda_version() {
    if ! command -v nvidia-smi &> /dev/null; then
        return 1
    fi
    
    # Get driver version from nvidia-smi
    driver_version=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | cut -d. -f1)
    
    if [ -z "$driver_version" ] || [ "$driver_version" -lt 555 ]; then
        return 1
    fi
    
    return 0
}

# Function to check if all requirements are installed
check_requirements_installed() {
    # Check if Docker is installed
    if ! command -v docker &> /dev/null; then
        return 1
    fi

    # Check if NVIDIA Container Toolkit is installed
    if ! dpkg -l | grep -q nvidia-container-toolkit; then
        return 1
    fi

    # Check if NVIDIA driver version meets requirements
    if ! check_cuda_version; then
        return 1
    fi

    return 0
}

# Check if script is run as root
if [ "$EUID" -ne 0 ]; then 
    print_error "Please run as root (use sudo)"
    exit 1
fi

# Set noninteractive frontend
export DEBIAN_FRONTEND=noninteractive

# Check if all requirements are already installed
if check_requirements_installed; then
    echo "✓ All requirements already installed, skipping system updates"
else
    # Update and upgrade the system
    apt update && apt upgrade -y
    check_status "System update and upgrade"
fi

# Check if Docker is already installed
if ! command -v docker &> /dev/null; then
    # Install Docker
    apt install -y apt-transport-https ca-certificates curl software-properties-common
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
    add-apt-repository -y "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
    apt update
    apt install -y docker-ce docker-ce-cli containerd.io
    check_status "Docker installation"

    systemctl start docker
    systemctl enable docker
    check_status "Docker service setup"
else
    echo "✓ Docker already installed"
fi

# Configure Docker group permissions
if ! groups $SUDO_USER | grep -q docker; then
    usermod -aG docker $SUDO_USER
    check_status "Adding user to docker group"
    echo "✓ Docker group changes will take effect after next login or reboot"
fi

docker ps -a > /dev/null 2>&1
check_status "Docker verification"

# Check if NVIDIA Container Toolkit is installed
if ! dpkg -l | grep -q nvidia-container-toolkit; then
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \
        && curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
        sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
        sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
    check_status "Repository setup"

    apt-get update
    check_status "Package list update"

    export NVIDIA_CONTAINER_TOOLKIT_VERSION=1.17.8-1
    apt-get install -y \
        nvidia-container-toolkit=${NVIDIA_CONTAINER_TOOLKIT_VERSION} \
        nvidia-container-toolkit-base=${NVIDIA_CONTAINER_TOOLKIT_VERSION} \
        libnvidia-container-tools=${NVIDIA_CONTAINER_TOOLKIT_VERSION} \
        libnvidia-container1=${NVIDIA_CONTAINER_TOOLKIT_VERSION}
    check_status "NVIDIA Container Toolkit installation"

    nvidia-ctk runtime configure --runtime=docker
    systemctl restart docker
    check_status "Docker runtime configuration"

    docker pull public.ecr.aws/succinct-labs/spn-node:latest-gpu
    check_status "Docker image pull"
else
    echo "✓ NVIDIA Container Toolkit already installed"
fi

# Check CUDA version and NVIDIA drivers
if ! command -v nvidia-smi &> /dev/null; then
    echo "nvidia-smi not found - installing NVIDIA drivers"
    NEEDS_DRIVER_INSTALL=true
elif ! check_cuda_version; then
    driver_version=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | cut -d. -f1)
    echo "Warning: Driver version $driver_version is below required 555 (for CUDA 12.5)"
    NEEDS_DRIVER_INSTALL=true
else
    driver_version=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | cut -d. -f1)
    echo "✓ Driver version $driver_version meets requirements (for CUDA 12.5+)"
    NEEDS_DRIVER_INSTALL=false
fi

if [ "$NEEDS_DRIVER_INSTALL" = true ]; then
    # Update system
    apt update
    check_status "System update"

    # Install essential packages
    apt install -y build-essential linux-headers-$(uname -r)
    check_status "Essential packages installation"

    # Remove existing NVIDIA installations
    apt remove -y nvidia-* --purge
    apt autoremove -y
    check_status "NVIDIA cleanup"

    # Add NVIDIA repository
    curl -fsSL https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb -O
    dpkg -i cuda-keyring_1.1-1_all.deb
    apt update
    check_status "NVIDIA repository setup"

    # Install latest NVIDIA driver and CUDA
    apt install -y cuda-drivers
    check_status "NVIDIA driver and CUDA installation"

    echo "Warning: NVIDIA drivers installed. System needs to reboot."
    echo "Please run this script again after reboot to complete the setup."
    sleep 10
    reboot
fi

echo "✓ All system requirements are installed!"

# Set default values for PROVE and PGUS
export PROVE_PER_BPGU=1.01
export PGUS_PER_SECOND=10485606

echo ""

# Check if PROVER_ADDRESS is already set
if [[ -z "$PROVER_ADDRESS" ]]; then
    echo "Step 1: Create a Prover"
    echo "You need to create a prover at https://staking.sepolia.succinct.xyz/prover. Your prover will have an address that is under \"My Prover\"."
    echo "Copy and paste the address of your prover below."
    echo ""
    read -p "Enter Prover Address: " PROVER_ADDRESS
    echo ""
else
    echo "✓ Using provided PROVER_ADDRESS: $PROVER_ADDRESS"
fi

# Validate PROVER_ADDRESS format
if [[ ! $PROVER_ADDRESS =~ ^0x[a-fA-F0-9]{40}$ ]]; then
    echo "Error: Address format is invalid. It should start with '0x' followed by 40 hexadecimal characters." >&2
    exit 1
fi

# Check if PRIVATE_KEY is already set
if [[ -z "$PRIVATE_KEY" ]]; then
    echo "Step 2: Enter Private Key"
    echo "Enter the private key of the wallet that received 1000 testnet PROVE tokens and was used to stake on https://staking.sepolia.succinct.xyz/prover."
    echo "As a sanity check, this wallet's address should be the one you see connected on the top right of the staking page. Remember, for security reasons,"
    echo "please use a fresh wallet created specifically for this prover, as the private key will be used directly in the CLI."
    echo ""
    read -p "Enter Private Key: " PRIVATE_KEY
    echo ""
else
    echo "✓ Using provided PRIVATE_KEY (hidden for security)"
fi

# Validate PRIVATE_KEY
if [[ -z "$PRIVATE_KEY" ]]; then
    echo "Error: Private key cannot be empty" >&2
    exit 1
fi

# Export the variables
export PROVER_ADDRESS
export PRIVATE_KEY

echo "✓ Configuration complete!"
echo ""

# Run the Docker container
docker run --gpus all \
    --network host \
    -e NETWORK_PRIVATE_KEY=$PRIVATE_KEY \
    -v /var/run/docker.sock:/var/run/docker.sock \
    public.ecr.aws/succinct-labs/spn-node:latest-gpu \
    prove \
    --rpc-url https://rpc.sepolia.succinct.xyz \
    --throughput $PGUS_PER_SECOND \
    --bid $PROVE_PER_BPGU \
    --private-key $PRIVATE_KEY \
    --prover $PROVER_ADDRESS 