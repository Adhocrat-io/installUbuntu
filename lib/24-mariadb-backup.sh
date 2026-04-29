#!/usr/bin/env bash
# 24-mariadb-backup — dump quotidien + rotation 7j/4w

mkdir -p /var/backups/mariadb
chmod 700 /var/backups/mariadb

cat > /usr/local/bin/backup-mariadb.sh <<'EOF'
#!/usr/bin/env bash
# Dump toutes les bases (sauf system) avec rotation 7 jours + 4 hebdos.
set -euo pipefail

BACKUP_DIR=/var/backups/mariadb
TS="$(date +%Y%m%d-%H%M)"
DOW="$(date +%u)"   # 1..7

mkdir -p "$BACKUP_DIR/daily" "$BACKUP_DIR/weekly"

DUMP_FILE="${BACKUP_DIR}/daily/all-${TS}.sql.gz"

mariadb-dump \
    --defaults-file=/root/.my.cnf \
    --single-transaction \
    --quick \
    --lock-tables=false \
    --routines \
    --triggers \
    --events \
    --all-databases \
    --ignore-database=information_schema \
    --ignore-database=performance_schema \
    --ignore-database=sys \
    --ignore-database=mysql \
    | gzip -9 > "$DUMP_FILE"

chmod 600 "$DUMP_FILE"

# Rotation : garder 7 quotidiens
find "$BACKUP_DIR/daily" -maxdepth 1 -name 'all-*.sql.gz' -mtime +7 -delete

# Tous les dimanches → copie vers weekly, garder 4 semaines
if [ "$DOW" = "7" ]; then
    cp "$DUMP_FILE" "${BACKUP_DIR}/weekly/all-${TS}.sql.gz"
    find "$BACKUP_DIR/weekly" -maxdepth 1 -name 'all-*.sql.gz' -mtime +28 -delete
fi
EOF
chmod 750 /usr/local/bin/backup-mariadb.sh

# Cron quotidien 03:00
cat > /etc/cron.d/mariadb-backup <<'EOF'
# Dump MariaDB quotidien
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
0 3 * * * root /usr/local/bin/backup-mariadb.sh >> /var/log/mariadb-backup.log 2>&1
EOF
chmod 644 /etc/cron.d/mariadb-backup

log_ok "Backup MariaDB : cron 03:00 → /var/backups/mariadb/ (rotation 7j+4w)."
