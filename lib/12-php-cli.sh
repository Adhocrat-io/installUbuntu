#!/usr/bin/env bash
# 12-php-cli — PHP 8.5 CLI + extensions (pour artisan/composer/build).
# Le runtime serveur est FrankenPHP (binaire statique, voir module 13).

require_var UBUNTU_CODENAME

export DEBIAN_FRONTEND=noninteractive

# PPA ondrej/php
if [ ! -f /etc/apt/sources.list.d/ondrej-ubuntu-php-${UBUNTU_CODENAME}.sources ] \
   && [ ! -f /etc/apt/sources.list.d/ondrej-ubuntu-php-${UBUNTU_CODENAME}.list ]; then
    log_info "  → ajout du PPA ondrej/php…"
    add-apt-repository -y ppa:ondrej/php
    log_info "  → apt update (sources PPA)…"
    apt-get update -qq
fi

# Extensions critiques (DOIVENT être dispo dans le PPA pour la version cible — sinon fallback)
PHP_EXTS_CRITICAL=(cli common mbstring xml curl gd intl bcmath mysql redis zip opcache)
# Extensions optionnelles (skip si pas dispo en tant que paquet séparé — ex. pcntl est built-in)
PHP_EXTS_OPTIONAL=(soap readline imagick)

# Tente PHP 8.5 — si UNE extension critique manque, fallback 8.4
PHP_VERSION="8.5"
missing_critical=()
for ext in "${PHP_EXTS_CRITICAL[@]}"; do
    apt-cache show "php${PHP_VERSION}-${ext}" >/dev/null 2>&1 \
        || missing_critical+=("php${PHP_VERSION}-${ext}")
done

if [ "${#missing_critical[@]}" -gt 0 ]; then
    log_warn "PHP ${PHP_VERSION} : extensions critiques absentes du PPA → ${missing_critical[*]}"
    log_warn "Fallback sur PHP 8.4."
    PHP_VERSION="8.4"
    missing_critical=()
    for ext in "${PHP_EXTS_CRITICAL[@]}"; do
        apt-cache show "php${PHP_VERSION}-${ext}" >/dev/null 2>&1 \
            || missing_critical+=("php${PHP_VERSION}-${ext}")
    done
    [ "${#missing_critical[@]}" -gt 0 ] && die "PHP 8.4 manque aussi : ${missing_critical[*]}"
fi

save_config PHP_VERSION "$PHP_VERSION"

# Construction finale : critiques + optionnelles dispo
pkgs=()
for ext in "${PHP_EXTS_CRITICAL[@]}"; do
    pkgs+=("php${PHP_VERSION}-${ext}")
done
for ext in "${PHP_EXTS_OPTIONAL[@]}"; do
    if apt-cache show "php${PHP_VERSION}-${ext}" >/dev/null 2>&1; then
        pkgs+=("php${PHP_VERSION}-${ext}")
    else
        log_warn "Extension optionnelle absente : php${PHP_VERSION}-${ext} (skip)."
    fi
done

log_info "  → installation PHP ${PHP_VERSION} + ${#pkgs[@]} paquets (peut prendre 1-2 min)…"
apt-get install -y -qq "${pkgs[@]}"

update-alternatives --set php "/usr/bin/php${PHP_VERSION}" 2>/dev/null || true

log_ok "PHP ${PHP_VERSION} CLI installé avec extensions."
