#!/bin/bash
# watashi v12.3.40dev: the old project name was taken out of this file (names, paths and links only)

# Rathole Tunnel Creator
# Creates tunnel configuration and systemd service files
# Usage: create_tunnel.sh <type> <tunnel_port> <config_ports> <token> [options...]
# Type: iran or kharej
# Example: create_tunnel.sh kharej 8080 "443,80" mytoken server_ip=1.2.3.4 transport=tcp nodelay=true heartbeat=true

set -e

RATHOLE_DIR="/opt/watashi-manager/other/rathole"
SERVICE_DIR="/etc/systemd/system"

TYPE="$1"
TUNNEL_PORT="$2"
CONFIG_PORTS="$3"
TOKEN="$4"
shift 4

# Parse optional arguments
SERVER_IP=""
TRANSPORT="tcp"
NODELAY="true"
HEARTBEAT="true"
IPV6="false"

for arg in "$@"; do
    case $arg in
        server_ip=*) SERVER_IP="${arg#*=}" ;;
        transport=*) TRANSPORT="${arg#*=}" ;;
        nodelay=*) NODELAY="${arg#*=}" ;;
        heartbeat=*) HEARTBEAT="${arg#*=}" ;;
        ipv6=*) IPV6="${arg#*=}" ;;
    esac
done

# Calculate heartbeat value
HEARTBEAT_VAL=0
if [ "$HEARTBEAT" = "true" ]; then
    HEARTBEAT_VAL=40
fi

# Set nodelay value
NODELAY_STR="false"
if [ "$NODELAY" = "true" ]; then
    NODELAY_STR="true"
fi

# Set local IP based on IPv6
LOCAL_IP="0.0.0.0"
if [ "$IPV6" = "true" ]; then
    LOCAL_IP="[::]"
fi

# Create config directory
mkdir -p "$RATHOLE_DIR"
chmod 755 "$RATHOLE_DIR"

if [ "$TYPE" = "iran" ]; then
    # Iran (Server) configuration
    CONFIG_FILE="$RATHOLE_DIR/iran${TUNNEL_PORT}.toml"
    SERVICE_NAME="rathole-iran${TUNNEL_PORT}"
    
    # Generate config
    cat > "$CONFIG_FILE" << EOF
[server]
bind_addr = "${LOCAL_IP}:${TUNNEL_PORT}"
default_token = "${TOKEN}"
heartbeat_interval = ${HEARTBEAT_VAL}

[server.transport]
type = "${TRANSPORT}"

[server.transport.${TRANSPORT}]
nodelay = ${NODELAY_STR}
EOF

    # Add services for each port
    IFS=',' read -ra PORTS <<< "$CONFIG_PORTS"
    for port in "${PORTS[@]}"; do
        port=$(echo "$port" | tr -d ' ')
        cat >> "$CONFIG_FILE" << EOF

[server.services.${port}]
bind_addr = "${LOCAL_IP}:${port}"
EOF
    done

elif [ "$TYPE" = "kharej" ]; then
    # Kharej (Client) configuration
    if [ -z "$SERVER_IP" ]; then
        echo "Error: server_ip is required for kharej tunnel"
        exit 1
    fi
    
    CONFIG_FILE="$RATHOLE_DIR/kharej${TUNNEL_PORT}.toml"
    SERVICE_NAME="rathole-kharej${TUNNEL_PORT}"
    
    # Generate config
    cat > "$CONFIG_FILE" << EOF
[client]
remote_addr = "${SERVER_IP}:${TUNNEL_PORT}"
default_token = "${TOKEN}"
heartbeat_timeout = ${HEARTBEAT_VAL}
retry_interval = 1

[client.transport]
type = "${TRANSPORT}"

[client.transport.${TRANSPORT}]
nodelay = ${NODELAY_STR}
EOF

    # Add services for each port
    IFS=',' read -ra PORTS <<< "$CONFIG_PORTS"
    for port in "${PORTS[@]}"; do
        port=$(echo "$port" | tr -d ' ')
        cat >> "$CONFIG_FILE" << EOF

[client.services.${port}]
local_addr = "${LOCAL_IP}:${port}"
EOF
    done

else
    echo "Error: Invalid tunnel type. Use 'iran' or 'kharej'"
    exit 1
fi

# Create systemd service
cat > "$SERVICE_DIR/${SERVICE_NAME}.service" << EOF
[Unit]
Description=Rathole ${TYPE^} Tunnel on port ${TUNNEL_PORT}
After=network.target

[Service]
Type=simple
ExecStart=${RATHOLE_DIR}/rathole ${CONFIG_FILE}
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# Enable and start service
systemctl daemon-reload
systemctl enable "${SERVICE_NAME}.service"
systemctl start "${SERVICE_NAME}.service"

echo "Tunnel ${TYPE} on port ${TUNNEL_PORT} created successfully!"
exit 0
