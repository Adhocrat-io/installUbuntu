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

# === Whitelist admin (ne JAMAIS bannir nos IPs de management) ===========
# Parser custom posé dans s02-enrich : tout évènement venant des IPs listées
# est marqué `whitelisted`, donc aucun scénario ne déclenchera de décision.
# Defense in depth : couvre localhost + RFC1918 + IPs admin du config.env.
WL_DIR=/etc/crowdsec/parsers/s02-enrich
WL_FILE="${WL_DIR}/admin-whitelist.yaml"
mkdir -p "$WL_DIR"

{
    echo "name: local/admin-whitelist"
    echo "description: \"Always-trust IPs admin (jamais bannir)\""
    echo "whitelist:"
    echo "  reason: \"admin / management IP\""
    echo "  ip:"
    echo "    - \"127.0.0.1\""
    echo "    - \"::1\""
    if [ -n "${ADMIN_WHITELIST_IPS:-}" ]; then
        for entry in ${ADMIN_WHITELIST_IPS}; do
            [ -z "$entry" ] && continue
            [[ "$entry" == *"/"* ]] && continue   # CIDR plus bas
            echo "    - \"$entry\""
        done
    fi
    echo "  cidr:"
    echo "    - \"10.0.0.0/8\""
    echo "    - \"172.16.0.0/12\""
    echo "    - \"192.168.0.0/16\""
    if [ -n "${ADMIN_WHITELIST_IPS:-}" ]; then
        for entry in ${ADMIN_WHITELIST_IPS}; do
            [[ "$entry" == *"/"* ]] && echo "    - \"$entry\""
        done
    fi
} > "$WL_FILE"
chmod 644 "$WL_FILE"
log_ok "Whitelist CrowdSec écrite (${WL_FILE})."

systemctl enable --now crowdsec
systemctl enable --now crowdsec-firewall-bouncer

cscli hub update >/dev/null 2>&1 || true
cscli hub upgrade >/dev/null 2>&1 || true

# Purge proactive : si CrowdSec a déjà émis des décisions contre nos IPs
# (par ex. lors d'un re-run, ou pendant la fenêtre entre install et reload),
# on les efface immédiatement.
if [ -n "${ADMIN_WHITELIST_IPS:-}" ]; then
    for entry in ${ADMIN_WHITELIST_IPS}; do
        [ -z "$entry" ] && continue
        cscli decisions delete --ip "$entry" >/dev/null 2>&1 || true
    done
fi

systemctl reload crowdsec || systemctl restart crowdsec

log_ok "CrowdSec actif (collections sshd + http + linux, whitelist admin appliquée)."
