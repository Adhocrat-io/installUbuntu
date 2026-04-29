#!/usr/bin/env bash
# 07-crowdsec — IDS comportemental + bouncer firewall

# Repo officiel CrowdSec
if [ ! -f /etc/apt/sources.list.d/crowdsec_crowdsec.list ]; then
    curl -fsSL https://install.crowdsec.net | bash
fi

apt-get update -qq
apt-get install -y -qq crowdsec crowdsec-firewall-bouncer-iptables

# Collections de scénarios
cscli collections install \
    crowdsecurity/linux \
    crowdsecurity/sshd \
    crowdsecurity/base-http-scenarios \
    crowdsecurity/http-cve \
    crowdsecurity/whitelist-good-actors >/dev/null 2>&1 || true

# Acquisition logs SSH (par défaut OK sur Ubuntu) + Caddy plus tard
cscli parsers install crowdsecurity/whitelists >/dev/null 2>&1 || true

systemctl enable --now crowdsec
systemctl enable --now crowdsec-firewall-bouncer

cscli hub update >/dev/null 2>&1 || true
cscli hub upgrade >/dev/null 2>&1 || true

systemctl reload crowdsec || systemctl restart crowdsec

log_ok "CrowdSec actif (collections sshd + http + linux)."
