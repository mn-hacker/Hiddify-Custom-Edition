# watashi v12.3.40dev: the old project name was taken out of this file (names, paths and links only)
source /opt/watashi-manager/common/utils.sh

ln -sf $(pwd)/watashi-ssh-liberty-bridge.service /etc/systemd/system/watashi-ssh-liberty-bridge.service

chown -R liberty-bridge host_key

# Get Redis password
if [ -z "${REDIS_URI_SSH}" ]; then
    REDIS_PASS=$(grep '^requirepass' "../redis/redis.conf" | awk '{print $2}')
    REDIS_URI_SSH="redis://:${REDIS_PASS}@127.0.0.1:6379/1"
fi

# Get server IP
SERVER_IP=$(curl -s --connect-timeout 5 https://api.ipify.org || hostname -I | awk '{print $1}')

# Get SSH port from panel config, default to 2222
SSH_PORT=$(hconfig ssh_server_port 2>/dev/null || echo "2222")

# Create complete .env file
cat > .env << EOF
REDIS_URL='$REDIS_URI_SSH'
LISTEN_ADDR=":$SSH_PORT"
CONFIG_PATH="/var/ssh-users/"
HOST_ADDR="http://localhost:8083/{uuid}.json"
SERVER_ADDR="$SERVER_IP"
SERVER_PORT=$SSH_PORT
HOST_KEY_PATH="$(pwd)/host_key/"
TEMPLATE_PATH="./generator/template.json"
MAX_CONNECTIONS=100
COPY_SERVER_VERSION="localhost:22"
DEFAULT_SERVER_VERSION="SSH-2.0-OpenSSH_8.9"
SOCKS_PROXY=""
WHITELIST_PORTS=""
EOF

chown liberty-bridge:liberty-bridge .env
chmod 600 .env

systemctl enable watashi-ssh-liberty-bridge
systemctl restart watashi-ssh-liberty-bridge