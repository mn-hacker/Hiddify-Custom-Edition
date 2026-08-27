#!/bin/bash
# watashi: warp v12.2.45
#
# Builds the WARP config for sing-box and brings the tunnel up.
#
# Why this file was rewritten: sing-box DELETED the "wireguard" outbound in
# 1.13 (deprecated in 1.11, replaced by a wireguard endpoint). The old config
# generated here still used that outbound, so on a current sing-box the WARP
# service refused to load its config and died in a restart loop. That is why
# WARP "could never be installed" from the panel. We now generate the endpoint
# form, ask sing-box itself which schema it wants, and refuse to restart the
# service with a config that sing-box cannot parse.
#
# The contract with the panel is unchanged: a SOCKS5 proxy on 127.0.0.1:3000,
# which is what xray/singbox configs use as their WARP outbound.

cd "$(dirname -- "$0")" || exit 1
source /opt/hiddify-manager/common/utils.sh

SB="${WS_SB:-/opt/hiddify-manager/singbox/sing-box}"
WGCF="./wgcf"
[ -x "$WGCF" ] || WGCF="wgcf"
CONF="warp-singbox.json"
PROFILE="wgcf-profile.conf"
ACCOUNT="wgcf-account.toml"
PORT=3000
PROXY="socks5h://127.0.0.1:$PORT"

if [[ "$(hconfig warp_mode disable)" == "disable" ]]; then
    warning "- WARP is disabled in the panel."
    bash disable.sh
    exit 0
fi

# --- what schema does this sing-box speak? -----------------------------------
# 1.11 and newer: endpoints. Older: the legacy wireguard outbound.
function sb_wants_endpoint() {
    local v major minor
    v=$("$SB" version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -n 1)
    [ -z "$v" ] && return 0
    major=${v%%.*}
    minor=${v##*.}
    [ "$major" -gt 1 ] && return 0
    [ "$major" -eq 1 ] && [ "$minor" -ge 11 ] && return 0
    return 1
}

# --- account -----------------------------------------------------------------
function register_account() {
    local key name
    [ -f "$ACCOUNT" ] && mv -f "$ACCOUNT" "$ACCOUNT.backup"
    name=$(hostname 2>/dev/null || cat /etc/hostname 2>/dev/null)
    key=$(hconfig warp_plus_code)
    if [ -n "$key" ] && [ "$key" != "-" ]; then
        export WGCF_LICENSE_KEY="$key"
    else
        unset WGCF_LICENSE_KEY
    fi
    echo "- Registering a new WARP account..."
    "$WGCF" register --accept-tos -m watashi -n "${name:-watashi}" >/dev/null 2>&1 || return 1
    # a WARP+ key only takes effect after an update call
    [ -n "$WGCF_LICENSE_KEY" ] && "$WGCF" update >/dev/null 2>&1
    return 0
}

# --- config ------------------------------------------------------------------
function ipv6_usable() {
    if [ -f /proc/sys/net/ipv6/conf/all/disable_ipv6 ] && [ "$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6)" == "1" ]; then
        return 1
    fi
    curl -s --connect-timeout 2 https://v6.ident.me >/dev/null 2>&1
}

function build_config() {
    local priv peer_key endpoint host port v6 addrs
    rm -f "$PROFILE"
    "$WGCF" generate >/dev/null 2>&1 || return 1
    [ -f "$PROFILE" ] || return 1

    priv=$(grep -m1 '^PrivateKey' "$PROFILE" | cut -d= -f2- | tr -d ' ')
    peer_key=$(grep -m1 '^PublicKey' "$PROFILE" | cut -d= -f2- | tr -d ' ')
    endpoint=$(grep -m1 '^Endpoint' "$PROFILE" | cut -d= -f2- | tr -d ' ')
    host=${endpoint%:*}
    port=${endpoint##*:}
    v6=$(grep '^Address' "$PROFILE" | grep ':' | head -n 1 | cut -d= -f2- | tr -d ' ')

    if [ -z "$priv" ] || [ -z "$peer_key" ] || [ -z "$host" ] || [ -z "$port" ]; then
        error "- WARP: the wgcf profile is incomplete, cannot build a config."
        return 1
    fi

    addrs="\"172.16.0.2/32\""
    if [ -n "$v6" ] && ipv6_usable; then
        addrs="$addrs, \"$v6\""
    else
        echo "- No usable IPv6 on this server, WARP will be IPv4 only."
    fi

    if sb_wants_endpoint; then
        cat >"$CONF" <<EOF
{
  "log": { "level": "warn", "timestamp": true },
  "inbounds": [
    {
      "type": "socks",
      "tag": "warp-in",
      "listen": "127.0.0.1",
      "listen_port": $PORT
    }
  ],
  "endpoints": [
    {
      "type": "wireguard",
      "tag": "WARP",
      "system": false,
      "mtu": 1280,
      "address": [ $addrs ],
      "private_key": "$priv",
      "peers": [
        {
          "address": "$host",
          "port": $port,
          "public_key": "$peer_key",
          "allowed_ips": [ "0.0.0.0/0", "::/0" ],
          "persistent_keepalive_interval": 25,
          "reserved": [ 0, 0, 0 ]
        }
      ]
    }
  ],
  "outbounds": [
    { "type": "direct", "tag": "direct" }
  ],
  "route": {
    "final": "WARP",
    "auto_detect_interface": true
  }
}
EOF
    else
        cat >"$CONF" <<EOF
{
  "log": { "level": "warn", "timestamp": true },
  "inbounds": [
    {
      "type": "socks",
      "tag": "warp-in",
      "listen": "127.0.0.1",
      "listen_port": $PORT
    }
  ],
  "outbounds": [
    {
      "type": "wireguard",
      "tag": "WARP",
      "server": "$host",
      "server_port": $port,
      "local_address": [ $addrs ],
      "private_key": "$priv",
      "peer_public_key": "$peer_key",
      "reserved": [ 0, 0, 0 ],
      "mtu": 1280
    },
    { "type": "direct", "tag": "direct" }
  ],
  "route": {
    "final": "WARP",
    "auto_detect_interface": true
  }
}
EOF
    fi

    # never hand systemd a config the core cannot read
    if ! "$SB" check -c "$CONF" >/dev/null 2>&1; then
        error "- WARP: sing-box rejected the generated config."
        "$SB" check -c "$CONF" 2>&1 | head -n 5 | sed 's|^|    |'
        return 1
    fi
    return 0
}

# --- proof that it really works ----------------------------------------------
function warp_trace() {
    curl -s -x "$PROXY" --connect-timeout 5 https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null | grep -qE '^warp=(on|plus)'
}

function bring_up() {
    build_config || return 1
    systemctl restart hiddify-warp.service
    local i
    for i in $(seq 1 15); do
        if warp_trace; then
            return 0
        fi
        sleep 1
    done
    return 1
}

function main() {
    [ -f "$ACCOUNT" ] || register_account || warning "- WARP registration failed on the first try."

    if ! bring_up; then
        warning "- WARP did not answer, registering a fresh account and retrying..."
        if ! (register_account && bring_up); then
            error "- WARP is NOT working. The panel will keep serving traffic directly."
            systemctl status hiddify-warp.service --no-pager 2>/dev/null | head -n 8 | sed 's|^|    |'
            return 1
        fi
    fi

    success "- WARP is working on socks5://127.0.0.1:$PORT"
    curl -s -x "$PROXY" --connect-timeout 4 "http://ip-api.com/json?fields=country,city,org,query" 2>/dev/null | sed 's|^|    |'
    echo
    return 0
}

main "$@"
