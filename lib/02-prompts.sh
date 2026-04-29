#!/usr/bin/env bash
# 02-prompts — Collecte interactive de la configuration
#
# Variables produites (sauvegardées dans config.env) :
#   HOSTNAME, FQDN, DOMAIN, SLUG
#   REPO_URL, PROD_BRANCH, STAGING_BRANCH
#   ALERT_EMAIL

if [ -z "${HOSTNAME:-}" ]; then
    HOSTNAME="$(ask "Hostname court (ex. vps-monsite)")"
    save_config HOSTNAME "$HOSTNAME"
fi

if [ -z "${FQDN:-}" ]; then
    FQDN="$(ask "FQDN du serveur (ex. vps-monsite.example.com)")"
    save_config FQDN "$FQDN"
fi

if [ -z "${DOMAIN:-}" ]; then
    DOMAIN="$(ask "Domaine principal du site (ex. nomdusite.com)")"
    save_config DOMAIN "$DOMAIN"
fi

if [ -z "${SLUG:-}" ]; then
    # nomdusite.com → nomdusite-com
    SLUG="${DOMAIN//./-}"
    save_config SLUG "$SLUG"
fi
log_info "Slug calculé : ${SLUG} → /var/www/${SLUG}/{production,staging}"

if [ -z "${REPO_URL:-}" ]; then
    REPO_URL="$(ask "URL SSH du repo GitHub (git@github.com:user/repo.git)")"
    case "$REPO_URL" in
        git@github.com:*) ;;
        *) die "URL repo invalide. Format attendu : git@github.com:user/repo.git" ;;
    esac
    save_config REPO_URL "$REPO_URL"
fi

if [ -z "${PROD_BRANCH:-}" ]; then
    PROD_BRANCH="$(ask "Branche production" "main")"
    save_config PROD_BRANCH "$PROD_BRANCH"
fi

if [ -z "${STAGING_BRANCH:-}" ]; then
    STAGING_BRANCH="$(ask "Branche staging" "staging")"
    save_config STAGING_BRANCH "$STAGING_BRANCH"
fi

if [ -z "${ALERT_EMAIL:-}" ]; then
    ALERT_EMAIL="$(ask "Email pour alertes système et Let's Encrypt (mailé localement à ubuntu pour l'instant)" "ubuntu@${FQDN}")"
    save_config ALERT_EMAIL "$ALERT_EMAIL"
fi

if [ -z "${INSTALL_TYPESENSE:-}" ]; then
    if ask_yes_no "Installer Typesense (search engine local, bind 127.0.0.1:8108) ?" n; then
        INSTALL_TYPESENSE=true
    else
        INSTALL_TYPESENSE=false
    fi
    save_config INSTALL_TYPESENSE "$INSTALL_TYPESENSE"
fi

log_info "Configuration :"
log_info "  HOSTNAME          = $HOSTNAME"
log_info "  FQDN              = $FQDN"
log_info "  DOMAIN            = $DOMAIN (apex + www, staging.$DOMAIN)"
log_info "  SLUG              = $SLUG"
log_info "  REPO_URL          = $REPO_URL"
log_info "  PROD_BRANCH       = $PROD_BRANCH"
log_info "  STAGING_BRANCH    = $STAGING_BRANCH"
log_info "  ALERT_EMAIL       = $ALERT_EMAIL"
log_info "  INSTALL_TYPESENSE = $INSTALL_TYPESENSE"

ask_yes_no "Confirmer et continuer ?" o || die "Annulé par l'utilisateur."
