#!/usr/bin/env bash
# 04-packages — paquets de base

export DEBIAN_FRONTEND=noninteractive

# Conf needrestart permanente : pas de prompt interactif lors des futurs upgrades
# (cron unattended-upgrades, apt manuel, etc.). Indispensable sur Ubuntu 24.04+
# où needrestart est installé par défaut et bloque les sessions non-tty.
if [ -d /etc/needrestart/conf.d ] || apt-cache show needrestart >/dev/null 2>&1; then
    mkdir -p /etc/needrestart/conf.d
    cat > /etc/needrestart/conf.d/99-auto.conf <<'EOF'
# Géré par installUbuntu — auto-restart sans prompt
$nrconf{restart} = 'a';
$nrconf{kernelhints} = -1;
EOF
fi

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
