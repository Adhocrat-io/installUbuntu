#!/usr/bin/env bash
# 21-clone-deploy-scripts — installe les scripts /usr/local/bin/{dispatch,deploy-{prod,staging}}.sh

require_var SLUG PROD_BRANCH STAGING_BRANCH

# dispatch-deploy.sh : lit $1 (ref reçu de webhook) et appelle le bon deploy.
render_template "${SCRIPT_DIR}/templates/dispatch-deploy.sh.tpl" /usr/local/bin/dispatch-deploy.sh
chmod 755 /usr/local/bin/dispatch-deploy.sh

# deploy-production.sh
ENV=production BRANCH="$PROD_BRANCH" \
SITE_DIR="/var/www/${SLUG}/production" \
    render_template "${SCRIPT_DIR}/templates/deploy.sh.tpl" /usr/local/bin/deploy-production.sh
chmod 755 /usr/local/bin/deploy-production.sh

# deploy-staging.sh
ENV=staging BRANCH="$STAGING_BRANCH" \
SITE_DIR="/var/www/${SLUG}/staging" \
    render_template "${SCRIPT_DIR}/templates/deploy.sh.tpl" /usr/local/bin/deploy-staging.sh
chmod 755 /usr/local/bin/deploy-staging.sh

# Log central des déploiements (writable par ubuntu, lisible adm)
touch /var/log/deploy.log
chown ubuntu:adm /var/log/deploy.log
chmod 640 /var/log/deploy.log

log_ok "Scripts de déploiement installés (/usr/local/bin/dispatch-deploy.sh + deploy-{production,staging}.sh)."
