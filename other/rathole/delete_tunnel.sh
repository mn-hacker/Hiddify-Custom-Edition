#!/bin/bash
# watashi v12.3.40dev: the old project name was taken out of this file (names, paths and links only)

# Rathole Tunnel Deleter
# Deletes tunnel configuration and systemd service files
# Usage: delete_tunnel.sh <type> <tunnel_port>
# Example: delete_tunnel.sh kharej 8080

set -e

RATHOLE_DIR="/opt/watashi-manager/other/rathole"
SERVICE_DIR="/etc/systemd/system"

TYPE="$1"
TUNNEL_PORT="$2"

if [ -z "$TYPE" ] || [ -z "$TUNNEL_PORT" ]; then
    echo "Error: Usage: delete_tunnel.sh <type> <tunnel_port>"
    exit 1
fi

SERVICE_NAME="rathole-${TYPE}${TUNNEL_PORT}"
CONFIG_FILE="$RATHOLE_DIR/${TYPE}${TUNNEL_PORT}.toml"
SERVICE_FILE="$SERVICE_DIR/${SERVICE_NAME}.service"

echo "Deleting tunnel ${TYPE} on port ${TUNNEL_PORT}..."

# Stop and disable service
if [ -f "$SERVICE_FILE" ]; then
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    systemctl disable "$SERVICE_NAME" 2>/dev/null || true
    rm -f "$SERVICE_FILE"
    echo "Service removed."
fi

# Reload systemd
systemctl daemon-reload 2>/dev/null || true

# Remove config file
if [ -f "$CONFIG_FILE" ]; then
    rm -f "$CONFIG_FILE"
    echo "Config removed."
fi

echo "Tunnel ${TYPE} on port ${TUNNEL_PORT} deleted successfully!"
exit 0
