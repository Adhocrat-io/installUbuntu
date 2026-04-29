#!/usr/bin/env bash
# 10-unattended-upgrades — patches sécurité auto

require_var ALERT_EMAIL

apt-get install -y -qq unattended-upgrades apt-listchanges

# Active les updates automatiques (security + recommandés)
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Download-Upgradeable-Packages "1";
EOF

# Configuration : security uniquement, mail à l'utilisateur ubuntu, redémarrage auto à 4h
cat > /etc/apt/apt.conf.d/50unattended-upgrades <<EOF
Unattended-Upgrade::Allowed-Origins {
    "\${distro_id}:\${distro_codename}";
    "\${distro_id}:\${distro_codename}-security";
    "\${distro_id}ESMApps:\${distro_codename}-apps-security";
    "\${distro_id}ESM:\${distro_codename}-infra-security";
};

Unattended-Upgrade::Package-Blacklist {};
Unattended-Upgrade::DevRelease "auto";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-WithUsers "false";
Unattended-Upgrade::Automatic-Reboot-Time "04:00";
Unattended-Upgrade::Mail "${ALERT_EMAIL}";
Unattended-Upgrade::MailReport "on-change";
EOF

systemctl enable --now unattended-upgrades

log_ok "unattended-upgrades configuré (sécurité auto, reboot 04:00 si nécessaire)."
