#!/usr/bin/env bash
# 16b-typesense — Typesense search engine, optionnel (si INSTALL_TYPESENSE=true)
# Bind 127.0.0.1:8108, API key généré aléatoirement, données /var/lib/typesense.

if [ "${INSTALL_TYPESENSE:-false}" != "true" ]; then
    log_info "INSTALL_TYPESENSE != true — skip Typesense."
    return 0
fi

export DEBIAN_FRONTEND=noninteractive

# Idempotent : si déjà installé, on continue (chmod / API key /etc régénérés).
if ! command -v typesense-server >/dev/null 2>&1; then
    log_info "  → ajout du repo APT Typesense (signed-by keyring)…"
    install -d -m 0755 /etc/apt/keyrings
    curl -fsSL --max-time 30 https://dl.typesense.org/apt/typesense-bookworm.gpg.key \
        | gpg --dearmor -o /etc/apt/keyrings/typesense.gpg
    chmod 0644 /etc/apt/keyrings/typesense.gpg

    cat > /etc/apt/sources.list.d/typesense.list <<'EOF'
deb [signed-by=/etc/apt/keyrings/typesense.gpg] https://dl.typesense.org/apt/ bookworm main
EOF

    log_info "  → apt update (sources Typesense)…"
    apt-get update -qq

    log_info "  → installation typesense-server…"
    apt-get install -y -qq typesense-server
fi

# Génération / réutilisation de l'API key (depuis .secrets.env si re-run)
load_secrets
TYPESENSE_API_KEY="${TYPESENSE_API_KEY:-$(gen_password)}"
record_secret TYPESENSE_API_KEY "$TYPESENSE_API_KEY"

# Conf : bind loopback strict, data + log dirs cohérents avec le packaging Debian
install -d -m 0750 -o typesense -g typesense /var/lib/typesense /var/log/typesense

cat > /etc/typesense/typesense-server.ini <<EOF
# Géré par installUbuntu — toute édition manuelle sera écrasée au prochain run du module 16b.
[server]
api-key = ${TYPESENSE_API_KEY}
data-dir = /var/lib/typesense
api-address = 127.0.0.1
api-port = 8108
log-dir = /var/log/typesense
enable-cors = false
EOF
chown root:typesense /etc/typesense/typesense-server.ini
chmod 0640 /etc/typesense/typesense-server.ini

systemctl daemon-reload
systemctl enable --now typesense-server

# Sanity check : Typesense doit répondre sur /health (200 OK)
sleep 2
if curl -fsS --max-time 5 http://127.0.0.1:8108/health >/dev/null 2>&1; then
    log_ok "Typesense actif (bind 127.0.0.1:8108, /health OK)."
else
    log_warn "Typesense installé mais /health KO — vérifie : journalctl -u typesense-server -n 30"
fi
