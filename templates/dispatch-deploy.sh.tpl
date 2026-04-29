#!/usr/bin/env bash
# /usr/local/bin/dispatch-deploy.sh
# Reçu en argument $1 : la ref Git poussée (ex. refs/heads/main).
# Lance le bon script de déploiement selon la branche, ignore les autres.

set -euo pipefail

REF="${1:-}"
LOG=/var/log/deploy.log

ts() { date -Iseconds; }
log() { printf '[%s] %s\n' "$(ts)" "$*" >> "$LOG"; }

log "dispatch ref=${REF}"

case "$REF" in
    refs/heads/{{PROD_BRANCH}})
        log "→ deploy-production.sh"
        exec /usr/local/bin/deploy-production.sh >> "$LOG" 2>&1
        ;;
    refs/heads/main|refs/heads/master)
        # Filet de sécurité si PROD_BRANCH != main/master
        log "→ deploy-production.sh (fallback main/master)"
        exec /usr/local/bin/deploy-production.sh >> "$LOG" 2>&1
        ;;
    refs/heads/{{STAGING_BRANCH}})
        log "→ deploy-staging.sh"
        exec /usr/local/bin/deploy-staging.sh >> "$LOG" 2>&1
        ;;
    *)
        log "branche ignorée : ${REF}"
        exit 0
        ;;
esac
