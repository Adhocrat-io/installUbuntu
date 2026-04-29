#!/usr/bin/env bash
# add-ssh-user.sh — Ajouter un utilisateur SSH (clé publique only) sur un serveur
# déjà durci par install.sh.
#
# Met à jour AllowUsers dans /etc/ssh/sshd_config.d/00-hardening.conf, désactive
# l'auth par mot de passe pour le user, et reload sshd après validation.
#
# Modes :
#   (défaut)            user sudoer indépendant, avec son propre home
#   --no-sudo           user sans sudo, avec son propre home
#   --proxy-to-ubuntu   user qui atterrit AUTOMATIQUEMENT dans le shell d'ubuntu
#                       à la connexion (sudo -u ubuntu transparent). Idéal pour
#                       les devs : ils n'ont pas à taper sudo, leurs commandes
#                       affectent l'arborescence /var/www/* (owned ubuntu)
#                       directement, et l'audit garde la trace de leur identité
#                       (clé SSH + log sudo alice→ubuntu).
#
# Usage :
#   sudo bash add-ssh-user.sh [--no-sudo|--proxy-to-ubuntu] <username> <pubkey-file|->
#
# Exemples :
#   sudo bash add-ssh-user.sh alice ~/alice.pub
#   echo 'ssh-ed25519 AAAA... alice@laptop' | sudo bash add-ssh-user.sh alice -
#   sudo bash add-ssh-user.sh --no-sudo readonly-bob ~/bob.pub
#   sudo bash add-ssh-user.sh --proxy-to-ubuntu dev-charlie ~/charlie.pub

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# shellcheck source=lib/00-helpers.sh
source "${SCRIPT_DIR}/lib/00-helpers.sh"

PROXY_GROUP="ssh-proxy-ubuntu"
PROXY_SCRIPT="/usr/local/bin/ssh-proxy-to-ubuntu"
PROXY_SUDOERS="/etc/sudoers.d/ssh-proxy-ubuntu"

usage() {
    sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-2}"
}

if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo "Ce script doit être lancé en root (sudo bash add-ssh-user.sh ...)." >&2
    exit 1
fi

MODE="sudoer"   # sudoer | nosudo | proxy
while [[ "${1:-}" == --* ]]; do
    case "$1" in
        --no-sudo)          MODE="nosudo"; shift ;;
        --proxy-to-ubuntu)  MODE="proxy";  shift ;;
        -h|--help)          usage 0 ;;
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

# === Mode proxy : prérequis (groupe + wrapper + sudoers), idempotent ===
ensure_proxy_infrastructure() {
    if ! getent group "$PROXY_GROUP" >/dev/null; then
        groupadd "$PROXY_GROUP"
        log_info "Groupe '$PROXY_GROUP' créé."
    fi

    if [ ! -f "$PROXY_SCRIPT" ]; then
        cat > "$PROXY_SCRIPT" <<'WRAPPER'
#!/usr/bin/env bash
# ssh-proxy-to-ubuntu — déclenché par command="..." dans authorized_keys
# pour les devs en mode proxy. Bascule la session SSH vers l'user ubuntu via
# sudo, sans exiger d'action côté client.
#
# Couvre :
#   - shell interactif (SSH_ORIGINAL_COMMAND vide)  → sudo -u ubuntu -i
#   - commande distante (ssh user@host 'cmd')        → sudo -u ubuntu -- bash -lc cmd
#   - SFTP                                            → sudo -u ubuntu /usr/lib/openssh/sftp-server
#
# SCP utilise SSH_ORIGINAL_COMMAND="scp …" et passe par la branche bash -lc.
set -u
if [ -z "${SSH_ORIGINAL_COMMAND:-}" ]; then
    exec sudo -u ubuntu -i
elif [[ "$SSH_ORIGINAL_COMMAND" == *sftp-server* ]]; then
    exec sudo -u ubuntu /usr/lib/openssh/sftp-server
else
    exec sudo -u ubuntu -- /bin/bash -lc "$SSH_ORIGINAL_COMMAND"
fi
WRAPPER
        chmod 755 "$PROXY_SCRIPT"
        log_info "Wrapper $PROXY_SCRIPT installé."
    fi

    if [ ! -f "$PROXY_SUDOERS" ]; then
        cat > "$PROXY_SUDOERS" <<EOF
# Permet aux membres du groupe ${PROXY_GROUP} d'exécuter des commandes
# en tant qu'ubuntu sans mot de passe (mode SSH proxy-to-ubuntu).
%${PROXY_GROUP} ALL=(ubuntu) NOPASSWD: ALL
EOF
        chmod 440 "$PROXY_SUDOERS"
        if ! visudo -cf "$PROXY_SUDOERS" >/dev/null; then
            rm -f "$PROXY_SUDOERS"
            die "Sudoers fragment invalide — abort."
        fi
        log_info "Sudoers fragment $PROXY_SUDOERS posé."
    fi
}

# Création du user si absent
if id "$USERNAME" >/dev/null 2>&1; then
    log_info "User '$USERNAME' existe déjà — skip création."
else
    log_info "Création du user '$USERNAME' (shell bash, sans mot de passe)…"
    case "$MODE" in
        sudoer) useradd -m -s /bin/bash -G sudo "$USERNAME" ;;
        nosudo|proxy) useradd -m -s /bin/bash "$USERNAME" ;;
    esac
    passwd -l "$USERNAME" >/dev/null
fi

# Mode proxy : prérequis + ajout au groupe (toujours, idempotent)
if [ "$MODE" = "proxy" ]; then
    ensure_proxy_infrastructure
    if id -nG "$USERNAME" | grep -qw "$PROXY_GROUP"; then
        log_info "'$USERNAME' déjà dans le groupe $PROXY_GROUP — skip."
    else
        usermod -aG "$PROXY_GROUP" "$USERNAME"
        log_ok "'$USERNAME' ajouté au groupe $PROXY_GROUP."
    fi
fi

case "$MODE" in
    sudoer) log_ok "User '$USERNAME' prêt (sudoer indépendant)." ;;
    nosudo) log_ok "User '$USERNAME' prêt (sans sudo)." ;;
    proxy)  log_ok "User '$USERNAME' prêt (proxy-to-ubuntu : ssh = shell ubuntu)." ;;
esac

# Pose de la clé publique (idempotent)
SSH_DIR="/home/$USERNAME/.ssh"
AUTH_KEYS="$SSH_DIR/authorized_keys"
install -d -m 700 -o "$USERNAME" -g "$USERNAME" "$SSH_DIR"

# En mode proxy : préfixe la clé pour forcer le wrapper.
# `restrict` désactive port/X11/agent forwarding (defense in depth) — pty est
# implicitement disponible via le shell exec.
if [ "$MODE" = "proxy" ]; then
    KEYLINE="restrict,command=\"$PROXY_SCRIPT\",pty $PUBKEY"
else
    KEYLINE="$PUBKEY"
fi

if [ -f "$AUTH_KEYS" ] && grep -qF "$PUBKEY" "$AUTH_KEYS"; then
    log_info "Clé déjà présente dans $AUTH_KEYS — skip."
else
    printf '%s\n' "$KEYLINE" >> "$AUTH_KEYS"
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
if [ "$MODE" = "proxy" ]; then
    echo "  → la session SSH atterrit DIRECTEMENT dans le shell d'ubuntu."
    echo "  → le dev peut faire 'cd /var/www/SLUG/staging && git pull' sans sudo."
fi
