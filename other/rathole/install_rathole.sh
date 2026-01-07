#!/bin/bash

# Rathole Core Installer
# This script installs the rathole binary for tunnel management

set -e

RATHOLE_DIR="/opt/hiddify-manager/other/rathole"
RATHOLE_URL="https://github.com/Musixal/rathole-tunnel/raw/main/core/rathole.zip"

echo "Installing Rathole..."

# Create directory
mkdir -p "$RATHOLE_DIR"

# Create temp directory
TMP_DIR="/tmp/rathole_install"
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

# Download
echo "Downloading rathole..."
cd "$TMP_DIR"
wget -q "$RATHOLE_URL" -O rathole.zip

# Extract
echo "Extracting..."
unzip -o rathole.zip

# Find and copy rathole binary
if [ -f "$TMP_DIR/rathole" ]; then
    cp "$TMP_DIR/rathole" "$RATHOLE_DIR/rathole"
    chmod +x "$RATHOLE_DIR/rathole"
    echo "Rathole installed successfully!"
else
    echo "Error: rathole binary not found in archive"
    exit 1
fi

# Cleanup
rm -rf "$TMP_DIR"

# Verify
if [ -x "$RATHOLE_DIR/rathole" ]; then
    echo "Verification passed!"
    exit 0
else
    echo "Error: Installation verification failed"
    exit 1
fi
