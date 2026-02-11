#!/bin/bash
cd $( dirname -- "$0"; )

# Stop existing service gracefully
systemctl stop mtproxy.service 2>/dev/null || true

# Link service file
ln -sf $(pwd)/mtproxy.service /etc/systemd/system/mtproxy.service

# Reload systemd daemon to recognize changes
systemctl daemon-reload

# Set proper permissions for config
chmod 600 *toml* 2>/dev/null || true

# Check if binary exists
if [ ! -x "./mtg" ]; then
    echo "ERROR: mtg binary not found or not executable. Attempting to run install.sh..."
    bash install.sh
fi

if [ ! -x "./mtg" ]; then
    echo "CRITICAL: mtg binary still missing after install attempt."
    exit 1
fi

# Enable and start the service
systemctl enable mtproxy.service
systemctl start mtproxy.service

# Wait for service to fully start
sleep 2

# Show status
systemctl status mtproxy --no-pager