#!/bin/bash
# watashi: warp v12.2.127
#
# Everything an operator needs to judge WARP in one screen, written to the
# manager log folder so the menu's log viewer shows it like every other log.

cd "$(dirname -- "$0")" || exit 1
source /opt/hiddify-manager/common/utils.sh

BIN="./warp-plus"
PORT=3000
PROXY="socks5h://127.0.0.1:$PORT"
CONF="engine.conf"
LOGDIR="${WS_LOG_DIR:-/opt/hiddify-manager/log/system}"

function main() {
    warning "- WARP Status:"

    if [ -x "$BIN" ]; then
        success "  - Engine: warp-plus $("$BIN" version 2>&1 | tr -d ' ' | head -n 1)"
    else
        error "  - Engine: not installed"
    fi

    if [ -f "$CONF" ]; then
        warning "  - Settings:"
        grep -vE '^\s*#|^\s*$' "$CONF" | sed 's|^|      |'
    fi

    if systemctl is-active --quiet hiddify-warp.service; then
        success "  - Service: running"
    else
        error "  - Service: NOT running"
        journalctl -u hiddify-warp.service -n 15 --no-pager 2>/dev/null | sed 's|^|      |'
    fi

    warning "  - Network:"
    local trace
    trace=$(curl -s -x "$PROXY" --connect-timeout 5 https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null)
    if grep -qE '^warp=(on|plus)' <<<"$trace"; then
        success "      WARP is working"
        grep -E '^(warp|colo|loc|ip)=' <<<"$trace" | sed 's|^|      |'
    else
        error "      WARP is not answering on socks5://127.0.0.1:$PORT"
    fi
    curl -s -x "$PROXY" --connect-timeout 5 "http://ip-api.com/json?fields=country,city,org,query" 2>/dev/null | sed 's|^|      |'
    echo
}

mkdir -p "$LOGDIR"
main |& tee "$LOGDIR/warp.log"
