#!/usr/bin/env bash
# 25-ember — Ember : dashboard TUI temps réel pour Caddy/FrankenPHP.
# https://github.com/alexandre-daubois/ember
#
# Pas de service en daemon, pas de port à exposer : `ember` se lance en
# interactif depuis SSH, lit l'admin API Caddy locale (127.0.0.1:2019),
# et affiche un TUI (RPS/latence/percentiles/threads FrankenPHP/logs).

if command -v ember >/dev/null 2>&1; then
    log_info "Ember déjà installé ($(ember --version 2>/dev/null | head -n1))."
else
    arch="$(uname -m)"
    case "$arch" in
        x86_64|amd64)   ember_arch=amd64 ;;
        aarch64|arm64)  ember_arch=arm64 ;;
        *) die "Architecture non supportée pour Ember : $arch" ;;
    esac

    log_info "  → résolution dernière release Ember…"
    ember_version="$(curl -fsSL --max-time 30 \
        https://api.github.com/repos/alexandre-daubois/ember/releases/latest \
        | grep -oP '"tag_name":\s*"v?\K[^"]+')"
    [ -n "$ember_version" ] || die "Impossible de déterminer la version Ember."

    tmp_dir="$(mktemp -d)"
    asset="ember_${ember_version}_linux_${ember_arch}.tar.gz"
    base_url="https://github.com/alexandre-daubois/ember/releases/download/v${ember_version}"

    log_info "  → téléchargement de ${asset}…"
    curl -fsSL --max-time 120 -o "${tmp_dir}/${asset}"      "${base_url}/${asset}" \
        || { rm -rf "$tmp_dir"; die "Téléchargement Ember KO."; }
    curl -fsSL --max-time 30  -o "${tmp_dir}/checksums.txt" "${base_url}/checksums.txt" \
        || { rm -rf "$tmp_dir"; die "Téléchargement checksums Ember KO."; }

    if ! (cd "$tmp_dir" && grep " ${asset}\$" checksums.txt | sha256sum -c - >/dev/null); then
        rm -rf "$tmp_dir"
        die "Checksum Ember invalide pour ${asset}."
    fi

    tar -C "$tmp_dir" -xzf "${tmp_dir}/${asset}"
    install -m 0755 "${tmp_dir}/ember" /usr/local/bin/ember
    rm -rf "$tmp_dir"

    log_ok "Ember v${ember_version} installé : /usr/local/bin/ember"
fi

# Active les métriques Prometheus sur l'admin API Caddy si pas déjà fait,
# sans restart (hot-reload via admin API). Soft-fail : si Caddy n'est pas
# encore prêt à ce stade, l'utilisateur relancera `ember init` en SSH.
if systemctl is-active --quiet frankenphp; then
    log_info "  → ember init (active les métriques Caddy)…"
    if ! ember init </dev/null 2>&1 | tee -a "$LOG_FILE"; then
        log_warn "ember init a échoué — relance manuellement en SSH : \`ember init\`."
    fi
else
    log_warn "FrankenPHP non actif — exécute \`ember init\` en SSH après le premier déploiement."
fi
