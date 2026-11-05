#!/bin/bash
# watashi v12.3.40dev: the old project name was taken out of this file (names, paths and links only)
# watashi v12.3.33dev: this file is the one from v12.2.130.49, put back exactly as
# it was. Everything done to WARP after that version was repair work on a
# remembered cloudflare address, and it made the node slower and less
# reliable than the thing it was repairing. The only feature lost with it is
# forcing the exit to IPv4 or IPv6, which warp-plus cannot do anyway: its -4
# only picks the address it dials, and the tunnel behind it always carries
# both families.
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
source /opt/watashi-manager/common/utils.sh

BIN="./warp-plus"
PORT=3000
PROXY="socks5h://127.0.0.1:$PORT"
CACHE="cache"
CONF="engine.conf"
# watashi v12.2.130v: the address the engine last left through, remembered so
# that a restart lands on the same one. Empty or missing simply means
# "nothing remembered yet", which is exactly the old behaviour.
PIN="$CACHE/.watashi-endpoint"
LOGDIR="${WS_LOG_DIR:-/opt/watashi-manager/log/system}"
LOG="$LOGDIR/warp.log"
WAIT=${WS_WARP_WAIT:-40}
mkdir -p "$LOGDIR" "$CACHE"

# watashi v12.2.129: the Nodes page writes warp_mode into the database
# and then asks for the node to come up at once. current.json, which is
# what hconfig reads, is only rewritten when the settings are applied,
# so without this door the page would switch the node on and run.sh
# would immediately switch it back off from a stale value.
if [[ "${WS_WARP_FORCE:-0}" != "1" && "$(hconfig warp_mode disable)" == "disable" ]]; then
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
        echo "# DNS_MODE: which DNS server warp-plus uses for resolving domains."
        echo "# cloudflare=1.1.1.1 (default, through warp), google=8.8.8.8,"
        echo "# system=server default resolver."
        echo "DNS_MODE=cloudflare"
        echo "# TEST_URL is how the engine decides it is ready. It is fetched"
        echo "# through the tunnel in its first seconds, when a TLS handshake"
        echo "# is often still too slow, so a plain HTTP address by IP is used."
        echo "# Measured: an https address here never lets the proxy open."
        echo "TEST_URL=http://1.1.1.1"
        echo "# ── watchdog tunables ────────────────────────────────────────"
        echo "# WS_WD_INTERVAL: seconds between healthchecks (default 300 = 5 min)."
        echo "WS_WD_INTERVAL=300"
        echo "# WS_WD_THRESHOLD: failed checks before rotating the endpoint (default 2)."
        echo "WS_WD_THRESHOLD=2"
        echo "# WS_WD_GRACE: seconds to wait after start before first check (default 60)."
        echo "WS_WD_GRACE=60"
    } >"$CONF"
    chmod 600 "$CONF" 2>/dev/null
fi

MODE=warp
COUNTRY=AT
IPV=auto
SCAN=1
DNS=1.1.1.1
DNS_MODE=cloudflare
TEST_URL=http://1.1.1.1
WS_WD_INTERVAL=300
WS_WD_THRESHOLD=2
WS_WD_GRACE=60
source "$CONF"

# watashi v12.3.33dev: Smart DNS — DNS_MODE drives the actual --dns argument.
# cloudflare = 1.1.1.1 (through warp), google = 8.8.8.8, system = server default.
case "${DNS_MODE:-cloudflare}" in
    cloudflare) DNS="1.1.1.1" ;;
    google)     DNS="8.8.8.8" ;;
    system)     DNS=$(grep -m1 '^nameserver' /etc/resolv.conf 2>/dev/null | awk '{print $2}' || echo "1.1.1.1") ;;
    *)          DNS="${DNS:-1.1.1.1}" ;;
esac
# Export so watchdog.sh can read them from engine.conf directly
export WS_WD_INTERVAL WS_WD_THRESHOLD WS_WD_GRACE

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
# watashi v12.2.130v: an address is only ever used again if it still looks like
# an address. Anything else is treated as nothing remembered.
function ws_endpoint_ok() {
    grep -qE '^(([0-9]{1,3}\.){3}[0-9]{1,3}|\[[0-9a-fA-F:]+\]):[0-9]{1,5}$' <<<"${1:-}"
}

# Does this engine take an address at all. An older build that does not
# know --endpoint would refuse to start, so it is asked first and the
# answer decides whether the pin is used.
function ws_engine_takes_endpoint() {
    [ -x "$BIN" ] || return 1
    "$BIN" --help 2>&1 | grep -q -- "--endpoint"
}

# Prints the remembered address, or nothing. cfon leaves through psiphon,
# where the cloudflare address means nothing, so that mode never pins.
function ws_pinned_endpoint() {
    local ep
    [ "$MODE" = "cfon" ] && return 1
    [ "${WS_WARP_NEW_IP:-0}" = "1" ] && return 1
    ep=$(head -n 1 "$PIN" 2>/dev/null | tr -d '[:space:]')
    ws_endpoint_ok "$ep" || return 1
    ws_engine_takes_endpoint || return 1
    printf '%s\n' "$ep"
}

# After a tunnel really carried traffic, write down the address it used so
# the next start can ask for the same one. If the engine never named it,
# nothing is written and nothing changes.
function ws_remember_endpoint() {
    local ep
    [ "$MODE" = "cfon" ] && return 0
    ws_engine_takes_endpoint || return 0
    ep=$(head -n 1 "$PIN" 2>/dev/null | tr -d '[:space:]')
    ws_endpoint_ok "$ep" && return 0
    ep=$(journalctl -u watashi-warp.service -n 200 --no-pager 2>/dev/null |
        grep -oE '(([0-9]{1,3}\.){3}[0-9]{1,3}|\[[0-9a-fA-F:]+\]):(2408|500|1701|4500|854|880|939|1002|1010|1014|1018|1070|1180|1387|1843|2371|2506|3138|3476|3581|3854|4177|4198|4233|5279|5956|7103|7152|7156|7281|7559|8319|8742|8854|8886)' |
        tail -n 1)
    ws_endpoint_ok "$ep" || return 0
    mkdir -p "$CACHE"
    printf '%s\n' "$ep" >"$PIN"
    chmod 600 "$PIN" 2>/dev/null
}

# watashi v12.2.130v: the file it writes is an argument now, so the new list can
# be built beside the live one and compared with it before anything is
# restarted. With no argument it behaves exactly as it always did.
function build_args() {
    local key out="${1:-engine.args}"
    : >"$out"
    {
        echo "-b"
        echo "127.0.0.1:$PORT"
        echo "--cache-dir"
        echo "$(pwd)/$CACHE"
        echo "--dns"
        echo "${DNS:-1.1.1.1}"
        echo "--test-url"
        echo "${TEST_URL:-http://1.1.1.1}"
    } >>"$out"
    case "$IPV" in
    4) echo "-4" >>"$out" ;;
    6) echo "-6" >>"$out" ;;
    esac
    # watashi v12.2.130v: a remembered address replaces the scan, because the
    # scan is the thing that hands out a different exit IP every time the
    # engine starts. If the engine of this machine does not understand
    # --endpoint, or nothing is remembered, the scan is used exactly as
    # before, so the worst case is the behaviour of the previous version.
    if ws_pinned_endpoint >/dev/null; then
        echo "--endpoint" >>"$out"
        ws_pinned_endpoint >>"$out"
    elif [ "$SCAN" == "1" ]; then
        echo "--scan" >>"$out"
    fi
    case "$MODE" in
    gool)
        echo "--gool" >>"$out"
        ;;
    cfon)
        echo "--cfon" >>"$out"
        echo "--country" >>"$out"
        echo "${COUNTRY:-AT}" >>"$out"
        ;;
    esac
    # watashi v12.2.130: hconfig reads current.json which is only
    # regenerated on apply_configs. After a restore the database has
    # the right key but current.json is still stale. ws_after_restore()
    # writes the sidecar warp-key.conf so the engine inherits the
    # correct key without waiting for the next apply.
    key=$(hconfig warp_plus_code)
    if [ -z "$key" ] || [ "$key" = "-" ]; then
        sidecar="$(pwd)/warp-key.conf"
        if [ -f "$sidecar" ]; then
            key=$(head -1 "$sidecar" 2>/dev/null | tr -d '[:space:]')
            [ -n "$key" ] && echo "- WARP: key loaded from post-restore sidecar." >&2
        fi
    fi
    if [ -n "$key" ] && [ "$key" != "-" ]; then
        echo "-k" >>"$out"
        echo "$key" >>"$out"
    fi
    chmod 600 "$out" 2>/dev/null
}

# The only honest test: real traffic through the proxy the panel will use.
# The engine's own opinion is not trusted here, because it was measured
# saying nothing at all while the tunnel underneath was already up.
WS_TRACE=
# watashi v12.2.129.2: readiness used to mean one thing only - cloudflare
# answering warp=on. That is right for the warp and gool modes, where the exit
# IS cloudflare. In cfon mode the exit is a psiphon server, so cloudflare
# correctly answers warp=off and a healthy node was declared dead. Here the
# question is the honest one: does the proxy carry traffic at all.
function warp_trace() {
    WS_TRACE=$(curl -s -x "$PROXY" --connect-timeout 5 https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null)
    if [ "$MODE" = "cfon" ]; then
        grep -qE '^ip=[^[:space:]]+' <<<"$WS_TRACE"
    else
        grep -qE '^warp=(on|plus)' <<<"$WS_TRACE"
    fi
}

# Whatever the engine printed. This is the part the old version threw away.
function engine_log() {
    journalctl -u watashi-warp.service -n "${1:-20}" --no-pager 2>/dev/null | sed 's|^|    |'
}

function explain_failure() {
    local j
    j=$(journalctl -u watashi-warp.service -n 80 --no-pager 2>/dev/null)
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

# watashi v12.2.130v: one restart and the wait that goes with it.
function ws_start_and_wait() {
    local i
    systemctl restart watashi-warp.service 2>&1 | sed 's|^|    |'
    for i in $(seq 1 "$WAIT"); do
        if warp_trace; then
            return 0
        fi
        if ! systemctl is-active --quiet watashi-warp.service; then
            # no point waiting on a service that already gave up
            sleep 2
            systemctl is-active --quiet watashi-warp.service || break
        fi
        sleep 1
    done
    return 1
}

# watashi v12.2.130v: the engine used to be restarted on every apply, every
# update and every settings save, and a restart with --scan comes back
# through a different cloudflare address, so an operator who had found a
# good exit IP lost it to work that had nothing to do with WARP. A running
# engine whose argument list has not changed, and which is carrying
# traffic right now, is now left exactly where it is.
function ws_can_leave_alone() {
    local started binary
    [ "${WS_WARP_NEW_IP:-0}" = "1" ] && return 1
    [ -f engine.args ] || return 1
    cmp -s engine.args.new engine.args || return 1
    systemctl is-active --quiet watashi-warp.service || return 1
    # a freshly installed binary must be picked up, so the running service
    # has to be younger than the file it runs.
    started=$(date -d "$(systemctl show -p ActiveEnterTimestamp --value watashi-warp.service 2>/dev/null)" +%s 2>/dev/null)
    binary=$(stat -c %Y "$BIN" 2>/dev/null)
    if [[ "$started" =~ ^[0-9]+$ && "$binary" =~ ^[0-9]+$ && "$binary" -gt "$started" ]]; then
        return 1
    fi
    warp_trace
}


# watashi v12.2.130: cache housekeeping.
# warp-plus accumulates registration blobs in its cache directory. On a server
# that has been running for months the cache can reach hundreds of MB. Keep only
# the most recent files; the engine re-registers on the next start if it needs
# anything that was pruned.
function ws_prune_cache() {
    local max_files=20  # keep at most this many files per type
    local cache_dir="$(pwd)/$CACHE"
    [ -d "$cache_dir" ] || return 0
    # prune .bin and .json files independently, keeping the newest ones
    for ext in bin json; do
        local files_to_remove
        files_to_remove=$(find "$cache_dir" -maxdepth 1 -name "*.${ext}" -type f             | sort -t/ -k1 | head -n -${max_files})
        if [ -n "$files_to_remove" ]; then
            echo "$files_to_remove" | xargs rm -f 2>/dev/null
        fi
    done
}

function bring_up() {
    ws_prune_cache  # keep the cache dir from growing into RAM
    build_args engine.args.new
    if ws_can_leave_alone; then
        rm -f engine.args.new
        echo "- Nothing about the node changed, so it keeps running and keeps its address."
        ws_remember_endpoint
        return 0
    fi
    mv -f engine.args.new engine.args
    chmod 600 engine.args 2>/dev/null
    if ws_start_and_wait; then
        ws_remember_endpoint
        return 0
    fi
    # The remembered address is never allowed to be the reason WARP is
    # down: if the start that used it failed, it is thrown away and the
    # engine is given one more chance to find an address by itself.
    if ws_pinned_endpoint >/dev/null; then
        warning "- The address the node used last time did not answer, looking for another one."
        rm -f "$PIN"
        build_args engine.args
        chmod 600 engine.args 2>/dev/null
        if ws_start_and_wait; then
            ws_remember_endpoint
            return 0
        fi
    fi
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
        if [ "$MODE" = "cfon" ]; then
            success "- The node is working on socks5://127.0.0.1:$PORT (psiphon exit, so warp=off is expected)"
        else
            success "- WARP is working on socks5://127.0.0.1:$PORT"
        fi
        grep -E '^(warp|ip|colo|loc)=' <<<"$WS_TRACE" | sed 's|^|    |'
        curl -s -x "$PROXY" --connect-timeout 5 "http://ip-api.com/json?fields=country,city,org,query" 2>/dev/null | sed 's|^|    |'
        echo
        return 0
    fi

    error "- The node is NOT working. The panel will keep serving traffic directly."
    explain_failure
    echo "  Last lines from the engine:"
    engine_log 20
    return 1
}

mkdir -p "$LOGDIR"
main "$@" |& tee -a "$LOG"
exit "${PIPESTATUS[0]}"
