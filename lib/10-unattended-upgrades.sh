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

# Configuration : security uniquement, silencieux si tout va bien (mail
# uniquement en cas d'échec), redémarrage à 04:00 UNIQUEMENT si une mise à
# jour l'exige (présence de /run/reboot-required) — jamais de reboot
# systématique.
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
// WithUsers true : une session SSH oubliée au moment du run quotidien ne
// doit pas annuler silencieusement le reboot (le shutdown planifié diffuse
// des avertissements wall avant l'échéance ; en mode only-on-error, aucun
// mail ne signalerait un reboot ainsi bloqué).
Unattended-Upgrade::Automatic-Reboot-WithUsers "true";
Unattended-Upgrade::Automatic-Reboot-Time "04:00";
Unattended-Upgrade::Mail "${ALERT_EMAIL}";
// only-on-error : pas de rapport pour les mises à jour réussies, un mail
// seulement quand une mise à jour échoue.
Unattended-Upgrade::MailReport "only-on-error";
EOF

systemctl enable --now unattended-upgrades

log_ok "unattended-upgrades configuré (sécurité auto, mail sur erreur seulement, reboot 04:00 si nécessaire)."
