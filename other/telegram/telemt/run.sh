#!/bin/bash
# telemt runner - watashi v12.2.53
cd "$(dirname "$0")" || exit 1

tm_log() { echo "telemt: $*" >&2; }

# Nothing else may hold 127.0.0.1:1001 while we bind it.
systemctl stop mtproxy.service 2>/dev/null || true
systemctl disable mtproxy.service 2>/dev/null || true

if [[ ! -x ./telemt ]]; then
    tm_log "the binary is missing, installing first"
    bash install.sh || exit 2
fi

if [[ ! -f ./telemt.toml ]]; then
    tm_log "telemt.toml was never rendered from telemt.toml.j2"
    exit 3
fi

if ! grep -Eq '^watashi = "[0-9a-f]{32}"' ./telemt.toml; then
    tm_log "the secret in telemt.toml is not 32 hex characters - refusing to start"
    exit 4
fi

mkdir -p /opt/hiddify-manager/log/system
mkdir -p /var/lib/telemt/tlsfront
chmod 644 telemt.toml
mkdir -p /etc/systemd/system
ln -sf "$(pwd)/telemt.service" /etc/systemd/system/telemt.service
systemctl daemon-reload
systemctl enable telemt.service >/dev/null 2>&1
systemctl restart telemt.service

sleep 3
if systemctl is-active --quiet telemt.service; then
    tm_log "up on 127.0.0.1:1001, haproxy sends the fake TLS sni here"
    if grep -q '^ad_tag' ./telemt.toml; then
        tm_log "ad tag is set, so this engine talks through telegram middle proxies"
    fi
    exit 0
fi

tm_log "telemt did not come up. the last lines of its own log:"
tail -n 20 /opt/hiddify-manager/log/system/telegram.err.log >&2 2>/dev/null
exit 5
