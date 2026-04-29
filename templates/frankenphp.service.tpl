[Unit]
Description=FrankenPHP server
Documentation=https://frankenphp.dev
After=network.target network-online.target mariadb.service redis-server.service
Requires=network-online.target

[Service]
Type=notify
User=ubuntu
Group=www-data
ExecStart=/usr/local/bin/frankenphp run --config /etc/frankenphp/Caddyfile
ExecReload=/usr/local/bin/frankenphp reload --config /etc/frankenphp/Caddyfile --force
TimeoutStopSec=5s
LimitNOFILE=1048576
LimitNPROC=512
PrivateTmp=true
ProtectSystem=full
ProtectHome=read-only
ReadWritePaths=/var/www /var/log/frankenphp /var/lib/caddy /etc/frankenphp /home/ubuntu
AmbientCapabilities=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
