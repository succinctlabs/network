# Build stage
FROM rustlang/rust:nightly-slim AS builder

# Install necessary packages for building
RUN DEBIAN_FRONTEND=noninteractive apt-get update -y && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
    openssl \
    libssl-dev \
    pkg-config \
    protobuf-compiler \
    build-essential \
    wget \
    tar \
    libclang-dev \
    curl \
    git

# Install Go (needed for native-gnark)
ENV GO_VERSION=1.22.1
ARG TARGETARCH
RUN wget -q https://golang.org/dl/go$GO_VERSION.linux-${TARGETARCH}.tar.gz && \
    tar -C /usr/local -xzf go$GO_VERSION.linux-${TARGETARCH}.tar.gz && \
    rm go$GO_VERSION.linux-${TARGETARCH}.tar.gz
ENV PATH=$PATH:/usr/local/go/bin

# Install sp1up and the SP1 toolchain
ENV SP1_HOME="/root/.sp1"
ENV PATH="${SP1_HOME}/bin:${PATH}"
RUN curl -L https://sp1.succinct.xyz | bash && \
    sp1up

# Prepare for git dependencies
ENV CARGO_NET_GIT_FETCH_WITH_CLI=true
RUN mkdir -p -m 0700 ~/.ssh && ssh-keyscan github.com >> ~/.ssh/known_hosts

# Copy the entire workspace (including root Cargo.toml and all crates)
COPY . /app
WORKDIR /app

ENV VERGEN_CARGO_PROFILE=release

# Build only the node binary
RUN --mount=type=ssh \
    --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/usr/local/cargo/git \
    --mount=type=cache,target=/app/target \
    cargo build --release -p spn-node && \
    cp target/release/spn-node /spn-node-temp

# CPU Runtime stage
FROM debian:bookworm-slim AS cpu

# Install necessary runtime dependencies and Docker
RUN DEBIAN_FRONTEND=noninteractive apt-get update -y && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates \
    gcc \
    libc6-dev \
    wget \
    curl \
    gnupg && \
    update-ca-certificates && \
    install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL --insecure https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg && \
    chmod a+r /etc/apt/keyrings/docker.gpg && \
    echo \
    "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
    "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
    tee /etc/apt/sources.list.d/docker.list > /dev/null && \
    DEBIAN_FRONTEND=noninteractive apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y docker-ce docker-ce-cli containerd.io && \
    DEBIAN_FRONTEND=noninteractive apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Set up working directory
WORKDIR /app

# Copy the built binary from the build stage
COPY --from=builder /spn-node-temp /app/spn-node

# Configure default prover settings
ENV SP1_PROVER=cpu

# Set the entrypoint to run the node binary
ENTRYPOINT ["/app/spn-node"]

# GPU Runtime stage
FROM --platform=linux/amd64 nvidia/cuda:12.5.0-runtime-ubuntu22.04 AS gpu

# Install necessary runtime dependencies and Docker
RUN DEBIAN_FRONTEND=noninteractive apt-get update -y && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates \
    gcc \
    libc6-dev \
    wget \
    curl \
    gnupg && \
    update-ca-certificates && \
    install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL --insecure https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg && \
    chmod a+r /etc/apt/keyrings/docker.gpg && \
    echo \
    "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
    tee /etc/apt/sources.list.d/docker.list > /dev/null && \
    DEBIAN_FRONTEND=noninteractive apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y docker-ce docker-ce-cli containerd.io && \
    DEBIAN_FRONTEND=noninteractive apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Set up working directory
WORKDIR /app

# Copy the built binary from the build stage
COPY --from=builder /spn-node-temp /app/spn-node

# Configure default prover settings
ENV SP1_PROVER=cuda

# Set the entrypoint to run the node binary
ENTRYPOINT ["/app/spn-node"] 