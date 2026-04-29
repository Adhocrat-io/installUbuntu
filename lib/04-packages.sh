#!/usr/bin/env bash
# 04-packages — paquets de base

export DEBIAN_FRONTEND=noninteractive

log_info "  → apt update…"
apt-get update -qq

log_info "  → apt upgrade (peut prendre plusieurs minutes)…"
apt-get upgrade -y -qq

log_info "  → installation paquets de base…"
apt-get install -y -qq \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    software-properties-common \
    apt-transport-https \
    ufw \
    git \
    vim \
    jq \
    htop \
    unzip \
    rsync \
    acl \
    cron \
    logrotate \
    openssl \
    openssh-server \
    debian-keyring \
    debian-archive-keyring \
    bash-completion

log_ok "Paquets de base installés."
