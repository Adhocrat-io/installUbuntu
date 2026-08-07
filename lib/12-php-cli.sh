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
PHP_EXTS_CRITICAL=(cli common mbstring xml curl gd intl bcmath mysql redis zip)
# Extensions optionnelles (skip si pas dispo en tant que paquet séparé — ex. pcntl est built-in).
#
# opcache est dans cette liste et NON dans les critiques : depuis PHP 8.5 le PPA
# ondrej ne publie plus de paquet phpX.Y-opcache séparé, l'extension est fournie
# par phpX.Y-common. La classer critique déclenchait un fallback sur PHP 8.4 alors
# que PHP 8.5 est parfaitement installable. Sa présence réelle est vérifiée après
# installation (voir le contrôle Zend OPcache en fin de module).
PHP_EXTS_OPTIONAL=(soap readline imagick opcache)

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

# Drop-in ini pour élargir les limites d'upload (par défaut 2 Mo / fichier,
# max 20 fichiers — insuffisant pour la médiathèque admin). Copié dans
# les conf.d cli ET fpm. Perms 0644 explicites : sudo tee créerait sinon
# un fichier en 0640 root:root que PHP CLI ne parvient pas à lire.
for target in /etc/php/${PHP_VERSION}/cli/conf.d /etc/php/${PHP_VERSION}/fpm/conf.d; do
    [ -d "$target" ] || continue
    install -m 0644 "${SCRIPT_DIR}/templates/php-upload-limits.ini" \
        "${target}/99-upload-limits.ini"
done

# opcache n'est plus un paquet séparé à partir de 8.5 (fourni par phpX.Y-common) :
# on vérifie donc que l'extension est réellement chargée, quelle que soit sa
# provenance, plutôt que de se fier à l'existence d'un paquet.
if "/usr/bin/php${PHP_VERSION}" -m 2>/dev/null | grep -qix "zend opcache"; then
    log_ok "Zend OPcache chargé pour PHP ${PHP_VERSION}."
else
    log_warn "Zend OPcache absent de PHP ${PHP_VERSION} — performances dégradées."
    log_warn "Vérifie : php${PHP_VERSION} -m | grep -i opcache"
fi

log_ok "PHP ${PHP_VERSION} CLI installé avec extensions."
