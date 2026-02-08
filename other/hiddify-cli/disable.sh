#!/bin/bash
# Disable hiddify-cli service
# NOTE: We only STOP the service, not disable it permanently
# This allows it to be re-enabled easily when needed

cd "$(dirname "$0")"

# Stop the service if running
systemctl stop hiddify-cli.service > /dev/null 2>&1

# Do NOT use 'systemctl disable' - that prevents the service from starting
# even after re-installation. The service should remain enabled but stopped.

echo "hiddify-cli service stopped"