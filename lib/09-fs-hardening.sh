#!/usr/bin/env bash
# 09-fs-hardening — /tmp et /dev/shm en noexec,nosuid,nodev
#
# /tmp : monté en tmpfs via systemd (drop-in tmp.mount).
# /dev/shm : remount avec options durcies.

# /tmp en tmpfs durci
mkdir -p /etc/systemd/system/tmp.mount.d
cat > /etc/systemd/system/tmp.mount.d/hardening.conf <<'EOF'
[Mount]
Options=mode=1777,strictatime,nosuid,nodev,noexec,size=50%,nr_inodes=1m
EOF

# Activer tmp.mount (le rendre persistant)
systemctl daemon-reload
systemctl enable tmp.mount 2>/dev/null || true

# /dev/shm hardening via fstab
if ! grep -q '/dev/shm' /etc/fstab; then
    echo 'tmpfs /dev/shm tmpfs defaults,nosuid,nodev,noexec 0 0' >> /etc/fstab
fi
mount -o remount,nosuid,nodev,noexec /dev/shm 2>/dev/null || true

log_ok "/tmp et /dev/shm durcis (noexec,nosuid,nodev). /tmp prendra effet au prochain reboot."
