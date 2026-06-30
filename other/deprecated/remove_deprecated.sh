#!/bin/bash
# Remove deprecated components from Hiddify Manager
# This script is called during installation to clean up old/unused services

echo "Cleaning up deprecated components..."

# Remove ookla speedtest repo (causes 404 errors on Ubuntu 24.04)
rm -f /etc/apt/sources.list.d/ookla_speedtest-cli.list 2>/dev/null
rm -f /etc/apt/sources.list.d/speedtest*.list 2>/dev/null

# ShadowTLS
systemctl stop --now shadowtls >/dev/null 2>&1
systemctl disable shadowtls >/dev/null 2>&1
rm -rf /opt/hiddify-manager/other/shadowtls/

# sniproxy (replaced by HAProxy)
systemctl stop --now hiddify-sniproxy >/dev/null 2>&1
systemctl disable hiddify-sniproxy >/dev/null 2>&1
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

# IP-Limiter (replaced by HWID limit)
systemctl stop --now hiddify-ip-limiter >/dev/null 2>&1
systemctl disable hiddify-ip-limiter >/dev/null 2>&1
rm -f /etc/systemd/system/hiddify-ip-limiter.service
rm -rf /opt/hiddify-manager/other/hiddify-ip-limiter/

echo "Deprecated components cleanup completed."