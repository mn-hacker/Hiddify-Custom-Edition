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
tar -xf mtg-linux.tar.gz || exit 1
# remove old dir if exists
rm -rf mtg-linux
# find the directory extracted
DIR=$(ls -d mtg-*/ 2>/dev/null || ls -d mtg*/ 2>/dev/null | head -n 1)
if [ -z "$DIR" ]; then
    echo "ERROR: Could not find extracted directory for mtg"
    ls -l
    exit 1
fi
mv "$DIR/mtg" mtg || { echo "ERROR: mtg binary not found in $DIR"; exit 2; }
set_installed_version mtproxygo
# export GOPATH=/opt/hiddify-manager/other/telegram/tgo/go/
# export GOCACHE=/opt/hiddify-manager/other/telegram/tgo/gocache/
# git clone https://github.com/9seconds/mtg/



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
