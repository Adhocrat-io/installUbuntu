#!/usr/bin/env bash
# 11-mariadb — MariaDB + secure install non-interactive + DBs prod/staging

require_var SLUG

export DEBIAN_FRONTEND=noninteractive
log_info "  → installation MariaDB (server + client)…"
apt-get install -y -qq mariadb-server mariadb-client

log_info "  → démarrage du service…"
systemctl enable --now mariadb

# Bind sur 127.0.0.1 uniquement
cat > /etc/mysql/mariadb.conf.d/99-bind.cnf <<'EOF'
[mysqld]
bind-address = 127.0.0.1
skip-name-resolve
EOF
systemctl restart mariadb

# Génération des secrets
load_secrets
DB_ROOT_PWD="${DB_ROOT_PWD:-$(gen_password)}"
DB_PROD_PWD="${DB_PROD_PWD:-$(gen_password)}"
DB_STAGING_PWD="${DB_STAGING_PWD:-$(gen_password)}"

record_secret DB_ROOT_PWD    "$DB_ROOT_PWD"
record_secret DB_PROD_PWD    "$DB_PROD_PWD"
record_secret DB_STAGING_PWD "$DB_STAGING_PWD"

DB_NAME_PROD="${SLUG//-/_}_production"
DB_NAME_STAGING="${SLUG//-/_}_staging"
DB_USER_PROD="${SLUG//-/_}_prod"
DB_USER_STAGING="${SLUG//-/_}_staging"

record_secret DB_NAME_PROD    "$DB_NAME_PROD"
record_secret DB_NAME_STAGING "$DB_NAME_STAGING"
record_secret DB_USER_PROD    "$DB_USER_PROD"
record_secret DB_USER_STAGING "$DB_USER_STAGING"

# secure_installation équivalent + création DBs/users — via socket (root unix_socket plugin).
# Syntaxe `IDENTIFIED VIA … USING PASSWORD()` documentée pour ALTER USER de MariaDB 10.4+ jusqu'à 11.x
# (c'est une grammaire de parser, pas la fonction PASSWORD() supprimée en 11.x).
mariadb <<SQL
-- Double auth root : socket pour root local, mot de passe pour scripts/admin via TCP
ALTER USER 'root'@'localhost' IDENTIFIED VIA unix_socket OR mysql_native_password USING PASSWORD('${DB_ROOT_PWD}');

DELETE FROM mysql.global_priv WHERE User='';
DELETE FROM mysql.global_priv WHERE User='root' AND Host NOT IN ('localhost','127.0.0.1','::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db IN ('test','test\\_%');

-- Bases applicatives
CREATE DATABASE IF NOT EXISTS \`${DB_NAME_PROD}\`    CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS \`${DB_NAME_STAGING}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Users pour socket (localhost) ET TCP (127.0.0.1) : MariaDB ne fait pas le mapping
-- automatique avec skip-name-resolve. Laravel + Octane se connectent en TCP sur 127.0.0.1.
CREATE USER IF NOT EXISTS '${DB_USER_PROD}'@'localhost'    IDENTIFIED BY '${DB_PROD_PWD}';
CREATE USER IF NOT EXISTS '${DB_USER_STAGING}'@'localhost' IDENTIFIED BY '${DB_STAGING_PWD}';
CREATE USER IF NOT EXISTS '${DB_USER_PROD}'@'127.0.0.1'    IDENTIFIED BY '${DB_PROD_PWD}';
CREATE USER IF NOT EXISTS '${DB_USER_STAGING}'@'127.0.0.1' IDENTIFIED BY '${DB_STAGING_PWD}';

ALTER USER '${DB_USER_PROD}'@'localhost'    IDENTIFIED BY '${DB_PROD_PWD}';
ALTER USER '${DB_USER_STAGING}'@'localhost' IDENTIFIED BY '${DB_STAGING_PWD}';
ALTER USER '${DB_USER_PROD}'@'127.0.0.1'    IDENTIFIED BY '${DB_PROD_PWD}';
ALTER USER '${DB_USER_STAGING}'@'127.0.0.1' IDENTIFIED BY '${DB_STAGING_PWD}';

GRANT ALL PRIVILEGES ON \`${DB_NAME_PROD}\`.*    TO '${DB_USER_PROD}'@'localhost';
GRANT ALL PRIVILEGES ON \`${DB_NAME_STAGING}\`.* TO '${DB_USER_STAGING}'@'localhost';
GRANT ALL PRIVILEGES ON \`${DB_NAME_PROD}\`.*    TO '${DB_USER_PROD}'@'127.0.0.1';
GRANT ALL PRIVILEGES ON \`${DB_NAME_STAGING}\`.* TO '${DB_USER_STAGING}'@'127.0.0.1';

FLUSH PRIVILEGES;
SQL

# .my.cnf root pour les scripts maintenance (chmod 600)
cat > /root/.my.cnf <<EOF
[client]
user=root
password=${DB_ROOT_PWD}
EOF
chmod 600 /root/.my.cnf

log_ok "MariaDB installée. DBs : ${DB_NAME_PROD}, ${DB_NAME_STAGING} (bind 127.0.0.1)."
