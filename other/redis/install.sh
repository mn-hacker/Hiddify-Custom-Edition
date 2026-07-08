source /opt/hiddify-manager/common/utils.sh
if ! is_installed redis-server; then
    add-apt-repository -y universe
    install_package redis-server
fi
ln -sf $(pwd)/hiddify-redis.service /etc/systemd/system/hiddify-redis.service >/dev/null 2>&1
systemctl enable hiddify-redis
systemctl daemon-reload >/dev/null 2>&1

# Ensure log directories exist with proper permissions
mkdir -p /var/log/redis
mkdir -p /opt/hiddify-manager/log/system
chown -R redis:redis /var/log/redis
chmod -R 755 /var/log/redis

touch /opt/hiddify-manager/log/system/redis-server.log
chown redis:redis /opt/hiddify-manager/log/system/redis-server.log
chown -R redis:redis .
chmod 600 redis.conf

# --- Watashi: cap redis memory based on server RAM to prevent OOM/hang after ~1-2 weeks ---
total_ram_mb=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}')
if [ -n "$total_ram_mb" ] && [ "$total_ram_mb" -gt 0 ]; then
    redis_mm=$(( total_ram_mb * 15 / 100 ))
    [ "$redis_mm" -lt 128 ] && redis_mm=128
    [ "$redis_mm" -gt 1024 ] && redis_mm=1024
    sed -i '/^maxmemory /d' redis.conf
    echo "maxmemory ${redis_mm}mb" >>redis.conf
fi
grep -q '^maxmemory-policy' redis.conf || echo "maxmemory-policy allkeys-lru" >>redis.conf

if ! grep -q "^requirepass" "redis.conf"; then
    # Generate a random password
    random_password=$(< /dev/urandom tr -dc 'a-zA-Z0-9' | head -c49; echo)
    # Add requirepass with the generated password to redis.conf
    echo "requirepass $random_password" >>redis.conf   
    systemctl disable --now redis-server >/dev/null 2>&1
    pkill -9 redis-server
    systemctl restart hiddify-redis
fi



# Apply config changes (maxmemory, etc.) on every (re)install so redis picks them up
systemctl restart hiddify-redis >/dev/null 2>&1

# systemctl reload hiddify-redis
