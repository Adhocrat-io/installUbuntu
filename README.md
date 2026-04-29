# installUbuntu — provisionnement automatisé VPS OVH

Script bash interactif idempotent pour provisionner un VPS OVH fraîchement installé sous **Ubuntu 24.04 LTS** ou **25.04**, avec une stack PHP moderne :

- **FrankenPHP** (Caddy + PHP 8.5) en mode worker Octane, multi-site
- **MariaDB** (bind localhost + DBs prod/staging)
- **Redis** (bind localhost + password)
- **Node 20** + **Yarn**
- **Composer**, **Supervisor**, **Postfix** send-only

Sécurité par défaut :

- SSH durci sur **port 2222**, key-only, AllowUsers ubuntu, algos modernes
- **UFW** deny-by-default (2222, 80, 443 uniquement)
- **CrowdSec** + bouncer firewall
- **Kernel hardening** sysctl (SYN cookies, anti-spoof, ICMP, kptr_restrict, …)
- `/tmp` et `/dev/shm` en `noexec,nosuid,nodev`
- `unattended-upgrades` (security + reboot auto à 04:00 si nécessaire)

Déploiement automatique via **un seul webhook GitHub** (pas GitHub Actions) :

- Push sur `main`/`master` → déploie production sur `https://nomdusite.com` (apex + redirect www)
- Push sur `staging` → déploie staging sur `https://staging.nomdusite.com`
- Autre branche → ignoré

## Prérequis

- VPS OVH Ubuntu 24.04 LTS ou 25.04, fraîchement installé
- User `ubuntu` existant avec **clé SSH déjà autorisée** dans `~/.ssh/authorized_keys`
- DNS du domaine pointant déjà vers l'IP du serveur, **avant le lancement** :
  - `nomdusite.com` (apex)
  - `www.nomdusite.com`
  - `staging.nomdusite.com`
- Un repo GitHub avec deux branches : prod (`main`/`master`) + `staging`

## Lancement

```bash
# Sur le VPS, en root (ou via sudo) :
git clone https://github.com/<ton-fork>/installUbuntu.git /opt/installUbuntu
cd /opt/installUbuntu
sudo bash install.sh
```

Le script demande interactivement :

1. Hostname court + FQDN
2. Domaine principal (le slug `/var/www/{slug}` en est dérivé)
3. URL SSH du repo GitHub
4. Branches prod (défaut `main`) et staging (défaut `staging`)
5. Email d'alerte (par défaut `ubuntu@<FQDN>` local)

À mi-parcours, le script **génère une deploy key SSH ed25519** et **pause** pour que tu la colles dans ton repo GitHub → Settings → Deploy keys (Allow write : NON). Tape `oui` une fois fait, le script teste la connexion `ssh -T git@github.com` et reprend.

À la fin :

- Tous les secrets générés (DB root, DB prod/staging, Redis, HMAC webhook) sont dans `/home/ubuntu/passwords.md` (**chmod 600**, jamais affichés stdout).
- Une URL webhook unique + son secret HMAC y sont aussi listés — à coller dans GitHub → Settings → Webhooks.
- Les deux environnements sont déjà clonés et déployés.

## Idempotence

Chaque module pose un marqueur dans `/var/lib/install-ubuntu/.<module>.done` après succès. Re-lancer `install.sh` skip les modules déjà appliqués. La config utilisateur est sauvegardée dans `/var/lib/install-ubuntu/config.env`.

Pour **forcer la ré-exécution d'un module** : supprimer son marqueur avant relance.

## Architecture FrankenPHP

- **Un seul service systemd** (`frankenphp.service`)
- **Un seul Caddyfile** (`/etc/frankenphp/Caddyfile`)
- 3 hôtes : apex, www (redir), staging
- **Workers Octane** : 4 pour prod, 2 pour staging — activés automatiquement par `enable-octane-worker.sh` après le premier déploiement (présence de `public/frankenphp-worker.php`)
- `caddy reload` (graceful, sans coupure) après chaque déploiement

## Webhook GitHub : flow

```
GitHub push → POST https://<DOMAIN>/_gh-deploy
            → Caddy reverse_proxy 127.0.0.1:9000
            → adnanh/webhook (vérifie HMAC + X-GitHub-Event=push)
            → /usr/local/bin/dispatch-deploy.sh <ref>
            → switch sur la branche :
                main/master → /usr/local/bin/deploy-production.sh
                staging     → /usr/local/bin/deploy-staging.sh
                autre       → ignored (logged)
```

Chaque script de déploiement fait :

```bash
git fetch && git reset --hard origin/<branche>
composer install (--no-dev pour prod)
[ npm ci && npm run build ]
php artisan migrate --force
[ php artisan {config,route,view,event}:cache pour prod ]
sudo /usr/local/bin/enable-octane-worker.sh <env>   # idempotent
sudo systemctl reload frankenphp
```

## Hors scope (à faire manuellement)

- Configuration DNS chez le registrar (avant l'install)
- Code applicatif (Laravel) : la stack est prête, le code arrive via webhook
- Sauvegarde externalisée (S3/Object Storage) : le backup MariaDB est local
- Relais SMTP authentifié pour les mails sortants (Postfix est en send-only loopback)
- 2FA SSH
- Mise à jour majeure d'Ubuntu

## Reset complet

```bash
sudo rm -rf /var/lib/install-ubuntu /var/log/install-ubuntu.log
# (ne supprime ni les paquets installés, ni les configs)
```

Pour repartir vraiment de zéro : reprovisionne le VPS.
