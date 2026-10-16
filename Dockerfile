# ==========================================
# Base system without opencode
# ==========================================
FROM ubuntu:24.04 AS base
ENV DEBIAN_FRONTEND=noninteractive

# Ubuntu hosts arm64 on ports.ubuntu.com, not archive.ubuntu.com —                                          
# restrict the default sources to amd64 and add a ports mirror for arm64.                                   
RUN sed -i 's/^Types: deb$/Types: deb\nArchitectures: amd64/' /etc/apt/sources.list.d/ubuntu.sources && \
    cat <<'EOF' > /etc/apt/sources.list.d/ubuntu-ports.sources
Types: deb
URIs: http://ports.ubuntu.com/ubuntu-ports/
Suites: noble noble-updates noble-backports noble-security
Components: main universe restricted multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
Architectures: arm64
EOF

RUN dpkg --add-architecture arm64 && \
    apt-get update && apt-get install -y --no-install-recommends \
    curl ca-certificates git openssh-client sudo bash jq \
    build-essential pkg-config libssl-dev \
    ripgrep libsqlite3-dev \
    podman podman-docker fuse-overlayfs uidmap libcap2-bin \
    netavark aardvark-dns passt gosu podman-compose \
    wget flex bison gperf python3 python3-pip python3-venv cmake \
    ninja-build ccache libffi-dev libssl-dev dfu-util libusb-1.0-0 \
    clang libclang-dev llvm-dev gcc-aarch64-linux-gnu libasound2-dev \
    libasound2-dev:arm64 libc6-dev:arm64 linux-libc-dev:arm64 lld \
    texlive-latex-recommended texlive-latex-extra  texlive-pictures \
    texlive-lang-german texlive-fonts-recommended  texlive-luatex \
    lmodern fonts-lmodern python3-fitz python3-cairosvg \
    build-essential python3 python3-pip git curl ca-certificates \
    gnupg unzip lsof netcat-openbsd \
    btrfs-progs borgbackup shellcheck \
    poppler-utils pandoc libreoffice-writer python3-docx \
    && curl -fsSL -o /tmp/google-chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb && sudo apt-get install -y /tmp/google-chrome.deb && rm /tmp/google-chrome.deb \
    && rm -rf /var/lib/apt/lists/*

# Node.js (needed for MCP servers)
RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g corepack@latest

RUN env PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm i -g playwright                         

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

RUN ln -s /usr/bin/ld.lld-18 /usr/aarch64-linux-gnu/bin/ld.lld

RUN corepack enable pnpm

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

# ESP32 RISV-V
RUN rustup target add riscv32imac-unknown-none-elf
RUN cargo install esp-generate --locked
RUN cargo install espflash --locked
RUN cargo install probe-rs-tools --locked
RUN cargo install cargo-generate --locked
RUN cargo install ldproxy --locked
RUN cargo install cargo-espflash --locked
RUN cargo install espup --locked
RUN espup install --targets esp32c6 --std

RUN rustup toolchain install nightly-2026-06-01 --component rust-src

# ARM64
RUN rustup target add aarch64-unknown-linux-gnu
RUN cat >> /home/op/.cargo/config.toml <<'EOF'
[target.aarch64-unknown-linux-gnu]
linker = "aarch64-linux-gnu-gcc"
EOF

# RUN python3 -m pip install --user python-docx
            
# ==========================================
# Opencode layer that should not be cached
# ==========================================
FROM base AS opencode

# Install OpenCode
# RUN curl -fsSL https://opencode.ai/install | bash
RUN curl -fsSL https://opencode.ai/v2/install | bash

# Opencode Plugins
# RUN npm install @bdliyq/opencode-rate-limit-retry@latest

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
