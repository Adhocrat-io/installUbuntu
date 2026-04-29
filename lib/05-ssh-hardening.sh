#!/usr/bin/env bash
# 05-ssh-hardening — SSH key-only sur port 2222, AllowUsers ubuntu, algos modernes
#
# IMPORTANT : la session SSH courante reste ouverte jusqu'au reload.
# On vérifie sshd -t avant de reloader, et on n'éjecte pas l'utilisateur.

require_var FQDN

# Sanity : la clé doit être autorisée pour ubuntu (vérifié en preflight, on revérifie)
if [ ! -s /home/ubuntu/.ssh/authorized_keys ]; then
    die "/home/ubuntu/.ssh/authorized_keys vide — abort hardening SSH."
fi
chmod 700 /home/ubuntu/.ssh
chmod 600 /home/ubuntu/.ssh/authorized_keys
chown -R ubuntu:ubuntu /home/ubuntu/.ssh

# Anti-lockout : si UFW est déjà actif (re-run), s'assurer que 2222 est autorisé AVANT
# le bascul du port. Le module 06 le fera de toute façon, mais en cas de re-run partiel
# on évite d'éjecter la session SSH.
if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
    ufw allow 2222/tcp comment 'SSH (anti-lockout pre-restart)' >/dev/null
fi

# Vérifie qu'openssh-server est bien là (sur certaines images minimales il manque)
if ! command -v sshd >/dev/null 2>&1; then
    log_warn "openssh-server absent — installation."
    apt-get install -y -qq openssh-server
fi

# Drop-in conf — on ne touche pas /etc/ssh/sshd_config principal
mkdir -p /etc/ssh/sshd_config.d
install -m 0644 "${SCRIPT_DIR}/templates/sshd-hardening.conf" \
    /etc/ssh/sshd_config.d/00-hardening.conf

# /run/sshd : créé d'habitude au boot par systemd-tmpfiles, mais peut manquer juste après
# l'install d'openssh-server avant le premier start.
[ -d /run/sshd ] || install -d -m 0755 /run/sshd

# Validation avant reload — si KO, on retire la conf pour ne pas casser SSH
if ! sshd -t 2>/tmp/sshd-test.err; then
    log_err "sshd -t a échoué :"
    cat /tmp/sshd-test.err >&2
    rm -f /etc/ssh/sshd_config.d/00-hardening.conf
    die "Conf SSH invalide — rollback effectué."
fi

# Sur Ubuntu 24.04+, le service est socket-activé : ssh.socket pilote le port.
# On override le ListenStream du socket via drop-in.
mkdir -p /etc/systemd/system/ssh.socket.d
cat > /etc/systemd/system/ssh.socket.d/listen.conf <<'EOF'
[Socket]
ListenStream=
ListenStream=0.0.0.0:2222
ListenStream=[::]:2222
BindIPv6Only=ipv6-only
EOF

systemctl daemon-reload
systemctl restart ssh.socket 2>/dev/null || systemctl restart ssh

# La socket est déjà sur 2222 mais sshd doit lire la nouvelle conf
systemctl reload ssh 2>/dev/null || systemctl restart ssh

log_warn "SSH écoute désormais sur 2222 UNIQUEMENT."
log_warn "Ne ferme pas ta session courante avant d'avoir testé : ssh -p 2222 ubuntu@${FQDN}"
