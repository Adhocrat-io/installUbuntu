# Caddyfile généré par le script d'install
# {{DOMAIN}} (apex + www) → /var/www/{{SLUG}}/production
# staging.{{DOMAIN}} → /var/www/{{SLUG}}/staging

{
    email {{ALERT_EMAIL}}
    log {
        output file /var/log/frankenphp/access.log
        format json
    }
    frankenphp {
        # Workers Octane décommentés par enable-octane-worker.sh au premier déploiement.
        # worker /var/www/{{SLUG}}/production/public/frankenphp-worker.php 4
        # worker /var/www/{{SLUG}}/staging/public/frankenphp-worker.php 2
    }
}

# Snippet réutilisable : règles de cache TTL par type de fichier.
# Importé via `import cache_rules` dans chaque bloc de site.
# Les matchers `path` ne ciblent que les fichiers statiques (servis directement par
# Caddy) — les réponses Laravel (HTML/JSON dynamiques) ne sont PAS impactées et
# conservent leurs propres headers Cache-Control.
(cache_rules) {
    # Assets immuables (Vite/Mix hashent les noms) — 30 jours, immutable
    @cache_immutable path *.jpg *.jpeg *.png *.gif *.webp *.svg *.svgz *.woff *.woff2 *.ttf *.otf *.eot *.mp4 *.webm *.ogg *.ogv *.m4a *.m4v
    header @cache_immutable Cache-Control "public, max-age=2592000, immutable"

    # Favicon : 1 semaine (nom fixe, peut être remplacée occasionnellement)
    @cache_favicon path *.ico
    header @cache_favicon Cache-Control "public, max-age=604800"

    # JS / CSS / source maps : 7 jours
    # (avec hash Vite, on pourrait monter à immutable 30j)
    @cache_code path *.js *.css *.map
    header @cache_code Cache-Control "public, max-age=604800"

    # Flux RSS / Atom : 1 heure
    @cache_feeds path *.rss *.atom *.xml
    header @cache_feeds Cache-Control "public, max-age=3600"

    # CORS pour webfonts (utile si servi depuis sous-domaine ou CDN)
    @cors_fonts path *.woff *.woff2 *.ttf *.otf *.eot
    header @cors_fonts Access-Control-Allow-Origin *
}

# Redirect www vers apex
www.{{DOMAIN}} {
    redir https://{{DOMAIN}}{uri} permanent
}

# Production (apex)
{{DOMAIN}} {
    root * /var/www/{{SLUG}}/production/public
    encode zstd gzip

    # Webhook GitHub : route isolée AVANT toute autre — sinon le rewrite Laravel l'avale.
    # GitHub poste sur /_gh-deploy (avec ou sans slash) ; rewrite vers /hooks/gh-deploy
    # (chemin attendu par adnanh/webhook avec son urlprefix par défaut "hooks").
    @gh_deploy path /_gh-deploy /_gh-deploy/
    handle @gh_deploy {
        rewrite * /hooks/gh-deploy
        reverse_proxy 127.0.0.1:9000
    }

    # Tout le reste → Laravel
    handle {
        # Routes Laravel : tout path inexistant → /index.php (Livewire, Flux, etc.
        # incluent des routes en .js/.css que php_server ne passe pas à PHP par défaut).
        @notFile not file
        rewrite @notFile /index.php?{query}

        php_server
    }

    # === Sécurité, cache, CORS ===

    # Bloquer fichiers cachés (.env, .git, …) et backups, sauf .well-known (Let's Encrypt)
    @forbidden {
        path /.* /*/.* *.bak *.config *.dist *.fla *.inc *.ini *.log *.psd *.sh *.sql *.swp
        not path /.well-known/*
    }
    handle @forbidden {
        respond 403
    }

    # Règles de cache TTL par type de fichier (snippet partagé)
    import cache_rules

    # Headers de sécurité globaux
    header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains"
        X-Content-Type-Options "nosniff"
        X-Frame-Options "SAMEORIGIN"
        Referrer-Policy "strict-origin-when-cross-origin"
        Permissions-Policy "geolocation=(), microphone=(), camera=()"
        -ETag
        -Server
    }

    log {
        output file /var/log/frankenphp/production.log
        format json
    }
}

# Staging
staging.{{DOMAIN}} {
    root * /var/www/{{SLUG}}/staging/public
    encode zstd gzip

    # Bloquer fichiers cachés / backups (idem prod)
    @forbidden {
        path /.* /*/.* *.bak *.config *.dist *.fla *.inc *.ini *.log *.psd *.sh *.sql *.swp
        not path /.well-known/*
    }
    handle @forbidden {
        respond 403
    }

    # Routes Laravel : tout path inexistant → /index.php (Livewire, Flux, etc.
    # incluent des routes en .js/.css que php_server ne passe pas à PHP par défaut).
    @notFile not file
    rewrite @notFile /index.php?{query}

    php_server

    # Règles de cache TTL (mêmes qu'en prod, snippet partagé)
    import cache_rules

    # Pas d'HSTS sur staging (utile si tests sans HTTPS, sinon supprimer la ligne)
    header {
        X-Content-Type-Options "nosniff"
        X-Frame-Options "SAMEORIGIN"
        Referrer-Policy "strict-origin-when-cross-origin"
        -ETag
        -Server
        # Empêche l'indexation Google de l'environnement staging
        X-Robots-Tag "noindex, nofollow"
    }

    log {
        output file /var/log/frankenphp/staging.log
        format json
    }
}
