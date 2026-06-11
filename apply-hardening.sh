#!/usr/bin/env bash
# apply-hardening.sh — applique les durcissements Lynis sur un VPS déjà provisionné.
#
# Idempotent : peut être ré-exécuté sans risque.
# À lancer en root (sudo bash apply-hardening.sh).
#
# Couvre :
#   - sysctl additions (KRNL-6000)
#   - blacklist protocoles inhabituels (NETW-3200)
#   - core dumps off (KRNL-5820)
#   - login.defs : UMASK 027, SHA512 500k rounds (pas d'expiration)
#   - PAM pwquality (AUTH-9262)
#   - auditd (ACCT-9628)
#   - banner SMTP Postfix (MAIL-8818)
#   - bannière légale /etc/issue (BANN-7126/7130)
#   - paquets manquants (libpam-tmpdir, debsums, needrestart, apt-show-versions)
#   - purge des paquets résiduels (PKGS-7346)

set -euo pipefail

if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo "Ce script doit être lancé en root (sudo bash apply-hardening.sh)." >&2
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1

log() { printf '\033[1;34m[%s]\033[0m %s\n' "$(date +%H:%M:%S)" "$*"; }
ok()  { printf '\033[1;32m[%s] ✔\033[0m %s\n' "$(date +%H:%M:%S)" "$*"; }

# === 1. Paquets manquants =================================================
log "Installation des paquets manquants…"
apt-get update -qq
apt-get install -y -qq \
    libpam-tmpdir \
    libpam-pwquality \
    debsums \
    apt-show-versions \
    needrestart \
    auditd \
    audispd-plugins

# === 2. Sysctl additions ==================================================
log "Mise à jour des sysctl (kernel hardening)…"
# Renommer l'ancien fichier 99-hardening.conf en zz- pour qu'il gagne contre
# /usr/lib/sysctl.d/99-protect-links.conf (ordre alphabétique, p > h).
if [ -f /etc/sysctl.d/99-hardening.conf ] && [ ! -f /etc/sysctl.d/zz-hardening.conf ]; then
    mv /etc/sysctl.d/99-hardening.conf /etc/sysctl.d/zz-hardening.conf
fi

cat > /etc/sysctl.d/zz-hardening-extra.conf <<'EOF'
# Additions Lynis — appliquées par apply-hardening.sh

# Empêcher le chargement automatique des line disciplines TTY
dev.tty.ldisc_autoload = 0

# Empêcher les binaires SUID de générer des core dumps
fs.suid_dumpable = 0

# Inclure le PID dans le nom des core dumps (si jamais activés)
kernel.core_uses_pid = 1

# Restreindre l'accès non-privilégié à perf_event_open()
kernel.perf_event_paranoid = 3
EOF

# Service oneshot : re-applique sysctl APRÈS que les interfaces réseau soient up.
# Sinon net.ipv4.conf.all.log_martians est reset au boot par networkd.
cat > /etc/systemd/system/sysctl-late.service <<'EOF'
[Unit]
Description=Re-apply sysctl after network is online
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/sysctl --system
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable sysctl-late.service >/dev/null 2>&1 || true

sysctl --system >/dev/null

# === 3. Blacklist modprobe ================================================
log "Blacklist des protocoles inhabituels et modules sensibles…"
cat > /etc/modprobe.d/99-hardening.conf <<'EOF'
# Blacklist protocoles réseau inhabituels (Lynis NETW-3200)
install dccp /bin/true
install sctp /bin/true
install rds /bin/true
install tipc /bin/true

# Stockage USB (VPS sans port USB) (Lynis USB-1000)
install usb-storage /bin/true

# Filesystems exotiques
install cramfs /bin/true
install freevxfs /bin/true
install jffs2 /bin/true
install hfs /bin/true
install hfsplus /bin/true
install udf /bin/true
EOF

# === 4. Core dumps off ====================================================
log "Désactivation des core dumps…"
cat > /etc/security/limits.d/99-hardening.conf <<'EOF'
*               hard    core            0
*               soft    core            0
root            hard    core            0
root            soft    core            0
EOF

mkdir -p /etc/systemd/coredump.conf.d
cat > /etc/systemd/coredump.conf.d/disable.conf <<'EOF'
[Coredump]
Storage=none
ProcessSizeMax=0
EOF
systemctl daemon-reload

# === 5. login.defs ========================================================
log "Mise à jour de /etc/login.defs (UMASK, SHA rounds, sans expiration)…"

# UMASK 027
if grep -qE '^\s*UMASK\s+' /etc/login.defs; then
    sed -i 's/^\s*UMASK\s\+.*/UMASK           027/' /etc/login.defs
else
    echo 'UMASK           027' >> /etc/login.defs
fi

# SHA512 500k rounds
for key in SHA_CRYPT_MIN_ROUNDS SHA_CRYPT_MAX_ROUNDS; do
    if grep -qE "^\s*${key}\s+" /etc/login.defs; then
        sed -i "s/^\s*${key}\s\+.*/${key} 500000/" /etc/login.defs
    else
        echo "${key} 500000" >> /etc/login.defs
    fi
done

# NOTE : on ne touche PAS à PASS_MAX_DAYS / PASS_MIN_DAYS.
# Choix volontaire : pas d'expiration de mot de passe sur ce serveur.

# === 6. PAM pwquality =====================================================
if [ -f /etc/security/pwquality.conf ]; then
    log "Configuration PAM pwquality…"
    sed -i 's/^# *minlen *=.*/minlen = 12/' /etc/security/pwquality.conf
    sed -i 's/^# *dcredit *=.*/dcredit = -1/' /etc/security/pwquality.conf
    sed -i 's/^# *ucredit *=.*/ucredit = -1/' /etc/security/pwquality.conf
    sed -i 's/^# *lcredit *=.*/lcredit = -1/' /etc/security/pwquality.conf
    sed -i 's/^# *ocredit *=.*/ocredit = -1/' /etc/security/pwquality.conf
    sed -i 's/^# *retry *=.*/retry = 3/' /etc/security/pwquality.conf
fi

# === 7. auditd ============================================================
log "Activation d'auditd…"
if systemctl list-unit-files auditd.service >/dev/null 2>&1; then
    systemctl enable --now auditd >/dev/null 2>&1 || true
fi

# === 7b. Désactivation d'apport ==========================================
# Le crash reporter Ubuntu force fs.suid_dumpable=2 au boot, ce qui casse
# notre durcissement sysctl. Inutile sur un serveur prod.
log "Désactivation d'apport (force suid_dumpable=2 au boot)…"
if systemctl list-unit-files apport.service >/dev/null 2>&1; then
    systemctl disable --now apport.service >/dev/null 2>&1 || true
fi

# === 8. Postfix banner ====================================================
if command -v postconf >/dev/null 2>&1; then
    log "Mise à jour du banner Postfix…"
    postconf -e 'smtpd_banner = $myhostname ESMTP' >/dev/null
    systemctl reload postfix 2>/dev/null || true
fi

# === 9. Bannière légale ===================================================
log "Installation de la bannière légale /etc/issue…"
cat > /etc/issue <<'EOF'
**********************************************************************
*  WARNING: Unauthorized access prohibited.                          *
*  All activity is monitored, logged and may be prosecuted.          *
*  Acces non autorise interdit ; toute activite est journalisee.     *
**********************************************************************
EOF
cp /etc/issue /etc/issue.net
chmod 0644 /etc/issue /etc/issue.net

# === 10. Purge paquets résiduels ==========================================
log "Purge des paquets résiduels (configs orphelines)…"
RESIDUAL="$(dpkg -l | awk '/^rc/ {print $2}')"
if [ -n "$RESIDUAL" ]; then
    # shellcheck disable=SC2086
    apt-get purge -y -qq $RESIDUAL >/dev/null 2>&1 || true
fi

# === 11. Récap ============================================================
ok "Durcissement appliqué."
echo
echo "Vérifications manuelles recommandées :"
echo "  - sysctl dev.tty.ldisc_autoload fs.suid_dumpable kernel.perf_event_paranoid"
echo "  - postconf smtpd_banner"
echo "  - systemctl is-active auditd"
echo "  - grep UMASK /etc/login.defs"
echo
echo "Les blacklists modprobe et limits.conf prennent effet au prochain reboot"
echo "(les modules concernés ne sont pas chargés là maintenant — vérifier avec lsmod)."
