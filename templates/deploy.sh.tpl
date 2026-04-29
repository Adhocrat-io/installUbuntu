#!/usr/bin/env bash
# /usr/local/bin/deploy-{{ENV}}.sh
# Déploie l'environnement {{ENV}} (branche {{BRANCH}}) dans {{SITE_DIR}}.
# Doit être lancé en user ubuntu (le webhook l'exécute en ubuntu, le bootstrap aussi).

set -euo pipefail

ENV={{ENV}}
BRANCH={{BRANCH}}
SITE_DIR={{SITE_DIR}}

cd "$SITE_DIR"

# Lock pour éviter deux déploiements concurrents
exec 9>"/tmp/deploy-${ENV}.lock"
if ! flock -n 9; then
    echo "[$(date -Iseconds)] $ENV : déploiement déjà en cours, skip." >&2
    exit 0
fi

echo "[$(date -Iseconds)] $ENV : git fetch + reset"
git fetch --all --prune
git reset --hard "origin/${BRANCH}"
git clean -fd

# Filet de sécurité : .env devrait avoir été pré-rempli au bootstrap
if [ ! -f .env ] && [ -f .env.example ]; then
    cp .env.example .env
    echo "[$(date -Iseconds)] $ENV : .env initialisé depuis .env.example — pense à compléter les credentials !"
fi

echo "[$(date -Iseconds)] $ENV : composer install"
if [ "$ENV" = "production" ]; then
    composer install --no-dev --optimize-autoloader --no-interaction --prefer-dist
else
    composer install --no-interaction --prefer-dist
fi

# APP_KEY : généré si vide (idempotent — ne touche pas une clé existante)
if [ -f .env ] && [ -f artisan ] && grep -qE '^APP_KEY=\s*$' .env; then
    php artisan key:generate --force --no-interaction || true
fi

# Octane : installation au premier passage si absent (génère le worker)
if [ -f artisan ] && ! [ -f public/frankenphp-worker.php ]; then
    echo "[$(date -Iseconds)] $ENV : octane:install (première exécution)"
    php artisan octane:install --server=frankenphp --no-interaction || true
fi

if [ -f package.json ]; then
    # CI=true : tous les outils passent en mode non-interactif strict (npm, vite,
    # husky…). Pas de --silent : on veut voir la progression sur les gros projets
    # (sinon ça donne l'impression de bloquer alors que ça travaille).
    export CI=true

    # Détection du package manager via le lockfile présent dans le repo.
    # `npm ci` exige package-lock.json, `yarn install --frozen-lockfile` exige
    # yarn.lock. Mélanger les deux conduit à des erreurs silencieuses.
    has_build_script() {
        jq -e '.scripts.build' package.json >/dev/null 2>&1
    }

    if [ -f pnpm-lock.yaml ]; then
        echo "[$(date -Iseconds)] $ENV : pnpm install + build (pnpm-lock.yaml détecté)"
        pnpm install --frozen-lockfile
        if has_build_script; then
            pnpm run build
        fi
    elif [ -f yarn.lock ]; then
        echo "[$(date -Iseconds)] $ENV : yarn install + build (yarn.lock détecté)"
        yarn install --frozen-lockfile --non-interactive
        if has_build_script; then
            yarn run build
        fi
    elif [ -f package-lock.json ]; then
        echo "[$(date -Iseconds)] $ENV : npm ci + build (package-lock.json détecté)"
        npm ci --no-audit --no-fund
        npm run build --if-present
    else
        echo "[$(date -Iseconds)] $ENV : ⚠ package.json présent mais aucun lockfile (pnpm-lock.yaml, yarn.lock ou package-lock.json) — skip install JS." >&2
    fi
fi

echo "[$(date -Iseconds)] $ENV : migrate"
php artisan migrate --force --no-interaction || true

if [ "$ENV" = "production" ]; then
    php artisan config:cache
    php artisan route:cache
    php artisan view:cache
    php artisan event:cache || true
else
    # Staging : caches plus permissifs (debug/profiling possible)
    php artisan config:clear
    php artisan route:clear
    php artisan view:clear
fi

# Active le worker Octane si possible (premier déploiement uniquement, idempotent)
sudo /usr/local/bin/enable-octane-worker.sh "$ENV" || true

# Reload du service web (graceful, sans coupure)
if systemctl is-active --quiet frankenphp; then
    sudo /bin/systemctl reload frankenphp
else
    sudo /bin/systemctl restart frankenphp
fi

echo "[$(date -Iseconds)] $ENV : déploiement OK"
