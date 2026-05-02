#!/usr/bin/env bash
# 99-finalize — génère /home/ubuntu/passwords.md (chmod 600), récap minimal en stdout

require_var HOSTNAME FQDN DOMAIN SLUG REPO_URL PROD_BRANCH STAGING_BRANCH

load_secrets

require_var \
    DB_ROOT_PWD DB_PROD_PWD DB_STAGING_PWD \
    DB_NAME_PROD DB_NAME_STAGING DB_USER_PROD DB_USER_STAGING \
    REDIS_PWD HMAC_SECRET SSH_DEPLOY_PUBKEY

PWD_FILE=/home/ubuntu/passwords.md

cat > "$PWD_FILE" <<EOF
# Secrets serveur — ${HOSTNAME} ($(date -I))

> Fichier confidentiel. Sauvegarde-le hors serveur (gestionnaire de mots de passe).
> Permissions : chmod 600, owner ubuntu.

## Comptes système

- User : \`ubuntu\` (sudo, SSH key uniquement)
- SSH  : \`ssh -p 2222 ubuntu@${FQDN}\`
- Port SSH : **2222** (22 fermé par UFW)

## MariaDB

- Bind : 127.0.0.1
- root : \`${DB_ROOT_PWD}\`
- Le fichier \`/root/.my.cnf\` (chmod 600) contient déjà ces creds pour les scripts admin.

### Database production
- Database : \`${DB_NAME_PROD}\`
- User     : \`${DB_USER_PROD}\`
- Password : \`${DB_PROD_PWD}\`

### Database staging
- Database : \`${DB_NAME_STAGING}\`
- User     : \`${DB_USER_STAGING}\`
- Password : \`${DB_STAGING_PWD}\`

## Redis

- Bind     : 127.0.0.1:6379
- Password : \`${REDIS_PWD}\`

## Webhook GitHub à configurer (UN seul, dispatch interne par branche)

Repo \`${REPO_URL}\` → Settings → Webhooks → Add webhook

| Champ        | Valeur                                       |
| ------------ | -------------------------------------------- |
| Payload URL  | \`https://${DOMAIN}/_gh-deploy\`             |
| Content type | \`application/json\`                         |
| Secret       | \`${HMAC_SECRET}\`                           |
| Events       | Just the push event                          |
| Active       | ✓                                            |

Le serveur dispatche automatiquement :

- push sur \`${PROD_BRANCH}\` → déploie production (\`https://${DOMAIN}\`)
- push sur \`${STAGING_BRANCH}\` → déploie staging (\`https://staging.${DOMAIN}\`)
- autre branche → ignoré (visible dans \`/var/log/deploy.log\`)

## Deploy key GitHub (déjà installée durant l'install)

Repo → Settings → Deploy keys (Allow write : NON) :

\`\`\`
${SSH_DEPLOY_PUBKEY}
\`\`\`

Clé privée correspondante : \`/home/ubuntu/.ssh/deploy_key\` (chmod 600).

## Monitoring (Ember)

Dashboard TUI temps réel pour Caddy/FrankenPHP. Pas de port exposé : tu lis
directement l'admin API locale (127.0.0.1:2019) depuis le shell SSH.

\`\`\`bash
ssh -p 2222 ubuntu@${FQDN}
ember            # TUI : RPS, latences, percentiles, threads/workers FrankenPHP, logs
ember status     # one-shot health check
ember --help
\`\`\`

Si \`ember\` se plaint de l'absence de métriques Caddy :

\`\`\`bash
ember init       # active les métriques via admin API, sans restart
\`\`\`

## Backups MariaDB

- Script    : \`/usr/local/bin/backup-mariadb.sh\`
- Cron      : tous les jours à 03:00
- Dossier   : \`/var/backups/mariadb/\`
- Rétention : 7 jours quotidiens + 4 hebdos (dimanche)

## Commandes utiles

\`\`\`bash
# Reload web sans coupure
sudo systemctl reload frankenphp

# Logs déploiement
tail -f /var/log/deploy.log

# CrowdSec
sudo cscli decisions list
sudo cscli alerts list

# Trigger un déploiement manuel
sudo -u ubuntu /usr/local/bin/deploy-production.sh
sudo -u ubuntu /usr/local/bin/deploy-staging.sh
\`\`\`

## Fichiers et dossiers clés

- Caddyfile         : \`/etc/frankenphp/Caddyfile\`
- Service web       : \`frankenphp.service\`
- Service webhook   : \`webhook.service\` (127.0.0.1:9000)
- Config webhook    : \`/etc/webhook.conf.json\`
- Sites             : \`/var/www/${SLUG}/{production,staging}\`
- Logs FrankenPHP   : \`/var/log/frankenphp/\`
- Logs install      : \`/var/log/install-ubuntu.log\`
EOF

# Section Typesense optionnelle (appendée après pour éviter les jeux de quoting
# sur les triple-backticks d'un heredoc imbriqué).
if [ "${INSTALL_TYPESENSE:-false}" = "true" ] && [ -n "${TYPESENSE_API_KEY:-}" ]; then
    cat >> "$PWD_FILE" <<EOF

## Typesense (search engine local)

- Bind     : 127.0.0.1:8108 (loopback only, accès via Laravel/Scout)
- API key  : \`${TYPESENSE_API_KEY}\`
- Data dir : \`/var/lib/typesense/\`
- Logs     : \`/var/log/typesense/\`
- Service  : \`typesense-server.service\`

Vérification :

\`\`\`bash
curl -s http://127.0.0.1:8108/health
curl -s -H "X-TYPESENSE-API-KEY: ${TYPESENSE_API_KEY}" http://127.0.0.1:8108/collections
\`\`\`

Côté Laravel (déjà pré-rempli dans .env par le bootstrap) :

\`\`\`
SCOUT_DRIVER=typesense
TYPESENSE_HOST=127.0.0.1
TYPESENSE_PORT=8108
TYPESENSE_PROTOCOL=http
TYPESENSE_API_KEY=${TYPESENSE_API_KEY}
\`\`\`
EOF
fi

chmod 600 "$PWD_FILE"
chown ubuntu:ubuntu "$PWD_FILE"

# Nettoyage : on supprime le .secrets.env une fois passwords.md écrit, pour ne pas garder
# les secrets en double sur disque. La config (sans secrets) reste pour l'idempotence.
if [ -f "$SECRETS_FILE" ]; then
    shred -u "$SECRETS_FILE" 2>/dev/null || rm -f "$SECRETS_FILE"
fi

# Pas d'echo des secrets dans le log d'install — on logge juste le chemin
log_ok "Fichier secrets généré : ${PWD_FILE}"
