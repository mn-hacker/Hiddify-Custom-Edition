#!/bin/bash
cd $( dirname -- "$0"; )

# Stop existing service gracefully
systemctl stop mtproxy.service 2>/dev/null || true

# Link service file
ln -sf $(pwd)/mtproxy.service /etc/systemd/system/mtproxy.service

# Reload systemd daemon
systemctl daemon-reload

# Set permissions
chmod 700 tgproxy_run.sh* 2>/dev/null || true

# Enable and start service
systemctl enable mtproxy.service
systemctl start mtproxy.service

# Wait for service to start
sleep 2

# Show status
systemctl status mtproxy --no-pager