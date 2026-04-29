#!/usr/bin/env bash
# Active le worker Octane dans le Caddyfile pour un environnement donné, après son
# premier déploiement (présence du fichier frankenphp-worker.php).
#
# Usage : sudo enable-octane-worker.sh production|staging

set -euo pipefail

ENV="${1:-}"
case "$ENV" in
    production|staging) ;;
    *) echo "Usage: $0 production|staging" >&2; exit 2 ;;
esac

CADDYFILE=/etc/frankenphp/Caddyfile

# Slug et chemin worker — détectés depuis le Caddyfile (root *)
SITE_ROOT="$(grep -oE 'root \* /var/www/[^/]+/'"$ENV"'/public' "$CADDYFILE" | head -n1 | awk '{print $3}')"
[ -n "$SITE_ROOT" ] || { echo "Site root introuvable dans Caddyfile pour $ENV" >&2; exit 1; }

WORKER="${SITE_ROOT}/frankenphp-worker.php"
[ -f "$WORKER" ] || { echo "Worker absent : $WORKER (Octane pas encore installé pour $ENV)"; exit 0; }

# Marqueur d'idempotence
MARK="/var/lib/install-ubuntu/.octane-${ENV}.done"
[ -f "$MARK" ] && { echo "Worker $ENV déjà activé."; exit 0; }

# Workers : 4 pour prod, 2 pour staging
N_WORKERS=4
[ "$ENV" = "staging" ] && N_WORKERS=2

# Décommente la ligne worker correspondante (formatée à l'install)
sed -i -E "s|^[[:space:]]*#[[:space:]]*worker (${SITE_ROOT//\//\\/}/frankenphp-worker\.php) [0-9]+|        worker \1 ${N_WORKERS}|" "$CADDYFILE"

# Validation puis reload
if /usr/local/bin/frankenphp validate --config "$CADDYFILE" >/dev/null 2>&1; then
    systemctl reload frankenphp
    mkdir -p "$(dirname "$MARK")"
    touch "$MARK"
    echo "Octane worker activé pour $ENV (${N_WORKERS} workers)."
else
    echo "Caddyfile invalide après modif — abort, restauration nécessaire." >&2
    exit 1
fi
