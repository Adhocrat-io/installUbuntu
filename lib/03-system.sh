#!/usr/bin/env bash
# 03-system — hostname, /etc/hosts, timezone, locales, swap, NTP

require_var HOSTNAME FQDN

# Hostname / FQDN
hostnamectl set-hostname "$HOSTNAME"

if grep -qE "^127\.0\.1\.1\b" /etc/hosts; then
    sed -i "s|^127\.0\.1\.1.*|127.0.1.1\t${FQDN} ${HOSTNAME}|" /etc/hosts
else
    printf '127.0.1.1\t%s %s\n' "$FQDN" "$HOSTNAME" >> /etc/hosts
fi

# Timezone
timedatectl set-timezone Europe/Paris

# Locales
apt-get install -y -qq locales
locale-gen en_US.UTF-8 fr_FR.UTF-8 >/dev/null
update-locale LANG=fr_FR.UTF-8 LC_ALL=fr_FR.UTF-8

# NTP via systemd-timesyncd (présent par défaut)
timedatectl set-ntp true

# Swap 2G si pas de swap
if [ "$(swapon --noheadings | wc -l)" -eq 0 ]; then
    log_info "Création swap 2G…"
    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile >/dev/null
    swapon /swapfile
    if ! grep -q '^/swapfile' /etc/fstab; then
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi
    # Tunables : moins de swap quand mémoire dispo
    cat > /etc/sysctl.d/99-swap.conf <<'EOF'
vm.swappiness = 10
vm.vfs_cache_pressure = 50
EOF
    sysctl --system >/dev/null
fi

log_ok "Système configuré (hostname=${HOSTNAME}, tz=Europe/Paris, locale=fr_FR.UTF-8, swap=2G)."
