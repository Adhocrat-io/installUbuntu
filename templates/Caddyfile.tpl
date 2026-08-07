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
        # worker /var/www/{{SLUG}}/production{{APP_SUBDIR_PATH}}/public/frankenphp-worker.php 4
        # worker /var/www/{{SLUG}}/staging{{APP_SUBDIR_PATH}}/public/frankenphp-worker.php 2
    }
}

# Snippet réutilisable : refus des fichiers qui n'ont rien à faire dans un webroot.
# Importé via `import deny_sensitive` en TÊTE de chaque bloc de site — l'ordre
# compte, ces règles doivent passer avant le renvoi vers Laravel.
(deny_sensitive) {
    # Fichiers et dossiers cachés, à N'IMPORTE QUELLE profondeur : .env, .git/,
    # .aws/credentials, .DS_Store, .idea/…
    #
    # Le matcher `path` de Caddy ne franchit pas les `/` : le motif historique
    # `/.* /*/.*` n'attrapait que la racine et le premier niveau, si bien que
    # /a/b/.git/config restait servi. `path_regexp` teste « un point juste après
    # un slash, ou en tout début de chemin », donc à toute profondeur.
    #
    # /.well-known/ reste accessible : Let's Encrypt en a besoin pour renouveler
    # le certificat, et c'est là que vivent security.txt et les fichiers
    # d'association d'applications mobiles.
    @hidden_files {
        not path /.well-known/*
        path_regexp hidden (^|/)[.]
    }
    handle @hidden_files {
        respond 403
    }

    # Sauvegardes, dumps, sources et archives laissés par erreur dans le webroot.
    # Un `site-backup.zip` ou un `dump.sql` oublié est une fuite de données
    # classique. Si un site doit servir une archive en téléchargement, retirer
    # l'extension concernée de cette liste.
    @sensitive_files path *.bak *.backup *.bkp *.old *.orig *.rej *.save *.swp *.swo *.tmp *.temp *~ *.log *.sql *.sqlite *.sqlite3 *.db *.dump *.sh *.bash *.config *.dist *.ini *.yml *.yaml *.lock *.inc *.psd *.fla *.twig *.tpl *.zip *.tar *.gz *.tgz *.bz2 *.7z *.rar
    handle @sensitive_files {
        respond 403
    }
}

# Snippet réutilisable : règles de cache TTL par type de fichier.
# Importé via `import cache_rules` dans chaque bloc de site.
#
# Chaque matcher combine `path` (extension) ET `file` (existence physique sur disque).
# Conséquence : si /favicon.ico n'existe PAS, Laravel répond une 404 avec
# `Cache-Control: no-cache` et nos règles ne s'appliquent pas (ce qui est correct).
# Le préfixe `>` sur Cache-Control remplace toute valeur posée par PHP, par sécurité.
#
# Les règles s'excluent mutuellement par `not path /build/*` plutôt que de
# compter sur l'ordre d'évaluation : une seule règle peut s'appliquer à un
# fichier donné, quel que soit l'ordre des directives.
#
# Le HTML n'est VOLONTAIREMENT jamais mis en cache publiquement : les pages
# portent le jeton CSRF de la session (attribut `data-csrf` de Livewire). Un
# cache partagé servirait le jeton d'un visiteur à un autre. Laravel répond
# `no-cache, private`, et la mise en cache des pages se fait côté serveur
# (spatie/laravel-responsecache), là où la session est connue.
(cache_rules) {
    # Assets produits par Vite : le nom porte un hash du contenu, donc l'URL
    # change à chaque modification. Le fichier peut être gardé indéfiniment —
    # c'est le gain le plus net sur les visites répétées et la navigation interne.
    @cache_build {
        path /build/*
        file
    }
    header @cache_build >Cache-Control "public, max-age=31536000, immutable"

    # Médias et polices hors build (noms stables, remplacés rarement) — 30 jours.
    @cache_media {
        path *.jpg *.jpeg *.png *.gif *.webp *.avif *.svg *.svgz *.woff *.woff2 *.ttf *.otf *.eot *.mp4 *.webm *.ogg *.ogv *.m4a *.m4v *.wasm
        not path /build/*
        file
    }
    header @cache_media >Cache-Control "public, max-age=2592000, immutable"

    # Favicon : 1 semaine (nom fixe, peut être remplacée occasionnellement)
    @cache_favicon {
        path *.ico *.webmanifest
        file
    }
    header @cache_favicon >Cache-Control "public, max-age=604800"

    # JS / CSS / source maps hors build (non hashés) : 7 jours.
    @cache_code {
        path *.js *.mjs *.css *.map
        not path /build/*
        file
    }
    header @cache_code >Cache-Control "public, max-age=604800"

    # Flux RSS / Atom : 1 heure (servis souvent en dynamique par Laravel,
    # donc PAS de matcher `file` ici — on cible aussi les routes /feed.xml etc.)
    @cache_feeds path *.rss *.atom *.xml
    header @cache_feeds >Cache-Control "public, max-age=3600"

    # CORS pour webfonts (utile si servi depuis sous-domaine ou CDN)
    @cors_fonts {
        path *.woff *.woff2 *.ttf *.otf *.eot
        file
    }
    header @cors_fonts Access-Control-Allow-Origin *
}

# Redirect www vers apex
www.{{DOMAIN}} {
    redir https://{{DOMAIN}}{uri} permanent
}

# Production (apex)
{{DOMAIN}} {
    root * /var/www/{{SLUG}}/production{{APP_SUBDIR_PATH}}/public

    # zstd d'abord (meilleur ratio, négocié par les navigateurs récents), gzip
    # en repli. En dessous de 256 octets la compression coûte plus qu'elle ne
    # rapporte — l'en-tête pèse déjà autant que le gain.
    encode {
        zstd
        gzip
        minimum_length 256
    }

    # Fichiers cachés, sauvegardes, dumps → 403, AVANT tout autre traitement.
    import deny_sensitive

    # Webhook GitHub : route isolée AVANT le renvoi vers Laravel — sinon le
    # rewrite l'avale. GitHub poste sur /_gh-deploy (avec ou sans slash) ;
    # rewrite vers /hooks/gh-deploy (chemin attendu par adnanh/webhook avec son
    # urlprefix par défaut "hooks").
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
    root * /var/www/{{SLUG}}/staging{{APP_SUBDIR_PATH}}/public

    encode {
        zstd
        gzip
        minimum_length 256
    }

    # Fichiers cachés, sauvegardes, dumps → 403 (idem prod)
    import deny_sensitive

    handle {
        # Routes Laravel : tout path inexistant → /index.php (Livewire, Flux, etc.
        # incluent des routes en .js/.css que php_server ne passe pas à PHP par défaut).
        @notFile not file
        rewrite @notFile /index.php?{query}

        php_server
    }

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
