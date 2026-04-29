#!/usr/bin/env bash
# 20-deploy-key — paire ed25519 pour git pull GitHub, ~/.ssh/config,
# pause utilisateur jusqu'à ce que la clé soit ajoutée à GitHub.

require_var HOSTNAME SLUG

UBUNTU_HOME=/home/ubuntu
SSH_DIR="${UBUNTU_HOME}/.ssh"
KEY_PATH="${SSH_DIR}/deploy_key"

mkdir -p "$SSH_DIR"
chown ubuntu:ubuntu "$SSH_DIR"
chmod 700 "$SSH_DIR"

if [ ! -f "$KEY_PATH" ]; then
    sudo -u ubuntu ssh-keygen -t ed25519 -N "" -C "deploy-${SLUG}@${HOSTNAME}" -f "$KEY_PATH" >/dev/null
fi
chmod 600 "$KEY_PATH"
chmod 644 "${KEY_PATH}.pub"
chown ubuntu:ubuntu "$KEY_PATH" "${KEY_PATH}.pub"

# Append (idempotent) un bloc Host github.com
SSH_CFG="${SSH_DIR}/config"
touch "$SSH_CFG"
chown ubuntu:ubuntu "$SSH_CFG"
chmod 600 "$SSH_CFG"

if ! grep -qE '^Host github\.com$' "$SSH_CFG"; then
    cat >> "$SSH_CFG" <<EOF

Host github.com
    HostName github.com
    User git
    IdentityFile ${KEY_PATH}
    IdentitiesOnly yes
EOF
fi

PUBKEY="$(cat "${KEY_PATH}.pub")"
record_secret SSH_DEPLOY_PUBKEY "$PUBKEY"

cat <<MSG

╔══════════════════════════════════════════════════════════════════╗
║  ACTION REQUISE                                                  ║
╠══════════════════════════════════════════════════════════════════╣
║  Ajoute la deploy key sur GitHub :                               ║
║    Repo → Settings → Deploy keys → Add deploy key                ║
║    Title : ${HOSTNAME}
║    Key   : (la clé publique ci-dessous)                          ║
║    Allow write access : NON                                      ║
╚══════════════════════════════════════════════════════════════════╝

${PUBKEY}

MSG

# Test connexion GitHub avec retry
while true; do
    read -r -p "Clé collée dans GitHub ? Tape 'oui' pour tester la connexion : " answer || true
    [ "$answer" = "oui" ] || continue

    output="$(sudo -u ubuntu ssh -T -o StrictHostKeyChecking=accept-new -o BatchMode=yes git@github.com 2>&1 || true)"
    if printf '%s' "$output" | grep -q "successfully authenticated"; then
        log_ok "Authentification GitHub OK pour la deploy key."
        break
    else
        log_warn "Échec — la clé ne semble pas (encore) acceptée par GitHub."
        log_warn "Sortie SSH : ${output}"
    fi
done
