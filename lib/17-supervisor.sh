#!/usr/bin/env bash
# 17-supervisor — supervisor pour les queue workers Laravel
# (configurations applicatives à ajouter manuellement par site dans /etc/supervisor/conf.d/)

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

log_ok "Supervisor installé (configs applicatives à ajouter dans /etc/supervisor/conf.d/)."
