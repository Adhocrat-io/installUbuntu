#!/usr/bin/env bash
# 21-clone-deploy-scripts — installe les scripts /usr/local/bin/{dispatch,deploy-{prod,staging}}.sh

require_var SLUG PROD_BRANCH
if staging_enabled; then
    require_var STAGING_BRANCH
fi
# APP_SUBDIR peut être vide (app à la racine) — pas de require_var.
: "${APP_SUBDIR:=}"
export APP_SUBDIR

# dispatch-deploy.sh : lit $1 (ref reçu de webhook) et appelle le bon deploy.
render_template "${SCRIPT_DIR}/templates/dispatch-deploy.sh.tpl" /usr/local/bin/dispatch-deploy.sh

# Sans staging : STAGING_BRANCH est vide, le case rendu vaut « refs/heads/) » et
# pointerait sur un deploy-staging.sh inexistant. On supprime la branche entière
# du case (de son motif jusqu'au « ;; » qui la termine).
if ! staging_enabled; then
    sed -i '\|^ *refs/heads/)$|,\|^ *;;$|d' /usr/local/bin/dispatch-deploy.sh
fi

chmod 755 /usr/local/bin/dispatch-deploy.sh

# deploy-production.sh
ENV=production BRANCH="$PROD_BRANCH" \
SITE_DIR="/var/www/${SLUG}/production" \
    render_template "${SCRIPT_DIR}/templates/deploy.sh.tpl" /usr/local/bin/deploy-production.sh
chmod 755 /usr/local/bin/deploy-production.sh

# deploy-staging.sh
if staging_enabled; then
    ENV=staging BRANCH="$STAGING_BRANCH" \
    SITE_DIR="/var/www/${SLUG}/staging" \
        render_template "${SCRIPT_DIR}/templates/deploy.sh.tpl" /usr/local/bin/deploy-staging.sh
    chmod 755 /usr/local/bin/deploy-staging.sh
fi

# Log central des déploiements (writable par ubuntu, lisible adm)
touch /var/log/deploy.log
chown ubuntu:adm /var/log/deploy.log
chmod 640 /var/log/deploy.log

if staging_enabled; then
    log_ok "Scripts de déploiement installés (/usr/local/bin/dispatch-deploy.sh + deploy-{production,staging}.sh)."
else
    log_ok "Scripts de déploiement installés (/usr/local/bin/dispatch-deploy.sh + deploy-production.sh)."
fi
