#!/usr/bin/env bash
# 16-redis — Redis bind 127.0.0.1 + requirepass

apt-get install -y -qq redis-server

load_secrets
REDIS_PWD="${REDIS_PWD:-$(gen_password)}"
record_secret REDIS_PWD "$REDIS_PWD"

# Édition directe de /etc/redis/redis.conf (pas de drop-in natif chez Debian/Ubuntu)
sed -i \
    -e 's/^bind .*/bind 127.0.0.1 -::1/' \
    -e 's/^# requirepass .*/requirepass '"${REDIS_PWD}"'/' \
    -e 's/^requirepass .*/requirepass '"${REDIS_PWD}"'/' \
    -e 's/^protected-mode .*/protected-mode yes/' \
    -e 's/^# maxmemory-policy.*/maxmemory-policy allkeys-lru/' \
    /etc/redis/redis.conf

# Si requirepass absent (cas premier set sans `# requirepass`), append
grep -q '^requirepass ' /etc/redis/redis.conf || echo "requirepass ${REDIS_PWD}" >> /etc/redis/redis.conf

systemctl enable --now redis-server
systemctl restart redis-server

log_ok "Redis configuré (bind 127.0.0.1, requirepass généré)."
