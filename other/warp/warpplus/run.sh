#!/bin/bash
# watashi: warp v12.2.128
#
# Configures and starts the WARP engine (warp-plus) and proves it really works
# before saying so.
#
# The contract with the panel is unchanged: a SOCKS5 proxy on 127.0.0.1:3000,
# which is what the xray and sing-box routing configs already use as their
# WARP outbound. Nothing outside this folder had to change.
#
# Two things the old wgcf version did wrong and this one does not:
#   1. it hid every error with >/dev/null 2>&1, so the only thing an operator
#      ever saw was "WARP is NOT working".
#   2. it registered a fresh account on every failed attempt, which turns a
#      rate limit into a permanent one. warp-plus keeps its identity in its
#      cache folder and reuses it.

cd "$(dirname -- "$0")" || exit 1
source /opt/hiddify-manager/common/utils.sh

BIN="./warp-plus"
PORT=3000
PROXY="socks5h://127.0.0.1:$PORT"
CACHE="cache"
CONF="engine.conf"
LOGDIR="${WS_LOG_DIR:-/opt/hiddify-manager/log/system}"
LOG="$LOGDIR/warp.log"
WAIT=${WS_WARP_WAIT:-40}
mkdir -p "$LOGDIR" "$CACHE"

if [[ "$(hconfig warp_mode disable)" == "disable" ]]; then
    warning "- WARP is disabled in the panel."
    bash disable.sh
    exit 0
fi

if [ ! -x "$BIN" ]; then
    warning "- The WARP engine is not installed yet, installing it now."
    bash install.sh || exit 1
fi

# engine.conf holds the knobs the Nodes page will drive later. It is written
# once with defaults and never overwritten, so an operator can edit it by hand
# today without losing the change on the next apply.
if [ ! -f "$CONF" ]; then
    {
        echo "# watashi WARP engine settings"
        echo "# MODE: warp = plain WARP, gool = warp in warp, cfon = psiphon"
        echo "MODE=warp"
        echo "# COUNTRY is only used by cfon. Valid: AT AU BE BG CA CH CZ DE DK"
        echo "# EE ES FI FR GB HR HU IE IN IT JP LV NL NO PL PT RO RS SE SG SK US"
        echo "COUNTRY=AT"
        echo "# IPV: auto, 4 or 6. Use 4 if this server has no working IPv6."
        echo "IPV=auto"
        echo "# SCAN=1 lets the engine find a reachable endpoint by itself."
        echo "SCAN=1"
        echo "DNS=1.1.1.1"
        echo "# TEST_URL is how the engine decides it is ready. It is fetched"
        echo "# through the tunnel in its first seconds, when a TLS handshake"
        echo "# is often still too slow, so a plain HTTP address by IP is used."
        echo "# Measured: an https address here never lets the proxy open."
        echo "TEST_URL=http://1.1.1.1"
    } >"$CONF"
    chmod 600 "$CONF" 2>/dev/null
fi

MODE=warp
COUNTRY=AT
IPV=auto
SCAN=1
DNS=1.1.1.1
TEST_URL=http://1.1.1.1
source "$CONF"

# Servers that already have an engine.conf from an earlier round do not
# have TEST_URL in it, and that single missing line is what kept the proxy
# from ever opening. Add it in place, keeping the operator's own edits.
if ! grep -q "^TEST_URL=" "$CONF" 2>/dev/null; then
    echo "# added in v12.2.128: the readiness check must not use https" >>"$CONF"
    echo "TEST_URL=http://1.1.1.1" >>"$CONF"
    TEST_URL=http://1.1.1.1
fi

# One argument per line, because a WARP+ key or a country code must never be
# re-split by the shell inside the systemd unit.
function build_args() {
    local key
    : >engine.args
    {
        echo "-b"
        echo "127.0.0.1:$PORT"
        echo "--cache-dir"
        echo "$(pwd)/$CACHE"
        echo "--dns"
        echo "${DNS:-1.1.1.1}"
        echo "--test-url"
        echo "${TEST_URL:-http://1.1.1.1}"
    } >>engine.args
    case "$IPV" in
    4) echo "-4" >>engine.args ;;
    6) echo "-6" >>engine.args ;;
    esac
    if [ "$SCAN" == "1" ]; then
        echo "--scan" >>engine.args
    fi
    case "$MODE" in
    gool)
        echo "--gool" >>engine.args
        ;;
    cfon)
        echo "--cfon" >>engine.args
        echo "--country" >>engine.args
        echo "${COUNTRY:-AT}" >>engine.args
        ;;
    esac
    key=$(hconfig warp_plus_code)
    if [ -n "$key" ] && [ "$key" != "-" ]; then
        echo "-k" >>engine.args
        echo "$key" >>engine.args
    fi
    chmod 600 engine.args 2>/dev/null
}

# The only honest test: real traffic through the proxy the panel will use.
# The engine's own opinion is not trusted here, because it was measured
# saying nothing at all while the tunnel underneath was already up.
WS_TRACE=
function warp_trace() {
    WS_TRACE=$(curl -s -x "$PROXY" --connect-timeout 5 https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null)
    grep -qE '^warp=(on|plus)' <<<"$WS_TRACE"
}

# Whatever the engine printed. This is the part the old version threw away.
function engine_log() {
    journalctl -u hiddify-warp.service -n "${1:-20}" --no-pager 2>/dev/null | sed 's|^|    |'
}

function explain_failure() {
    local j
    j=$(journalctl -u hiddify-warp.service -n 80 --no-pager 2>/dev/null)
    if grep -q '429' <<<"$j"; then
        error "- Cloudflare answered 429 (too many requests) to this server IP."
        error "  Registrations from this IP are rate limited. Wait and try again,"
        error "  or put a working WARP key in the panel settings."
    elif grep -qi 'context deadline\|timeout\|i/o timeout' <<<"$j"; then
        error "- The engine could not reach any WARP endpoint (timeout)."
        error "  Set IPV=4 in engine.conf if this server has no IPv6, or keep SCAN=1."
    elif grep -qi 'connection test failed' <<<"$j"; then
        error "- The tunnel came up but the engine readiness check failed."
        error "  TEST_URL in engine.conf must be a plain http address by IP,"
        error "  for example http://1.1.1.1 . An https address is too slow in"
        error "  the first seconds of a fresh tunnel and never passes."
    elif grep -qi 'permission denied' <<<"$j"; then
        error "- The engine was not allowed to write its cache folder."
    fi
}

function bring_up() {
    local i
    build_args
    systemctl restart hiddify-warp.service 2>&1 | sed 's|^|    |'
    for i in $(seq 1 "$WAIT"); do
        if warp_trace; then
            return 0
        fi
        if ! systemctl is-active --quiet hiddify-warp.service; then
            # no point waiting on a service that already gave up
            sleep 2
            systemctl is-active --quiet hiddify-warp.service || break
        fi
        sleep 1
    done
    return 1
}

# warp-plus prints its version on stderr, so both streams are read.
function engine_version() {
    [ -x "$BIN" ] || { echo "not installed"; return 0; }
    local v
    v=$("$BIN" version 2>&1 | tr -d ' ' | head -n 1)
    echo "${v:-unknown version}"
}

function main() {
    echo "- WARP engine: $(engine_version), mode $MODE, ip version $IPV"
    if bring_up; then
        success "- WARP is working on socks5://127.0.0.1:$PORT"
        grep -E '^(warp|ip|colo|loc)=' <<<"$WS_TRACE" | sed 's|^|    |'
        curl -s -x "$PROXY" --connect-timeout 5 "http://ip-api.com/json?fields=country,city,org,query" 2>/dev/null | sed 's|^|    |'
        echo
        return 0
    fi

    error "- WARP is NOT working. The panel will keep serving traffic directly."
    explain_failure
    echo "  Last lines from the engine:"
    engine_log 20
    return 1
}

mkdir -p "$LOGDIR"
main "$@" |& tee -a "$LOG"
exit "${PIPESTATUS[0]}"
