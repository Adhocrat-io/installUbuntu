#!/usr/bin/env bash
# 15-node-yarn — Node 20 LTS via NodeSource + yarn global

if ! command -v node >/dev/null 2>&1 || [ "$(node -v 2>/dev/null | grep -oE '^v[0-9]+' | tr -d v)" != "20" ]; then
    log_info "  → ajout du repo NodeSource (Node 20)…"
    curl -fsSL --max-time 60 https://deb.nodesource.com/setup_20.x | bash - \
        || die "Setup repo NodeSource KO."
    log_info "  → installation Node.js…"
    apt-get install -y -qq nodejs
fi

if ! command -v yarn >/dev/null 2>&1; then
    log_info "  → installation Yarn (global, via npm)…"
    npm install -g --silent yarn
fi

if ! command -v pnpm >/dev/null 2>&1; then
    log_info "  → installation pnpm (global, via npm)…"
    npm install -g --silent pnpm
fi

log_ok "Node $(node -v) + Yarn $(yarn --version) + pnpm $(pnpm --version) installés."
