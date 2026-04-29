#!/usr/bin/env bash
# 01-preflight — Vérifications avant installation
# - root
# - Ubuntu 24.04 ou 25.04
# - User ubuntu présent avec clé SSH autorisée
# - Connectivité réseau

if ! command -v lsb_release >/dev/null 2>&1; then
    apt-get update -qq
    apt-get install -y -qq lsb-release
fi

DISTRIB_ID="$(lsb_release -is)"
DISTRIB_CODENAME="$(lsb_release -cs)"
DISTRIB_RELEASE="$(lsb_release -rs)"

[ "$DISTRIB_ID" = "Ubuntu" ] || die "Distribution non supportée : $DISTRIB_ID (attendu : Ubuntu)"

case "$DISTRIB_RELEASE" in
    24.04|25.04) log_ok "Ubuntu $DISTRIB_RELEASE ($DISTRIB_CODENAME) détecté." ;;
    *) die "Version non supportée : $DISTRIB_RELEASE (attendu : 24.04 ou 25.04)" ;;
esac

save_config UBUNTU_RELEASE "$DISTRIB_RELEASE"
save_config UBUNTU_CODENAME "$DISTRIB_CODENAME"

if ! id ubuntu >/dev/null 2>&1; then
    die "L'utilisateur 'ubuntu' n'existe pas. Crée-le d'abord (template OVH par défaut)."
fi

if [ ! -s /home/ubuntu/.ssh/authorized_keys ]; then
    die "/home/ubuntu/.ssh/authorized_keys vide ou absent — impossible de durcir SSH sans risquer un lockout."
fi

if ! groups ubuntu | grep -qE '\bsudo\b'; then
    log_warn "L'utilisateur ubuntu n'est pas dans le groupe sudo — ajout."
    usermod -aG sudo ubuntu
fi

if ! getent passwd ubuntu | grep -q '/bin/bash'; then
    chsh -s /bin/bash ubuntu
fi

if ! ping -c 1 -W 3 1.1.1.1 >/dev/null 2>&1; then
    die "Pas de connectivité réseau (ping 1.1.1.1 KO)."
fi

if ! command -v curl >/dev/null 2>&1; then
    apt-get install -y -qq curl
fi

log_ok "Préflight OK."
