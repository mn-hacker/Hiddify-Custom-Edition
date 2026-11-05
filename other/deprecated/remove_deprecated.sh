#!/bin/bash
# Remove deprecated components from Watashi Manager
# watashi v12.3.40dev: the old-name units (sniproxy, ip-limiter) are cleaned by common/watashi_legacy.sh now
# This script is called during installation to clean up old/unused services

echo "Cleaning up deprecated components..."

# Remove ookla speedtest repo (causes 404 errors on Ubuntu 24.04)
rm -f /etc/apt/sources.list.d/ookla_speedtest-cli.list 2>/dev/null
rm -f /etc/apt/sources.list.d/speedtest*.list 2>/dev/null

# ShadowTLS
systemctl stop --now shadowtls >/dev/null 2>&1
systemctl disable shadowtls >/dev/null 2>&1
rm -rf /opt/watashi-manager/other/shadowtls/

# sniproxy (replaced by HAProxy)
pkill -9 sniproxy >/dev/null 2>&1

# Trojan-go (replaced by Xray trojan)
systemctl stop --now trojan-go >/dev/null 2>&1
systemctl disable trojan-go >/dev/null 2>&1

# Caddy (replaced by Nginx)
systemctl stop --now caddy >/dev/null 2>&1
systemctl disable caddy >/dev/null 2>&1

# Clash server
systemctl stop --now clash >/dev/null 2>&1
systemctl disable clash >/dev/null 2>&1

# Monitoring/Netdata
systemctl stop --now netdata >/dev/null 2>&1
systemctl disable netdata >/dev/null 2>&1

echo "Deprecated components cleanup completed."