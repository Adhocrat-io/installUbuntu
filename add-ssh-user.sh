#!/usr/bin/env bash
# add-ssh-user.sh — Ajouter un utilisateur SSH (clé publique only) sur un serveur
# déjà durci par install.sh.
#
# Met à jour AllowUsers dans /etc/ssh/sshd_config.d/00-hardening.conf, désactive
# l'auth par mot de passe pour le user, et reload sshd après validation.
#
# Usage :
#   sudo bash add-ssh-user.sh [--no-sudo] <username> <pubkey-file|->
#
# Exemples :
#   sudo bash add-ssh-user.sh alice ~/alice.pub
#   echo 'ssh-ed25519 AAAA... alice@laptop' | sudo bash add-ssh-user.sh alice -
#   sudo bash add-ssh-user.sh --no-sudo readonly-bob ~/bob.pub

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# shellcheck source=lib/00-helpers.sh
source "${SCRIPT_DIR}/lib/00-helpers.sh"

usage() {
    sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-2}"
}

if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo "Ce script doit être lancé en root (sudo bash add-ssh-user.sh ...)." >&2
    exit 1
fi

WITH_SUDO=1
while [[ "${1:-}" == --* ]]; do
    case "$1" in
        --no-sudo) WITH_SUDO=0; shift ;;
        -h|--help) usage 0 ;;
        *) echo "Option inconnue : $1" >&2; usage 2 ;;
    esac
done

USERNAME="${1:-}"
KEYSRC="${2:-}"
[ -n "$USERNAME" ] && [ -n "$KEYSRC" ] || usage 2

# Validation nom d'utilisateur (POSIX-safe)
if ! [[ "$USERNAME" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
    die "Nom d'utilisateur invalide : $USERNAME"
fi

# Lecture de la clé publique
if [ "$KEYSRC" = "-" ]; then
    PUBKEY="$(cat)"
else
    [ -f "$KEYSRC" ] || die "Fichier clé introuvable : $KEYSRC"
    PUBKEY="$(cat "$KEYSRC")"
fi
# Une seule ligne, pas de CR/LF parasite
PUBKEY="$(printf '%s' "$PUBKEY" | tr -d '\r\n')"

# Validation format clé publique (ed25519, rsa, ecdsa, sk-ed25519)
if ! [[ "$PUBKEY" =~ ^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp[0-9]+|sk-ssh-ed25519@openssh\.com)[[:space:]]+[A-Za-z0-9+/=]+([[:space:]].+)?$ ]]; then
    die "Format de clé publique invalide. Attendu : 'ssh-ed25519 AAAA… commentaire'"
fi

# Création du user si absent
if id "$USERNAME" >/dev/null 2>&1; then
    log_info "User '$USERNAME' existe déjà — skip création."
else
    log_info "Création du user '$USERNAME' (shell bash, sans mot de passe)…"
    if [ "$WITH_SUDO" -eq 1 ]; then
        useradd -m -s /bin/bash -G sudo "$USERNAME"
    else
        useradd -m -s /bin/bash "$USERNAME"
    fi
    passwd -l "$USERNAME" >/dev/null
    log_ok "User '$USERNAME' créé$([ "$WITH_SUDO" -eq 1 ] && echo ' (sudoer)' || echo ' (sans sudo)')."
fi

# Si user existait déjà mais qu'on demande --no-sudo / sudo, on n'altère pas
# l'appartenance aux groupes — décision explicite de l'admin via gpasswd/usermod.

# Pose de la clé publique (idempotent)
SSH_DIR="/home/$USERNAME/.ssh"
AUTH_KEYS="$SSH_DIR/authorized_keys"
install -d -m 700 -o "$USERNAME" -g "$USERNAME" "$SSH_DIR"

if [ -f "$AUTH_KEYS" ] && grep -qF "$PUBKEY" "$AUTH_KEYS"; then
    log_info "Clé déjà présente dans $AUTH_KEYS — skip."
else
    printf '%s\n' "$PUBKEY" >> "$AUTH_KEYS"
    log_ok "Clé ajoutée à $AUTH_KEYS."
fi
chmod 600 "$AUTH_KEYS"
chown "$USERNAME:$USERNAME" "$AUTH_KEYS"

# Mise à jour AllowUsers dans la conf SSH durcie
HARDEN_CONF="/etc/ssh/sshd_config.d/00-hardening.conf"
[ -f "$HARDEN_CONF" ] || die "Conf SSH durcie introuvable : $HARDEN_CONF (ce serveur n'a pas été installé via install.sh ?)"

if grep -qE "^AllowUsers .*[[:space:]]${USERNAME}([[:space:]]|$)|^AllowUsers ${USERNAME}([[:space:]]|$)" "$HARDEN_CONF"; then
    log_info "'$USERNAME' déjà dans AllowUsers — skip."
elif grep -qE "^AllowUsers " "$HARDEN_CONF"; then
    sed -i -E "s|^(AllowUsers .*)$|\1 ${USERNAME}|" "$HARDEN_CONF"
    log_ok "'$USERNAME' ajouté à AllowUsers."
else
    echo "AllowUsers ${USERNAME}" >> "$HARDEN_CONF"
    log_ok "Directive AllowUsers créée avec '$USERNAME'."
fi

# Validation + reload sshd (rollback si KO)
if ! sshd -t 2>/tmp/sshd-test.err; then
    log_err "sshd -t a échoué après modification :"
    cat /tmp/sshd-test.err >&2
    die "Conf SSH invalide — corrige $HARDEN_CONF avant de relancer (rien n'a été reloadé)."
fi

systemctl reload ssh 2>/dev/null || systemctl restart ssh

# Récap
SSH_PORT="$(sshd -T 2>/dev/null | awk '$1=="port"{print $2; exit}')"
SSH_PORT="${SSH_PORT:-2222}"
SERVER_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"

log_ok "User '$USERNAME' prêt à se connecter."
echo "  → ssh -p ${SSH_PORT} ${USERNAME}@${SERVER_IP:-<ip-du-serveur>}"
