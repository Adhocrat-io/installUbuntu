#!/usr/bin/env bash
# 26-logrotate — rotation des logs Laravel et FrankenPHP

require_var SLUG

LARAVEL_LOG_PATHS="/var/www/${SLUG}/production/storage/logs/*.log"
if staging_enabled; then
    LARAVEL_LOG_PATHS="${LARAVEL_LOG_PATHS}
/var/www/${SLUG}/staging/storage/logs/*.log"
fi

cat > /etc/logrotate.d/laravel-${SLUG} <<EOF
${LARAVEL_LOG_PATHS}
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
