#!/usr/bin/env bash
# 25-netdata — monitoring local, bind 127.0.0.1 uniquement, accès via SSH tunnel.
# Pas d'ouverture firewall, pas de cloud Netdata.

if command -v netdata >/dev/null 2>&1 && systemctl is-enabled --quiet netdata; then
    log_info "Netdata déjà installé."
else
    log_info "  → téléchargement et exécution du kickstart Netdata (peut prendre plusieurs minutes)…"
    bash <(curl -fsSL --max-time 60 https://my-netdata.io/kickstart.sh) \
        --dont-wait \
        --disable-telemetry \
        --no-updates 2>&1 | tee -a "$LOG_FILE"
fi

# Bind localhost
mkdir -p /etc/netdata
if [ -f /etc/netdata/netdata.conf ]; then
    if ! grep -qE '^\s*bind socket to IP\s*=\s*127\.0\.0\.1' /etc/netdata/netdata.conf; then
        # Soit la section [web] existe, soit il faut la créer
        if grep -q '^\[web\]' /etc/netdata/netdata.conf; then
            sed -i '/^\[web\]/a\    bind socket to IP = 127.0.0.1' /etc/netdata/netdata.conf
        else
            cat >> /etc/netdata/netdata.conf <<'EOF'

[web]
    bind socket to IP = 127.0.0.1
    default port = 19999
EOF
        fi
    fi
fi

systemctl enable netdata
systemctl restart netdata

log_ok "Netdata installé sur 127.0.0.1:19999. Accès : ssh -p 2222 -L 19999:127.0.0.1:19999 ubuntu@<host>"
