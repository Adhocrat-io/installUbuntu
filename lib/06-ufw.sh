#!/usr/bin/env bash
# 06-ufw — firewall : deny incoming, allow 2222/80/443

ufw --force reset >/dev/null

ufw default deny incoming
ufw default allow outgoing

# SSH (port 2222 après hardening)
ufw allow 2222/tcp comment 'SSH'

# Web
ufw allow 80/tcp  comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'

# Activation
ufw --force enable

log_ok "UFW actif : 2222/tcp, 80/tcp, 443/tcp (deny par défaut)."
