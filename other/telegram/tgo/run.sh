#!/bin/bash
cd $( dirname -- "$0"; )

# Stop existing service gracefully
systemctl stop mtproxy.service 2>/dev/null || true

# Check if mtg binary exists
if [ ! -x "$(pwd)/mtg" ]; then
    echo "ERROR: mtg binary not found or not executable at $(pwd)/mtg"
    echo "Please run install.sh first"
    exit 1
fi

# Check if config file exists
if [ ! -f "$(pwd)/mtg.toml" ]; then
    echo "ERROR: mtg.toml config file not found"
    exit 1
fi

# Link service file
ln -sf $(pwd)/mtproxy.service /etc/systemd/system/mtproxy.service

# Reload systemd daemon to recognize changes
systemctl daemon-reload

# Set proper permissions for config
chmod 600 *toml* 2>/dev/null || true

# Enable and start the service
systemctl enable mtproxy.service
systemctl start mtproxy.service

# Wait for service to fully start
sleep 3

# Show status
if systemctl is-active --quiet mtproxy.service; then
    echo "MTProxy (mtg) started successfully!"
    systemctl status mtproxy --no-pager
else
    echo "MTProxy failed to start. Check logs at /opt/hiddify-manager/log/system/telegram.err.log"
    cat /opt/hiddify-manager/log/system/telegram.err.log 2>/dev/null | tail -20
    exit 1
fi