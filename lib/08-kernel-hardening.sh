#!/usr/bin/env bash
# 08-kernel-hardening — sysctl

install -m 0644 "${SCRIPT_DIR}/templates/sysctl-hardening.conf" \
    /etc/sysctl.d/99-hardening.conf

sysctl --system >/dev/null

log_ok "Kernel hardening (sysctl) appliqué."
