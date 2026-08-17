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
#
# Chaque environnement (production, et staging s'il est activé) a son propre
# worker et son propre ordonnanceur : leurs files Redis sont isolées par préfixe
# (APP_NAME différent), il faut donc bien un consommateur par environnement.

require_var SLUG

# Installe le worker de queue + le cron d'ordonnancement pour un environnement.
#   $1 = env (production | staging)
# Production conserve les noms historiques (programme/log/cron sans suffixe) pour
# rester rétrocompatible ; les autres environnements sont suffixés.
install_env_queue_worker() {
    local env="$1"
    local app_dir="/var/www/${SLUG}/${env}${APP_SUBDIR:+/${APP_SUBDIR}}"

    local program="${SLUG}-queue"
    local queue_log="/var/log/queue-worker.log"
    local cron_file="/etc/cron.d/laravel-schedule"
    if [ "$env" != "production" ]; then
        program="${SLUG}-queue-${env}"
        queue_log="/var/log/queue-worker-${env}.log"
        cron_file="/etc/cron.d/laravel-schedule-${env}"
    fi

    if [ ! -f "${app_dir}/artisan" ]; then
        log_warn "${app_dir}/artisan introuvable — worker de queue et ordonnanceur (${env}) non installés."
        log_warn "Relance ce module après le premier déploiement : rm ${STATE_DIR}/.24b-queue-worker.done"
        return 0
    fi

    # === Worker de queue =================================================
    # --max-time : le worker se recycle chaque heure (mémoire, et reprise du
    # code même si un déploiement oublie `queue:restart`).
    cat > "/etc/supervisor/conf.d/${program}.conf" <<EOF
; Worker de queue Laravel (${env}) — généré par installUbuntu (module 24b).
[program:${program}]
process_name=%(program_name)s_%(process_num)02d
command=/usr/bin/php ${app_dir}/artisan queue:work --sleep=3 --tries=3 --backoff=10 --max-time=3600
directory=${app_dir}
autostart=true
autorestart=true
stopasgroup=true
killasgroup=true
user=ubuntu
numprocs=1
redirect_stderr=true
stdout_logfile=${queue_log}
stopwaitsecs=3600
EOF
    # 0644 explicite : UMASK 027 (module 08b) créerait un fichier que supervisor,
    # qui lit ses configs en root, accepte — mais qu'aucun humain non-root ne peut
    # relire. On reste sur des permissions de config classiques.
    chmod 0644 "/etc/supervisor/conf.d/${program}.conf"

    install -m 0640 -o ubuntu -g adm /dev/null "$queue_log"

    supervisorctl reread >/dev/null 2>&1 || true
    supervisorctl update >/dev/null 2>&1 || true

    # === Ordonnanceur ====================================================
    cat > "$cron_file" <<EOF
# Ordonnanceur Laravel (${env}) — généré par installUbuntu (module 24b).
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
* * * * * ubuntu cd ${app_dir} && /usr/bin/php artisan schedule:run >> /dev/null 2>&1
EOF
    chmod 0644 "$cron_file"

    # === Vérification ====================================================
    sleep 2
    if supervisorctl status "${program}:${program}_00" 2>/dev/null | grep -q RUNNING; then
        log_ok "Worker de queue actif (${program}) + ordonnanceur cron installé (${env})."
    else
        log_warn "Le worker de queue (${env}) n'est pas encore RUNNING — vérifie : sudo supervisorctl status"
        log_warn "et le log applicatif : ${queue_log}"
    fi
}

install_env_queue_worker production

if staging_enabled; then
    install_env_queue_worker staging
fi
