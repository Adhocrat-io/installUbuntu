#!/usr/bin/env bash
# 26-logrotate — rotation des logs Laravel et FrankenPHP

require_var SLUG

cat > /etc/logrotate.d/laravel-${SLUG} <<EOF
/var/www/${SLUG}/production/storage/logs/*.log
/var/www/${SLUG}/staging/storage/logs/*.log
{
    daily
    rotate 14
    missingok
    notifempty
    compress
    delaycompress
    copytruncate
    su ubuntu www-data
}
EOF

cat > /etc/logrotate.d/frankenphp <<'EOF'
/var/log/frankenphp/*.log {
    daily
    rotate 14
    missingok
    notifempty
    compress
    delaycompress
    copytruncate
    su ubuntu ubuntu
    postrotate
        systemctl reload frankenphp >/dev/null 2>&1 || true
    endscript
}
EOF

cat > /etc/logrotate.d/deploy-log <<'EOF'
/var/log/deploy.log {
    weekly
    rotate 8
    missingok
    notifempty
    compress
    delaycompress
    copytruncate
    su ubuntu ubuntu
}
EOF

log_ok "Logrotate configuré (Laravel, FrankenPHP, deploy.log)."
