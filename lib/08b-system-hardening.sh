#!/usr/bin/env bash
# 08b-system-hardening — durcissements système complémentaires (Lynis)
#
# - Blacklist des protocoles réseau inhabituels (dccp/sctp/rds/tipc) + usb-storage
# - Core dumps désactivés pour tous les utilisateurs
# - login.defs : UMASK 027, SHA512 500k rounds
#   (PAS d'expiration de mot de passe — choix volontaire)
# - PAM pwquality : exigences minimales de qualité
# - auditd : activé et démarré
# - /etc/issue + /etc/issue.net : bannière légale

# === 1. Blacklist modules ===
install -m 0644 "${SCRIPT_DIR}/templates/modprobe-blacklist.conf" \
    /etc/modprobe.d/99-hardening.conf

# === 2. Core dumps off ===
install -m 0644 "${SCRIPT_DIR}/templates/limits-hardening.conf" \
    /etc/security/limits.d/99-hardening.conf

# Drop-in systemd pour les services systemd (limits.conf ne s'applique qu'aux sessions PAM)
mkdir -p /etc/systemd/coredump.conf.d
cat > /etc/systemd/coredump.conf.d/disable.conf <<'EOF'
[Coredump]
Storage=none
ProcessSizeMax=0
EOF
systemctl daemon-reload

# === 3. login.defs ===
# UMASK 027 (au lieu de 022)
if grep -qE '^\s*UMASK\s+' /etc/login.defs; then
    sed -i 's/^\s*UMASK\s\+.*/UMASK           027/' /etc/login.defs
else
    echo 'UMASK           027' >> /etc/login.defs
fi

# Hashage des mots de passe : SHA512 + 500k rounds
for key in SHA_CRYPT_MIN_ROUNDS SHA_CRYPT_MAX_ROUNDS; do
    if grep -qE "^\s*${key}\s+" /etc/login.defs; then
        sed -i "s/^\s*${key}\s\+.*/${key} 500000/" /etc/login.defs
    else
        echo "${key} 500000" >> /etc/login.defs
    fi
done

# Note volontaire : on ne configure PAS PASS_MAX_DAYS / PASS_MIN_DAYS.
# Pas d'expiration forcée sur ce serveur (choix opérateur).

# === 4. PAM pwquality ===
# Exigences minimales si jamais un mot de passe est défini un jour.
if [ -f /etc/security/pwquality.conf ]; then
    sed -i 's/^# *minlen *=.*/minlen = 12/' /etc/security/pwquality.conf
    sed -i 's/^# *dcredit *=.*/dcredit = -1/' /etc/security/pwquality.conf
    sed -i 's/^# *ucredit *=.*/ucredit = -1/' /etc/security/pwquality.conf
    sed -i 's/^# *lcredit *=.*/lcredit = -1/' /etc/security/pwquality.conf
    sed -i 's/^# *ocredit *=.*/ocredit = -1/' /etc/security/pwquality.conf
    sed -i 's/^# *retry *=.*/retry = 3/' /etc/security/pwquality.conf
fi

# === 5. auditd ===
# Le paquet est installé par 04-packages, on s'assure qu'il tourne.
if systemctl list-unit-files auditd.service >/dev/null 2>&1; then
    systemctl enable --now auditd >/dev/null 2>&1 || true
fi

# === 6. Bannière légale ===
install -m 0644 "${SCRIPT_DIR}/templates/issue-banner" /etc/issue
install -m 0644 "${SCRIPT_DIR}/templates/issue-banner" /etc/issue.net

# === 7. Purge anciens paquets résiduels ===
# Cleanup des configs orphelines (Lynis PKGS-7346) — silencieux si rien à faire.
dpkg -l | awk '/^rc/ {print $2}' | xargs -r apt-get purge -y -qq >/dev/null 2>&1 || true

log_ok "Durcissement système complémentaire appliqué (Lynis : NETW-3200, KRNL-5820, AUTH-9230, AUTH-9262, AUTH-9328, ACCT-9628, BANN-7126, PKGS-7346)."
