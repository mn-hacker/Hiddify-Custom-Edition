#!/bin/bash
# watashi: warp v12.2.45
#
# The old version wrote its log to other/warp/singbox/log/system/warp.log,
# a folder nobody ever reads. It now writes to the manager log folder, so the
# menu's log viewer can show it like every other log.

cd "$(dirname -- "$0")" || exit 1
source /opt/hiddify-manager/common/utils.sh

WGCF="./wgcf"
[ -x "$WGCF" ] || WGCF="wgcf"
PORT=3000
PROXY="socks5h://127.0.0.1:$PORT"
LOGDIR="${WS_LOG_DIR:-/opt/hiddify-manager/log/system}"

function main() {
    warning "- WARP Status:"

    if systemctl is-active --quiet hiddify-warp.service; then
        success "  - Service: running"
    else
        error "  - Service: NOT running"
        systemctl status hiddify-warp.service --no-pager 2>/dev/null | head -n 10 | sed 's|^|      |'
    fi

    warning "  - Account:"
    "$WGCF" status 2>/dev/null | sed '/^$/d ; s|^|      |'

    warning "  - Network:"
    local trace
    trace=$(curl -s -x "$PROXY" --connect-timeout 4 https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null)
    if grep -qE '^warp=(on|plus)' <<<"$trace"; then
        success "      WARP is working"
        grep -E '^(warp|colo|loc)=' <<<"$trace" | sed 's|^|      |'
    else
        error "      WARP is not answering on socks5://127.0.0.1:$PORT"
    fi
    curl -s -x "$PROXY" --connect-timeout 4 "http://ip-api.com/json?fields=country,city,org,query" 2>/dev/null | sed 's|^|      |'
    echo
}

mkdir -p "$LOGDIR"
main |& tee "$LOGDIR/warp.log"
