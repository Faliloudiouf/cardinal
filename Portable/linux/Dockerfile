# Environnement de construction Linux (x86_64) de Cardinal : Ubuntu 22.04 pour une large
# compatibilité des paquets (glibc 2.35), Node 22, Rust stable et les bibliothèques de Tauri.
FROM --platform=linux/amd64 ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      curl ca-certificates build-essential pkg-config file rpm patchelf xdg-utils \
      libwebkit2gtk-4.1-dev libappindicator3-dev librsvg2-dev libssl-dev \
    && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL https://sh.rustup.rs | sh -s -- -y --profile minimal
ENV PATH=/root/.cargo/bin:$PATH
WORKDIR /travail
