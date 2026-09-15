#!/bin/bash
# watashi: warp v12.2.128.1
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

# The trace through the panel's own proxy is the only real evidence, so it
# is taken first and every later line is allowed to rely on it.
function warp_trace() {
    curl -s -x "$PROXY" --connect-timeout 5 https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null
}

# Only the lines the engine printed since it was last started. Counting
# the whole journal would report failures from before a fix was applied.
function failures_since_start() {
    local since
    since=$(systemctl show -p ActiveEnterTimestamp --value hiddify-warp.service 2>/dev/null)
    if [ -n "$since" ]; then
        journalctl -u hiddify-warp.service --since "$since" --no-pager 2>/dev/null |
            grep -c 'connection test failed'
    else
        echo 0
    fi
}

function main() {
    warning "- WARP Status:"
    local trace
    trace=$(warp_trace)

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
        # A running service is not proof of a working tunnel, so the engine's
        # readiness loop is reported too. But it is only worth mentioning
        # when the trace ALSO fails: with warp=on the loop is just noise
        # from the seconds before the tunnel settled.
        local tf
        if ! grep -qE '^warp=(on|plus)' <<<"$trace"; then
            tf=$(failures_since_start)
            if [ "${tf:-0}" -gt 10 ]; then
                error "      but its readiness check is failing ($tf times since it started)."
                error "      Try a plain http address by IP for TEST_URL in engine.conf,"
                error "      for example http://1.1.1.1 , and SCAN=0 if it still fails."
            fi
        fi
    else
        error "  - Service: NOT running"
        journalctl -u hiddify-warp.service -n 15 --no-pager 2>/dev/null | sed 's|^|      |'
    fi

    warning "  - Network:"
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
