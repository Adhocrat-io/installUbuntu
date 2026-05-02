#!/usr/bin/env bash
# Installation automatisée VPS OVH — Ubuntu 24.04 LTS / 25.04
# FrankenPHP/Octane + PHP 8.5 + MariaDB + Redis + Node 20 + déploiement webhook GitHub.
#
# Usage : sudo bash install.sh
#
# Prérequis :
#  - VPS OVH fraîchement installé sous Ubuntu 24.04 LTS ou 25.04
#  - User `ubuntu` existant avec clé SSH déjà autorisée
#  - DNS du domaine pointant déjà vers l'IP du serveur (apex + www + staging.*)
#  - Repo GitHub avec deux branches (main/master + staging)

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
export SCRIPT_DIR

STATE_DIR="/var/lib/install-ubuntu"
CONFIG_FILE="${STATE_DIR}/config.env"
LOG_FILE="/var/log/install-ubuntu.log"
export STATE_DIR CONFIG_FILE LOG_FILE

# Évite tout prompt interactif sur Ubuntu 24.04+ :
# - DEBIAN_FRONTEND=noninteractive : apt ne pose aucune question (conf files…)
# - NEEDRESTART_MODE=a : needrestart auto-restart les services sans demander
# - NEEDRESTART_SUSPEND=1 : ceinture ET bretelles si la conf drop-in tarde
# Le module 04-packages dépose en plus une conf permanente dans /etc/needrestart/conf.d/.
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1

if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo "Ce script doit être lancé en root (sudo bash install.sh)." >&2
    exit 1
fi

mkdir -p "$STATE_DIR"
touch "$LOG_FILE"
chmod 600 "$LOG_FILE"

# shellcheck source=lib/00-helpers.sh
source "${SCRIPT_DIR}/lib/00-helpers.sh"

if [ -f "$CONFIG_FILE" ]; then
    log_info "Reprise : configuration trouvée dans ${CONFIG_FILE}"
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
fi

MODULES=(
    01-preflight
    02-prompts
    03-system
    04-packages
    05-ssh-hardening
    06-ufw
    07-crowdsec
    08-kernel-hardening
    09-fs-hardening
    10-unattended-upgrades
    11-mariadb
    12-php-cli
    13-frankenphp
    14-composer
    15-node-yarn
    16-redis
    16b-typesense
    17-supervisor
    18-postfix
    19-www-tree
    20-deploy-key
    21-clone-deploy-scripts
    22-clone-and-bootstrap
    23-webhook
    24-mariadb-backup
    25-ember
    26-logrotate
    99-finalize
)

for module in "${MODULES[@]}"; do
    module_path="${SCRIPT_DIR}/lib/${module}.sh"
    if [ ! -f "$module_path" ]; then
        log_err "Module manquant : ${module_path}"
        exit 1
    fi

    if is_done "$module"; then
        log_info "Module ${module} déjà appliqué — skip."
        continue
    fi

    log_info "▶  Module ${module}…"
    # shellcheck disable=SC1090
    source "$module_path"
    mark_done "$module"
done

log_info "✔ Installation terminée."
log_info "→ Tous les secrets et l'URL webhook GitHub sont dans /home/ubuntu/passwords.md (chmod 600)."
log_info "→ Lis ce fichier, configure le webhook GitHub, puis pousse sur main et staging."
