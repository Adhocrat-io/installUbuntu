#!/usr/bin/env bash
# 13-frankenphp — binaire statique + Caddyfile + service systemd
# User=ubuntu + AmbientCapabilities=CAP_NET_BIND_SERVICE pour 80/443 sans root

require_var DOMAIN SLUG ALERT_EMAIL

# Téléchargement du binaire FrankenPHP officiel
ARCH="$(uname -m)"
case "$ARCH" in
    x86_64) FP_ARCH="x86_64" ;;
    aarch64|arm64) FP_ARCH="aarch64" ;;
    *) die "Architecture non supportée pour FrankenPHP : $ARCH" ;;
esac

if [ ! -x /usr/local/bin/frankenphp ]; then
    log_info "  → téléchargement binaire FrankenPHP (${FP_ARCH}, ~50 Mo)…"
    curl -fL --max-time 300 --progress-bar \
        "https://github.com/php/frankenphp/releases/latest/download/frankenphp-linux-${FP_ARCH}" \
        -o /usr/local/bin/frankenphp \
        || die "Téléchargement FrankenPHP KO."
    chmod +x /usr/local/bin/frankenphp
fi

# Capabilities pour bind 80/443 sans root (le service systemd l'octroiera aussi)
setcap 'cap_net_bind_service=+ep' /usr/local/bin/frankenphp || true

# Arborescence Caddy
mkdir -p /etc/frankenphp /var/log/frankenphp /var/lib/caddy
chown -R ubuntu:ubuntu /var/log/frankenphp /var/lib/caddy
chmod 755 /var/log/frankenphp /var/lib/caddy

# Caddyfile généré depuis template
render_template "${SCRIPT_DIR}/templates/Caddyfile.tpl" /etc/frankenphp/Caddyfile

# Validation
if ! /usr/local/bin/frankenphp validate --config /etc/frankenphp/Caddyfile 2>/tmp/caddy-validate.err; then
    log_err "Caddyfile invalide :"
    cat /tmp/caddy-validate.err >&2
    die "Conf FrankenPHP invalide."
fi

# Service systemd
install -m 0644 "${SCRIPT_DIR}/templates/frankenphp.service.tpl" /etc/systemd/system/frankenphp.service

# Sudoers : ubuntu peut reload le service sans password
install -m 0440 "${SCRIPT_DIR}/templates/sudoers-ubuntu" /etc/sudoers.d/ubuntu-deploy
visudo -cf /etc/sudoers.d/ubuntu-deploy >/dev/null

# enable-octane-worker.sh : décommente le worker dans le Caddyfile au premier déploiement
install -m 0755 "${SCRIPT_DIR}/templates/enable-octane-worker.sh.tpl" /usr/local/bin/enable-octane-worker.sh

systemctl daemon-reload
# Le service sera démarré APRÈS le bootstrap (clone + premier déploiement) — module 22.
# On ne le démarre pas ici pour éviter Let's Encrypt en boucle sur des dossiers vides.

log_ok "FrankenPHP installé (service prêt, démarrage différé après bootstrap)."
