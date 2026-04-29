#!/usr/bin/env bash
# 19-www-tree — création de l'arborescence /var/www/{slug}/{production,staging}
# avec permissions ubuntu:www-data + setgid + ACL par défaut.
# Les dossiers sont vides ici ; le clone Git arrive au module 22.

require_var SLUG

# www-data doit exister (paquet apache2/nginx peut l'avoir créé sinon on le force)
getent group www-data >/dev/null || groupadd --system www-data
id -u www-data >/dev/null 2>&1 || useradd --system --no-create-home --gid www-data --shell /usr/sbin/nologin www-data

usermod -aG www-data ubuntu

WWW_BASE="/var/www/${SLUG}"
mkdir -p "${WWW_BASE}/production" "${WWW_BASE}/staging"

# Owner ubuntu:www-data, setgid pour héritage du groupe
chown -R ubuntu:www-data /var/www
chmod 2755 /var/www
chmod 2755 "$WWW_BASE"
chmod 2755 "${WWW_BASE}/production" "${WWW_BASE}/staging"

# ACL par défaut : tous les futurs fichiers seront ubuntu:www-data avec g+rwx
setfacl -R -m u:ubuntu:rwx -m g:www-data:rx "$WWW_BASE"
setfacl -R -d -m u:ubuntu:rwx -m g:www-data:rx "$WWW_BASE"

log_ok "Arborescence /var/www/${SLUG}/{production,staging} prête (ubuntu:www-data, ACL set)."
