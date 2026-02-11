#!/bin/bash

cd /opt/hiddify-manager/other/telegram/tgo || exit

echo "Fixing permissions..."

# 1. Change file permission to be world-readable (needed for DynamicUser)
chmod 644 mtg.toml

# 2. Patch run.sh to avoid resetting it to 600
sed -i 's/chmod 600/chmod 644/g' run.sh

# 3. Restart service
systemctl restart mtproxy.service

echo "Verifying status..."
sleep 3
systemctl status mtproxy.service --no-pager
