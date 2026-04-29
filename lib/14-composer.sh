#!/usr/bin/env bash
# 14-composer — installation Composer global

if [ -x /usr/local/bin/composer ] || command -v composer >/dev/null 2>&1; then
    log_info "Composer déjà installé (/usr/local/bin/composer)."
    return 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' RETURN

log_info "  → récupération signature attendue (composer.github.io)…"
EXPECTED_SIG="$(curl -fsSL --max-time 30 https://composer.github.io/installer.sig)" \
    || die "Impossible de récupérer la signature Composer (timeout/réseau)."

log_info "  → téléchargement composer-setup.php (getcomposer.org)…"
curl -fL --max-time 60 -o "${TMP}/composer-setup.php" https://getcomposer.org/installer \
    || die "Téléchargement Composer KO."

log_info "  → vérification de la signature SHA384…"
ACTUAL_SIG="$(php -r "echo hash_file('sha384', '${TMP}/composer-setup.php');")"
[ "$ACTUAL_SIG" = "$EXPECTED_SIG" ] || die "Composer installer corrompu (signature mismatch)."

log_info "  → installation de Composer dans /usr/local/bin…"
php "${TMP}/composer-setup.php" --install-dir=/usr/local/bin --filename=composer

log_ok "Composer installé : $(composer --version --no-ansi 2>/dev/null | head -n1)"
