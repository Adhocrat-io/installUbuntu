#!/usr/bin/env bash
# 22-clone-and-bootstrap — git clone des deux branches, démarrage FrankenPHP, premier déploiement
#
# Ordre :
#   1. Clone prod + staging (en user ubuntu, donc via la deploy_key SSH).
#   2. Démarrage FrankenPHP (workers Octane encore désactivés ; certs Let's Encrypt obtenus).
#   3. Exécute deploy-production.sh puis deploy-staging.sh (composer, npm, migrate, octane:install, reload).

require_var REPO_URL PROD_BRANCH STAGING_BRANCH SLUG DOMAIN

WWW_BASE="/var/www/${SLUG}"

clone_if_empty() {
    local target="$1" branch="$2"
    if [ -d "${target}/.git" ]; then
        log_info "Repo déjà cloné dans ${target} — skip clone."
        return 0
    fi
    # Clone dans un dossier potentiellement non-vide : il faut le vider d'abord
    # (les ACLs et perms restent grâce à chown récursif après).
    if [ -n "$(ls -A "$target" 2>/dev/null)" ]; then
        log_warn "${target} non vide, nettoyage avant clone."
        find "$target" -mindepth 1 -delete
    fi
    sudo -u ubuntu git clone --branch "$branch" "$REPO_URL" "$target"
}

clone_if_empty "${WWW_BASE}/production" "$PROD_BRANCH"
clone_if_empty "${WWW_BASE}/staging"    "$STAGING_BRANCH"

# Permissions après clone (les fichiers viennent de git en mode 644/755 ubuntu:ubuntu,
# on rétablit ubuntu:www-data pour que FrankenPHP en groupe www-data lise).
chown -R ubuntu:www-data "$WWW_BASE"

# Pré-remplit .env si absent — credentials DB/Redis et APP_URL
load_secrets
populate_env() {
    local env_dir="$1" app_url="$2" db_name="$3" db_user="$4" db_pass="$5" app_env="$6"
    [ -f "${env_dir}/.env.example" ] || { log_warn "${env_dir}/.env.example absent — skip pré-remplissage."; return; }
    [ -f "${env_dir}/.env" ] && { log_info "${env_dir}/.env existe déjà — skip."; return; }
    cp "${env_dir}/.env.example" "${env_dir}/.env"
    set_or_append() {
        local key="$1" value="$2" file="$3"
        # Échappement basique pour sed : | \\ &
        local escaped="${value//\\/\\\\}"
        escaped="${escaped//&/\\&}"
        escaped="${escaped//|/\\|}"
        if grep -qE "^${key}=" "$file"; then
            sed -i "s|^${key}=.*|${key}=${escaped}|" "$file"
        else
            echo "${key}=${value}" >> "$file"
        fi
    }
    set_or_append APP_ENV       "$app_env"        "${env_dir}/.env"
    set_or_append APP_URL       "https://${app_url}" "${env_dir}/.env"
    set_or_append DB_CONNECTION mysql              "${env_dir}/.env"
    set_or_append DB_HOST       127.0.0.1          "${env_dir}/.env"
    set_or_append DB_PORT       3306               "${env_dir}/.env"
    set_or_append DB_DATABASE   "$db_name"         "${env_dir}/.env"
    set_or_append DB_USERNAME   "$db_user"         "${env_dir}/.env"
    set_or_append DB_PASSWORD   "$db_pass"         "${env_dir}/.env"
    set_or_append REDIS_HOST    127.0.0.1          "${env_dir}/.env"
    set_or_append REDIS_PORT    6379               "${env_dir}/.env"
    set_or_append REDIS_PASSWORD "$REDIS_PWD"      "${env_dir}/.env"
    set_or_append CACHE_STORE   redis              "${env_dir}/.env"
    set_or_append SESSION_DRIVER redis             "${env_dir}/.env"
    set_or_append QUEUE_CONNECTION redis           "${env_dir}/.env"
    # APP_KEY laissé vide ici — généré par deploy.sh après composer install (vendor/ requis).
    chown ubuntu:www-data "${env_dir}/.env"
    chmod 640 "${env_dir}/.env"
    log_ok "${env_dir}/.env pré-rempli (APP_KEY sera généré au déploiement)."
}

populate_env "${WWW_BASE}/production" "${DOMAIN}"          "$DB_NAME_PROD"    "$DB_USER_PROD"    "$DB_PROD_PWD"    production
populate_env "${WWW_BASE}/staging"    "staging.${DOMAIN}"  "$DB_NAME_STAGING" "$DB_USER_STAGING" "$DB_STAGING_PWD" staging

# DNS check : éviter rate-limit Let's Encrypt si DNS pas propagé (5 échecs/h/account)
SERVER_IP="$(curl -fsSL https://api.ipify.org 2>/dev/null || curl -fsSL https://ifconfig.me 2>/dev/null || echo "")"
[ -n "$SERVER_IP" ] || die "Impossible de récupérer l'IP publique du serveur (api.ipify.org/ifconfig.me KO)."

DNS_OK=1
for d in "$DOMAIN" "www.${DOMAIN}" "staging.${DOMAIN}"; do
    resolved="$(getent ahostsv4 "$d" | awk '{print $1}' | sort -u | head -n1)"
    if [ -z "$resolved" ]; then
        log_warn "DNS : $d ne résout pas."
        DNS_OK=0
    elif [ "$resolved" != "$SERVER_IP" ]; then
        log_warn "DNS : $d → $resolved (attendu: $SERVER_IP)"
        DNS_OK=0
    else
        log_ok "DNS : $d → $resolved ✓"
    fi
done

if [ "$DNS_OK" -ne 1 ]; then
    log_warn "Certaines entrées DNS ne pointent pas (encore) sur le serveur."
    log_warn "Risque : rate-limit Let's Encrypt (5 échecs/heure)."
    if ! ask_yes_no "Démarrer FrankenPHP malgré tout ?" n; then
        die "Configure le DNS d'abord, puis relance le script (le module 22 reprendra ici)."
    fi
fi

# Démarrer FrankenPHP maintenant (workers Octane désactivés dans le Caddyfile,
# le service va servir les sites en mode classique php_server jusqu'au reload post-deploy).
systemctl enable --now frankenphp

# Petit délai pour laisser Let's Encrypt démarrer
sleep 3

# Premier déploiement — en user ubuntu, comme un webhook futur.
sudo -u ubuntu /usr/local/bin/deploy-production.sh
sudo -u ubuntu /usr/local/bin/deploy-staging.sh

log_ok "Bootstrap terminé : sites cloned + premier deploy OK + FrankenPHP up."
