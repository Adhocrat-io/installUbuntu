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

# Ubuntu 24.04 ne fournit que le template /usr/share/systemd/tmp.mount, pas
# de copie active dans /etc/systemd/system/. Sans cette copie, le `enable`
# qui suit echoue silencieusement (Unit tmp.mount could not be found) et le
# drop-in hardening ne s'applique JAMAIS au boot — /tmp reste sur la racine
# sans noexec.
if [ -f /usr/share/systemd/tmp.mount ] && [ ! -f /etc/systemd/system/tmp.mount ]; then
    cp /usr/share/systemd/tmp.mount /etc/systemd/system/tmp.mount
fi

# Activer tmp.mount (le rendre persistant)
systemctl daemon-reload
if ! systemctl enable tmp.mount 2>/dev/null; then
    log_warn "tmp.mount enable a echoue — /tmp ne sera pas durci au reboot."
fi

# /dev/shm hardening via fstab
if ! grep -q '/dev/shm' /etc/fstab; then
    echo 'tmpfs /dev/shm tmpfs defaults,nosuid,nodev,noexec 0 0' >> /etc/fstab
fi
mount -o remount,nosuid,nodev,noexec /dev/shm 2>/dev/null || true

log_ok "/tmp et /dev/shm durcis (noexec,nosuid,nodev). /tmp prendra effet au prochain reboot."
