#!/usr/bin/env bash
# Fonctions utilitaires partagées par tous les modules.
# NE JAMAIS faire `set -x` ici : on manipule des secrets.

# shellcheck disable=SC2034
HELPERS_LOADED=1

_log() {
    local level="$1"; shift
    local color_reset="\033[0m"
    local color
    case "$level" in
        INFO) color="\033[1;34m" ;;
        WARN) color="\033[1;33m" ;;
        ERR)  color="\033[1;31m" ;;
        OK)   color="\033[1;32m" ;;
        *)    color="" ;;
    esac
    local ts
    ts="$(date -Iseconds)"
    printf '%b[%s] [%s]%b %s\n' "$color" "$ts" "$level" "$color_reset" "$*" | tee -a "${LOG_FILE:-/dev/null}"
}

log_info() { _log INFO "$@"; }
log_warn() { _log WARN "$@"; }
log_err()  { _log ERR  "$@" >&2; }
log_ok()   { _log OK   "$@"; }

die() {
    log_err "$*"
    exit 1
}

# ask "Question ?" "default" → renvoie sur stdout la réponse
ask() {
    local prompt="$1"
    local default="${2:-}"
    local reply
    if [ -n "$default" ]; then
        read -r -p "${prompt} [${default}] : " reply || true
        printf '%s' "${reply:-$default}"
    else
        while [ -z "${reply:-}" ]; do
            read -r -p "${prompt} : " reply || true
        done
        printf '%s' "$reply"
    fi
}

ask_yes_no() {
    local prompt="$1"
    local default="${2:-n}"
    local hint="(o/N)"
    [ "$default" = "o" ] || [ "$default" = "y" ] && hint="(O/n)"
    local reply
    while true; do
        read -r -p "${prompt} ${hint} : " reply || true
        reply="${reply:-$default}"
        case "$reply" in
            o|O|y|Y|oui|yes) return 0 ;;
            n|N|non|no)      return 1 ;;
        esac
    done
}

gen_password() {
    # 32 chars URL-safe (générés depuis 48 octets pour avoir de la marge après strip)
    openssl rand -base64 48 | tr -d '/+=\n' | cut -c1-32
}

is_done() {
    local module="$1"
    [ -f "${STATE_DIR}/.${module}.done" ]
}

mark_done() {
    local module="$1"
    touch "${STATE_DIR}/.${module}.done"
}

save_config() {
    local key="$1" value="$2"
    # Append/update key=value dans config.env (simple, idempotent).
    if [ -f "$CONFIG_FILE" ] && grep -q "^${key}=" "$CONFIG_FILE"; then
        sed -i "s|^${key}=.*|${key}=$(printf '%q' "$value")|" "$CONFIG_FILE"
    else
        printf '%s=%q\n' "$key" "$value" >> "$CONFIG_FILE"
    fi
    chmod 600 "$CONFIG_FILE"
    # Expose la valeur aux modules suivants dans la même exécution
    # (sinon, à la 1ʳᵉ run sans config.env préexistant, les modules en aval ne la voient pas).
    export "$key=$value"
}

# Persistance des secrets en mémoire pour le finalize.
# Les secrets ne sont écrits sur disque QUE dans /home/ubuntu/passwords.md à la fin.
SECRETS_FILE="${STATE_DIR}/.secrets.env"
record_secret() {
    local key="$1" value="$2"
    touch "$SECRETS_FILE"
    chmod 600 "$SECRETS_FILE"
    if grep -q "^${key}=" "$SECRETS_FILE" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=$(printf '%q' "$value")|" "$SECRETS_FILE"
    else
        printf '%s=%q\n' "$key" "$value" >> "$SECRETS_FILE"
    fi
}

load_secrets() {
    [ -f "$SECRETS_FILE" ] || return 0
    # shellcheck disable=SC1090
    source "$SECRETS_FILE"
}

render_template() {
    # render_template <template_path> <output_path>
    # Remplace {{VAR}} par la valeur de $VAR pour chaque variable trouvée.
    local tpl="$1" out="$2"
    [ -f "$tpl" ] || die "Template introuvable : $tpl"

    local content
    content="$(cat "$tpl")"

    while IFS= read -r var; do
        local value="${!var:-}"
        # Echappement basique pour sed
        local escaped="${value//\\/\\\\}"
        escaped="${escaped//&/\\&}"
        escaped="${escaped//|/\\|}"
        content="$(printf '%s' "$content" | sed "s|{{${var}}}|${escaped}|g")"
    done < <(grep -oE '\{\{[A-Z_][A-Z0-9_]*\}\}' "$tpl" | sed 's/[{}]//g' | sort -u)

    printf '%s\n' "$content" > "$out"
}

require_var() {
    local var
    for var in "$@"; do
        [ -n "${!var:-}" ] || die "Variable requise non définie : $var"
    done
}
