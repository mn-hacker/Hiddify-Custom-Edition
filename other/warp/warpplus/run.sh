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
# watashi v12.2.130v: the address the engine last left through, remembered so
# that a restart lands on the same one. Empty or missing simply means
# "nothing remembered yet", which is exactly the old behaviour.
PIN="$CACHE/.watashi-endpoint"
LOGDIR="${WS_LOG_DIR:-/opt/hiddify-manager/log/system}"
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
        echo "# It decides two things: which cloudflare address the engine dials,"
        echo "# and, after the configuration is applied, the family the traffic"
        echo "# leaves the tunnel on. Apply once after changing it."
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
# watashi v12.2.130bg: everything that remembered a cloudflare address used to live
# here - ws_endpoint_ok, ws_endpoint_family, ws_endpoint_family_ok,
# ws_engine_takes_endpoint, ws_pinned_endpoint, ws_endpoint_from_log,
# ws_remember_endpoint and the port pattern they shared.
#
# The idea was to keep the same exit IP across an apply. What it cost was a
# start on an address that may have died since, the wait that goes with it,
# and a second start behind it - which is the whole of "it got slow and it
# gets stuck". Two things replaced it and are better at the job:
# ws_can_leave_alone, which does not restart a healthy node at all, and
# v12.2.130bf, which lets the core decide the family instead of trying to
# steer it by picking a cloudflare address.
#
# An old pin file left over from those versions is deleted on sight, so a
# server that upgrades into this does not keep one lying in its cache.
rm -f "$PIN" 2>/dev/null

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
    # watashi v12.2.130bg: what the engine is asked for is the family, and then
    # either a scan or nothing. There is no third possibility any more.
    if [ "${WS_WARP_NO_SCAN:-0}" = "1" ]; then
        # watashi v12.2.130be: no --scan and no --endpoint means the engine takes one
        # random warp address of the family that was asked for
        # (cmd/warp-plus/rootcmd.go, "If the endpoint is not set"). No
        # probing, no minute long search: it either answers or it does not.
        # This is the last thing tried when the scan cannot finish, and on a
        # server where UDP to cloudflare is throttled it is what works.
        :
    elif [ "$SCAN" == "1" ] || [ "${WS_WARP_NEW_IP:-0}" = "1" ]; then
        # watashi v12.2.130be: asking for a new IP means asking for a different
        # cloudflare edge, and the scan is the only thing that picks one. It
        # is switched on for that one run even when SCAN is off, otherwise
        # the button on the Nodes page has nothing to work with.
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
    key=$(hconfig warp_plus_code)
    if [ -n "$key" ] && [ "$key" != "-" ]; then
        echo "-k" >>"$out"
        echo "$key" >>"$out"
    fi
    chmod 600 "$out" 2>/dev/null
}

# watashi v12.2.130bf: how the node is measured, in the family it was set to.
#
# -4 on the engine picks the cloudflare address it dials and nothing else:
# the tunnel always carries a v4 and a v6 address, so a name handed to it as
# a name is answered AAAA first and the reply says IPv6 - on a node the
# operator set to IPv4. Asking curl to resolve the name out here, in the
# chosen family, hands the tunnel a literal address, which is exactly what
# xray and sing-box do for user traffic once domainStrategy is set. The
# report then shows what the node really does instead of flattering it.
function ws_proxy_args() {
    case "$IPV" in
    4) echo "-4 -x socks5://127.0.0.1:$PORT" ;;
    6) echo "-6 -x socks5://127.0.0.1:$PORT" ;;
    *) echo "-x $PROXY" ;;
    esac
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
    WS_TRACE=$(curl -s $(ws_proxy_args) --connect-timeout 5 https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null)
    if [ "$MODE" = "cfon" ]; then
        grep -qE '^ip=[^[:space:]]+' <<<"$WS_TRACE"
    else
        grep -qE '^warp=(on|plus)' <<<"$WS_TRACE"
    fi
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
    elif grep -qi 'user canceled the operation' <<<"$j"; then
        error "- The endpoint scan did not find two reachable WARP addresses"
        error "  inside the one minute it allows itself, so the engine gave up."
        error "  UDP to cloudflare is throttled or blocked on this server."
        error "  IPV=auto in engine.conf lets it try IPv6 as well, and SCAN=0"
        error "  makes it take one address directly instead of searching."
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

# watashi v12.2.130be: how long one start is given, read off the arguments it was
# given. The scanner of warp-plus 1.2.6 allows itself a full minute
# (wiresocks/scanner.go) and returns only after it has found two reachable
# addresses, probing them one at a time. WAIT was 40 seconds, so a scan that
# was still working was called dead at second forty - on every apply, and
# the more the family filter narrows the search the more often it happened.
function ws_wait_for() {
    local args="${1:-engine.args}" want="$WAIT"
    if grep -qx -- '--scan' "$args" 2>/dev/null; then
        want=75
        [ "$WAIT" -gt 75 ] && want="$WAIT"
    fi
    echo "$want"
}

# watashi v12.2.130v: one restart and the wait that goes with it.
function ws_start_and_wait() {
    local i limit="${1:-$WAIT}"
    systemctl restart hiddify-warp.service 2>&1 | sed 's|^|    |'
    for i in $(seq 1 "$limit"); do
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

# watashi v12.2.130v: the engine used to be restarted on every apply, every
# update and every settings save, and a restart with --scan comes back
# through a different cloudflare address, so an operator who had found a
# good exit IP lost it to work that had nothing to do with WARP. A running
# engine whose argument list has not changed, and which is carrying
# traffic right now, is now left exactly where it is.
# watashi v12.2.130bd: the argument list without the address in it. A remembered
# address is a preference for the next start, not a reason to throw a
# healthy tunnel away - and since it is written down right after a --scan
# start, the freshly built list said --endpoint where the live one still
# said --scan, so every apply restarted the node. That is the opposite of
# what remembering it was for.
function ws_args_body() {
    awk 'skip { skip = 0; next }
         $0 == "--endpoint" { skip = 1; next }
         $0 == "--scan" { next }
         { print }' "$1" 2>/dev/null
}

function ws_can_leave_alone() {
    local started binary
    [ "${WS_WARP_NEW_IP:-0}" = "1" ] && return 1
    # watashi v12.2.130bd: one door for "restart it even though nothing changed",
    # used when the files under the engine changed instead of its arguments.
    [ "${WS_WARP_RESTART:-0}" = "1" ] && return 1
    [ -f engine.args ] || return 1
    [ "$(ws_args_body engine.args.new)" = "$(ws_args_body engine.args)" ] || return 1
    systemctl is-active --quiet hiddify-warp.service || return 1
    # a freshly installed binary must be picked up, so the running service
    # has to be younger than the file it runs.
    started=$(date -d "$(systemctl show -p ActiveEnterTimestamp --value hiddify-warp.service 2>/dev/null)" +%s 2>/dev/null)
    binary=$(stat -c %Y "$BIN" 2>/dev/null)
    if [[ "$started" =~ ^[0-9]+$ && "$binary" =~ ^[0-9]+$ && "$binary" -gt "$started" ]]; then
        return 1
    fi
    warp_trace
}

function bring_up() {
    build_args engine.args.new
    if ws_can_leave_alone; then
        rm -f engine.args.new
        echo "- Nothing about the node changed, so it keeps running and keeps its address."
        return 0
    fi
    mv -f engine.args.new engine.args
    chmod 600 engine.args 2>/dev/null
    if ws_start_and_wait "$(ws_wait_for engine.args)"; then
        return 0
    fi

    # watashi v12.2.130be: the scan needs two reachable addresses inside the one
    # minute it allows itself. Where UDP to cloudflare is throttled it will
    # never have them, and narrowing it to one family only makes that
    # likelier. Without --scan the engine simply takes one random address of
    # the family that was asked for, which needs nothing to succeed first.
    if grep -qx -- '--scan' engine.args 2>/dev/null; then
        warning "- The endpoint scan did not finish in time, trying a single address instead."
        export WS_WARP_NO_SCAN=1
        build_args engine.args
        unset WS_WARP_NO_SCAN
        chmod 600 engine.args 2>/dev/null
        if ws_start_and_wait "$(ws_wait_for engine.args)"; then
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
        curl -s $(ws_proxy_args) --connect-timeout 5 "http://ip-api.com/json?fields=country,city,org,query" 2>/dev/null | sed 's|^|    |'
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
