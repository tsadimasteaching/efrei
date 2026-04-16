FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    strace \
    nmap \
    wget \
    curl \
    python3 \
    libcap2-bin \
    apparmor \
    apparmor-profiles \
    apparmor-utils \
    uidmap \
    busybox \
    && rm -rf /var/lib/apt/lists/*
