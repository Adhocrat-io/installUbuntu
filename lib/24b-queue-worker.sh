#!/usr/bin/env bash
# 24b-queue-worker — worker de queue Laravel (supervisor) + ordonnanceur (cron).
#
# Placé APRÈS 22-clone-and-bootstrap : le programme supervisor pointe sur
# `artisan`, qui n'existe qu'une fois le dépôt cloné et déployé. L'installer
# plus tôt ferait boucler supervisor sur un binaire absent.
#
# Sans ces deux briques, une app Laravel configurée en QUEUE_CONNECTION=redis
# (ce que fait le module 22) empile ses jobs dans Redis sans jamais les
# exécuter, et aucune tâche planifiée ne tourne — le tout en silence.

require_var SLUG

APP_DIR="/var/www/${SLUG}/production${APP_SUBDIR:+/${APP_SUBDIR}}"

if [ ! -f "${APP_DIR}/artisan" ]; then
    log_warn "${APP_DIR}/artisan introuvable — worker de queue et ordonnanceur non installés."
    log_warn "Relance ce module après le premier déploiement : rm ${STATE_DIR}/.24b-queue-worker.done"
    return 0
fi

# === Worker de queue =====================================================
# --max-time : le worker se recycle chaque heure (mémoire, et reprise du code
# même si un déploiement oublie `queue:restart`).
QUEUE_LOG="/var/log/queue-worker.log"

cat > "/etc/supervisor/conf.d/${SLUG}-queue.conf" <<EOF
; Worker de queue Laravel — généré par installUbuntu (module 24b).
[program:${SLUG}-queue]
process_name=%(program_name)s_%(process_num)02d
command=/usr/bin/php ${APP_DIR}/artisan queue:work --sleep=3 --tries=3 --backoff=10 --max-time=3600
directory=${APP_DIR}
autostart=true
autorestart=true
stopasgroup=true
killasgroup=true
user=ubuntu
numprocs=1
redirect_stderr=true
stdout_logfile=${QUEUE_LOG}
stopwaitsecs=3600
EOF
# 0644 explicite : UMASK 027 (module 08b) créerait un fichier que supervisor,
# qui lit ses configs en root, accepte — mais qu'aucun humain non-root ne peut
# relire. On reste sur des permissions de config classiques.
chmod 0644 "/etc/supervisor/conf.d/${SLUG}-queue.conf"

install -m 0640 -o ubuntu -g adm /dev/null "$QUEUE_LOG"

supervisorctl reread >/dev/null 2>&1 || true
supervisorctl update >/dev/null 2>&1 || true

# === Ordonnanceur ========================================================
cat > /etc/cron.d/laravel-schedule <<EOF
# Ordonnanceur Laravel — généré par installUbuntu (module 24b).
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
* * * * * ubuntu cd ${APP_DIR} && /usr/bin/php artisan schedule:run >> /dev/null 2>&1
EOF
chmod 0644 /etc/cron.d/laravel-schedule

# === Vérification ========================================================
sleep 2
if supervisorctl status "${SLUG}-queue:${SLUG}-queue_00" 2>/dev/null | grep -q RUNNING; then
    log_ok "Worker de queue actif (${SLUG}-queue) + ordonnanceur cron installé."
else
    log_warn "Le worker de queue n'est pas encore RUNNING — vérifie : sudo supervisorctl status"
    log_warn "et le log applicatif : ${QUEUE_LOG}"
fi
