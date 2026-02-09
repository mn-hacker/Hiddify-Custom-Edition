#!/bin/bash
source /opt/hiddify-manager/common/package_manager.sh

echo "Telegram MTProxy (mtg) install.sh $*"

# Stop and disable existing services
systemctl stop mtproxy.service 2>/dev/null || true
systemctl disable mtproxy.service 2>/dev/null || true

cd "$(dirname "$0")"

# Download mtg binary
echo "Downloading mtg binary..."
download_package mtproxygo mtg-linux.tar.gz
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to download mtg package"
    exit 1
fi

# Extract binary
tar -xf mtg-linux.tar.gz || { echo "ERROR: Failed to extract mtg archive"; exit 1; }
rm -rf mtg-linux

# Find and move mtg binary
if [ -d "mtg"* ]; then
    mv mtg*/mtg mtg 2>/dev/null || mv mtg-*/mtg mtg 2>/dev/null || { echo "ERROR: Could not find mtg binary in archive"; exit 1; }
    rm -rf mtg-* 2>/dev/null
elif [ ! -f "mtg" ]; then
    echo "ERROR: mtg binary not found after extraction"
    exit 1
fi

# Make executable
chmod +x mtg

# Verify binary works
if ./mtg --version >/dev/null 2>&1; then
    echo "MTProxy (mtg) installed successfully!"
    ./mtg --version
    set_installed_version mtproxygo
else
    echo "ERROR: mtg binary is not working properly"
    exit 1
fi

# Create logs directory
mkdir -p /opt/hiddify-manager/log/system

echo "Installation complete. Run 'bash run.sh' to start the service."
