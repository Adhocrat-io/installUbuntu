#!/usr/bin/env bash
# 08-kernel-hardening — sysctl
#
# Le nom de fichier 'zz-' garantit qu'il est lu APRÈS tous les autres
# (en particulier /usr/lib/sysctl.d/99-protect-links.conf qui surcharge
# fs.protected_fifos sinon).

install -m 0644 "${SCRIPT_DIR}/templates/zz-sysctl-hardening.conf" \
    /etc/sysctl.d/zz-hardening.conf

# Service oneshot : re-applique sysctl APRÈS que les interfaces réseau soient up.
# Sinon net.ipv4.conf.all.* est reset lorsque ens3 vient up après systemd-sysctl.service.
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
systemctl enable sysctl-late.service >/dev/null 2>&1

sysctl --system >/dev/null

log_ok "Kernel hardening (sysctl) appliqué."
