#!/usr/bin/env bash
# 16b-typesense — Typesense search engine, optionnel (si INSTALL_TYPESENSE=true)
# Bind 127.0.0.1:8108, API key généré aléatoirement, données /var/lib/typesense.
#
# Install direct via .deb officiel (plus déterministe que le repo APT, qui
# change parfois d'URL/format de clé GPG). Version pinnée via TYPESENSE_VERSION
# — override possible dans config.env pour forcer une autre version.

if [ "${INSTALL_TYPESENSE:-false}" != "true" ]; then
    log_info "INSTALL_TYPESENSE != true — skip Typesense."
    return 0
fi

TYPESENSE_VERSION="${TYPESENSE_VERSION:-30.0}"
save_config TYPESENSE_VERSION "$TYPESENSE_VERSION"

export DEBIAN_FRONTEND=noninteractive

# Idempotent : si déjà installé à la bonne version, on saute le téléchargement
INSTALLED_VERSION="$(dpkg-query -W -f='${Version}\n' typesense-server 2>/dev/null || true)"
if [ "$INSTALLED_VERSION" != "$TYPESENSE_VERSION" ]; then
    ARCH="$(dpkg --print-architecture)"   # amd64, arm64…
    DEB_URL="https://dl.typesense.org/releases/${TYPESENSE_VERSION}/typesense-server-${TYPESENSE_VERSION}-${ARCH}.deb"
    DEB_PATH="/tmp/typesense-server-${TYPESENSE_VERSION}-${ARCH}.deb"

    log_info "  → téléchargement Typesense ${TYPESENSE_VERSION} (${ARCH})…"
    curl -fL --max-time 120 --progress-bar "$DEB_URL" -o "$DEB_PATH" \
        || die "Téléchargement Typesense KO : $DEB_URL"

    log_info "  → installation du paquet .deb…"
    apt-get install -y -qq "$DEB_PATH"
    rm -f "$DEB_PATH"
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
