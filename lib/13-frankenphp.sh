#!/usr/bin/env bash
# 13-frankenphp — binaire statique + Caddyfile + service systemd
# User=ubuntu + AmbientCapabilities=CAP_NET_BIND_SERVICE pour 80/443 sans root

require_var DOMAIN SLUG ALERT_EMAIL

# Préflight : qui écoute sur 80/443 ? Renvoie sur stdout les noms de process
# uniques (un par ligne). Vide si rien n'écoute.
listeners_on_80_443() {
    ss -tlnHp '( sport = :80 or sport = :443 )' 2>/dev/null \
        | grep -oE 'users:\(\("[^"]+"' \
        | sed -E 's/^users:\(\(\"//; s/"$//' \
        | sort -u
}

# Préflight : ports 80/443 doivent être libres (ou occupés par FrankenPHP lui-même
# si on rejoue le module). Cas typique à neutraliser : nginx préinstallé sur l'image VPS.
preflight_ports_80_443() {
    local procs
    procs="$(listeners_on_80_443)"
    [ -n "$procs" ] || return 0

    log_warn "Ports 80/443 occupés par : ${procs//$'\n'/, }"

    # Si seul FrankenPHP écoute, c'est qu'on rejoue le module (validate ok, reload
    # plus loin). Rien à faire.
    if [ "$procs" = "frankenphp" ]; then
        log_info "FrankenPHP déjà en place — preflight OK (rejeu du module)."
        return 0
    fi

    # nginx présent (avec ou sans autre process) → purge complet.
    # nginx-common laisse traîner une conf qui peut repartir au reboot via apt.
    if printf '%s\n' "$procs" | grep -qx nginx; then
        log_warn "nginx détecté — il bloque FrankenPHP."
        if ask_yes_no "Désinstaller nginx complètement (stop + disable + apt purge) ?" o; then
            systemctl disable --now nginx 2>/dev/null || true
            DEBIAN_FRONTEND=noninteractive apt-get -y purge 'nginx*' || true
            DEBIAN_FRONTEND=noninteractive apt-get -y autoremove --purge || true
            log_ok "nginx désinstallé."
        else
            die "Libère les ports 80/443 puis relance — FrankenPHP ne peut pas démarrer sinon."
        fi
    else
        die "Ports 80/443 occupés par : ${procs//$'\n'/, } — investigue avec : sudo ss -tlnp | grep -E ':80|:443'"
    fi

    # Re-vérification : il ne doit plus rester que rien (ou frankenphp si déjà up).
    procs="$(listeners_on_80_443)"
    if [ -n "$procs" ] && [ "$procs" != "frankenphp" ]; then
        die "Ports 80/443 toujours occupés après purge nginx : ${procs//$'\n'/, }"
    fi
}
preflight_ports_80_443

# Sous-dossier de l'app dans le repo (vide par défaut → racine).
# {{APP_SUBDIR_PATH}} dans le Caddyfile vaut "" ou "/web-overlay".
APP_SUBDIR_PATH="${APP_SUBDIR:+/${APP_SUBDIR}}"
export APP_SUBDIR_PATH

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
chmod 2775 /var/log/frankenphp /var/lib/caddy

# Pré-création des log files en ubuntu:ubuntu pour neutraliser un piège connu :
# `frankenphp validate` charge la config et ouvre les loggers en écriture, donc
# CRÉE les fichiers manquants. Si validate tourne en root (ce qui arrive via
# enable-octane-worker.sh appelé en sudo depuis deploy.sh), les fichiers sont
# créés root-owned, et le service (User=ubuntu) ne peut plus écrire dessus.
# Le setgid sur le dossier (chmod 2775) garantit aussi que tout nouveau fichier
# hérite du groupe ubuntu — defense in depth.
for logfile in access.log production.log staging.log; do
    install -m 0664 -o ubuntu -g ubuntu /dev/null "/var/log/frankenphp/${logfile}"
done

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
