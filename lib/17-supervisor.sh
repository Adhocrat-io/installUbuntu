#!/usr/bin/env bash
# 17-supervisor — installe supervisor, qui pilotera les workers Laravel.
# Le worker de queue du site est posé par le module 24b, après le bootstrap :
# il a besoin d'un `artisan` existant pour démarrer.

apt-get install -y -qq supervisor

systemctl enable --now supervisor

# Exemple commenté pour Horizon — à activer plus tard par l'utilisateur
cat > /etc/supervisor/conf.d/README.example <<'EOF'
# Exemple de configuration pour Laravel Horizon (à copier en .conf et adapter) :
#
# [program:horizon-production]
# process_name=%(program_name)s
# command=/usr/bin/php /var/www/<slug>/production/artisan horizon
# autostart=true
# autorestart=true
# user=ubuntu
# redirect_stderr=true
# stdout_logfile=/var/log/horizon-production.log
# stopwaitsecs=3600
EOF

log_ok "Supervisor installé. Le worker de queue du site est posé par le module 24b (après le bootstrap)."
