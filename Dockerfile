# ==========================================
# Base system without opencode
# ==========================================
FROM ubuntu:24.04 AS base
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl ca-certificates git openssh-client sudo bash jq \
    build-essential pkg-config libssl-dev \
    ripgrep libsqlite3-dev \
    podman podman-docker fuse-overlayfs uidmap libcap2-bin \
    netavark aardvark-dns passt gosu podman-compose \
    && rm -rf /var/lib/apt/lists/*



# Node.js (needed for MCP servers)
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

ARG HOST_UID=1000
RUN userdel -r ubuntu 2>/dev/null || true \
    && useradd -m -u ${HOST_UID} -s /bin/bash op \
    && echo "op ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/op \
    && chmod 0440 /etc/sudoers.d/op

# 1. Configure subUIDs/subGIDs for user 'op'
RUN echo "op:100000:65536" > /etc/subuid \
    && echo "op:100000:65536" > /etc/subgid

# 2. Ensure SetUID permissions are set (do NOT use setcap)
RUN chmod 0755 /usr/bin/newuidmap /usr/bin/newgidmap \
    && setcap cap_setuid=ep /usr/bin/newuidmap \
    && setcap cap_setgid=ep /usr/bin/newgidmap

# Configure complete Podman storage settings for VFS
RUN mkdir -p /etc/containers && cat <<'EOF' > /etc/containers/storage.conf
[storage]
driver = "vfs"
runroot = "/run/containers/storage"
graphroot = "/var/lib/containers/storage"
EOF

# Quiet the Podman emulation notice
RUN touch /etc/containers/nodocker

# Use chroot isolation for inner builds
ENV BUILDAH_ISOLATION=chroot

# Disable Linux kernel keyrings and cgroup management (DO NOT put userns = "host" here)
RUN mkdir -p /etc/containers && cat <<'EOF' > /etc/containers/containers.conf
[containers]
keyring = false
default_sysctls = []

[network]
network_backend = "netavark"
default_rootless_network_cmd = "pasta"
EOF

# Non-root user setup
USER op
WORKDIR /home/op
ENV HOME=/home/op

# Configure Podman storage settings for user 'op'
RUN mkdir -p /home/op/.config/containers && cat <<'EOF' > /home/op/.config/containers/storage.conf
[storage]
driver = "vfs"
EOF

# Install Rust + rust-analyzer + tools
RUN curl -fsSL https://sh.rustup.rs | bash -s -- -y
ENV PATH=/home/op/.cargo/bin:$PATH
RUN rustup component add rust-analyzer rust-src clippy rustfmt
RUN cargo install --locked cargo-tarpaulin
RUN rustup component add llvm-tools-preview 
RUN cargo install cargo-llvm-cov 

# ==========================================
# Opencode layer that should not be cached
# ==========================================
FROM base AS opencode

# Install OpenCode
RUN curl -fsSL https://opencode.ai/install | bash

# Opencode Plugins
RUN npm install @bdliyq/opencode-rate-limit-retry@latest

RUN mkdir -p ~/.local/share; mkdir -p ~/.local/state; mkdir -p ~/.config

ENV PATH=/home/op/.opencode/bin:$PATH

USER root

COPY <<'EOF' /usr/local/bin/entrypoint.sh
#!/bin/bash
set -e
mkdir -p /mnt/unmasked-proc
mount -t proc proc /mnt/unmasked-proc
exec gosu op "$@"
EOF
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
