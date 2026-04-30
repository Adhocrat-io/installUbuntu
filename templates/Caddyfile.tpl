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

# Redirect www vers apex
www.{{DOMAIN}} {
    redir https://{{DOMAIN}}{uri} permanent
}

# Production (apex)
{{DOMAIN}} {
    root * /var/www/{{SLUG}}/production/public
    encode zstd gzip

    # Webhook GitHub : route isolée — sinon le rewrite Laravel ci-dessous l'avale.
    # Le client GitHub poste sur /_gh-deploy ; on réécrit en interne vers /hooks/gh-deploy
    # (chemin attendu par adnanh/webhook avec son urlprefix par défaut "hooks").
    handle /_gh-deploy {
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

    # === Production : équivalents .htaccess H5BP (sécurité, cache, CORS) ===

    # Bloquer fichiers cachés (.env, .git, …) et backups, sauf .well-known (Let's Encrypt)
    @forbidden {
        path /.* /*/.* *.bak *.config *.dist *.fla *.inc *.ini *.log *.psd *.sh *.sql *.swp
        not path /.well-known/*
    }
    handle @forbidden {
        respond 403
    }

    # Cache long pour assets immuables (Vite hashed) — 30 jours
    @assets_immutable path *.jpg *.jpeg *.png *.gif *.svg *.svgz *.webp *.ico *.woff *.woff2 *.ttf *.otf *.eot *.mp4 *.webm *.ogg *.m4a
    header @assets_immutable Cache-Control "public, max-age=2592000, immutable"

    # JS/CSS/maps — 7 jours (Vite ajoute un hash, donc immutable serait OK aussi)
    @assets_code path *.js *.css *.map
    header @assets_code Cache-Control "public, max-age=604800"

    # CORS pour webfonts (utile si tu sers depuis un sous-domaine ou CDN futur)
    @cors_fonts path *.woff *.woff2 *.ttf *.otf *.eot
    header @cors_fonts Access-Control-Allow-Origin *

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

    # Routes Laravel : tout path inexistant → /index.php (Livewire, Flux, etc.
    # incluent des routes en .js/.css que php_server ne passe pas à PHP par défaut).
    @notFile not file
    rewrite @notFile /index.php?{query}

    php_server

    log {
        output file /var/log/frankenphp/staging.log
        format json
    }
}
