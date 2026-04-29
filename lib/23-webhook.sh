#!/usr/bin/env bash
# 23-webhook — adnanh/webhook : UN seul hook, dispatch interne par branche.

apt-get install -y -qq webhook

load_secrets
HMAC_SECRET="${HMAC_SECRET:-$(gen_password)}"
record_secret HMAC_SECRET "$HMAC_SECRET"

render_template "${SCRIPT_DIR}/templates/webhook.json.tpl" /etc/webhook.conf.json
# Le fichier contient le HMAC_SECRET — lisible uniquement par le user du service webhook (ubuntu).
chown root:ubuntu /etc/webhook.conf.json
chmod 640 /etc/webhook.conf.json

# Service systemd dédié (le paquet Debian fournit un /lib/systemd/system/webhook.service
# qui pointe sur /etc/webhook.conf — on override pour notre conf JSON).
mkdir -p /etc/systemd/system/webhook.service.d
cat > /etc/systemd/system/webhook.service.d/override.conf <<'EOF'
[Unit]
# Le unit Debian par défaut exige /etc/webhook.conf — nous utilisons /etc/webhook.conf.json
ConditionPathExists=
ConditionPathExists=/etc/webhook.conf.json

[Service]
ExecStart=
ExecStart=/usr/bin/webhook -hooks /etc/webhook.conf.json -ip 127.0.0.1 -port 9000 -verbose
User=ubuntu
Group=ubuntu
EOF

systemctl daemon-reload
systemctl enable --now webhook
systemctl restart webhook

log_ok "Webhook listener actif sur 127.0.0.1:9000 (hook id=gh-deploy)."
