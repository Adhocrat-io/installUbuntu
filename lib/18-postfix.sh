#!/usr/bin/env bash
# 18-postfix — Postfix send-only loopback, alias root → ubuntu
# Plus tard : ajouter un relais SMTP authentifié si besoin d'envoyer hors localhost.

require_var FQDN

export DEBIAN_FRONTEND=noninteractive
debconf-set-selections <<EOF
postfix postfix/main_mailer_type        select  Internet Site
postfix postfix/mailname                string  ${FQDN}
EOF

apt-get install -y -qq postfix mailutils

# Bind loopback uniquement
postconf -e "inet_interfaces = loopback-only"
postconf -e "mydestination = \$myhostname, localhost.\$mydomain, localhost"
postconf -e "myhostname = ${FQDN}"
postconf -e "mynetworks = 127.0.0.0/8 [::1]/128"
postconf -e "smtpd_relay_restrictions = permit_mynetworks reject_unauth_destination"
postconf -e "smtp_tls_security_level = may"

# Alias root → ubuntu
if ! grep -qE '^root:' /etc/aliases; then
    echo "root: ubuntu" >> /etc/aliases
else
    sed -i 's/^root:.*/root: ubuntu/' /etc/aliases
fi
newaliases

systemctl enable --now postfix
systemctl restart postfix

log_ok "Postfix send-only configuré (loopback, alias root→ubuntu)."
