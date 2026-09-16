#!/bin/bash
# watashi: node v12.2.129
#
# The one root door the Nodes page has.
#
# Reading WARP state and changing it both need root: engine.conf is chmod 600
# and owned by root, and systemctl is not something the panel user may call.
# So the panel asks common/commander.py, which validates its own input again
# and lands here. Nothing on this side trusts what it was handed.
#
# Three of the four write actions take longer than a web request may wait
# (run.sh alone waits for the tunnel to answer), so they are started in the
# background by the panel and leave a job file behind. The page then polls
# "show" until the job is gone, which is what draws the spinner on the card.

cd "$(dirname -- "$0")" || exit 1
source /opt/hiddify-manager/common/utils.sh

BIN="./warp-plus"
PORT=3000
PROXY="socks5h://127.0.0.1:$PORT"
CONF="engine.conf"
UNIT="hiddify-warp.service"
JOB="node.job"
JOBLOG="node.job.log"
NODE_KEYS="MODE COUNTRY IPV SCAN DNS TEST_URL"
# The countries warp-plus accepts for --cfon. Anything else makes the engine
# exit at once, which would look like a broken node.
NODE_COUNTRIES="AT AU BE BG CA CH CZ DE DK EE ES FI FR GB HR HU IE IN IT JP LV NL NO PL PT RO RS SE SG SK US"

# ---------------------------------------------------------------- json bits
function jesc() {
    sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr -d '\r\n'
}

function jkv() {
    printf '"%s":"%s"' "$1" "$(printf '%s' "$2" | jesc)"
}

# ---------------------------------------------------------------- job file
# line 1 = action, line 2 = pid, line 3 = unix time it started
function job_running() {
    [ -f "$JOB" ] || return 1
    local pid
    pid=$(sed -n '2p' "$JOB" 2>/dev/null)
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

function job_action() {
    job_running || return 1
    sed -n '1p' "$JOB" 2>/dev/null
}

function job_start() {
    if job_running; then
        echo "- Another node job ($(job_action)) is still running."
        return 1
    fi
    printf '%s\n%s\n%s\n' "$1" "$$" "$(date +%s)" >"$JOB"
    chmod 600 "$JOB" 2>/dev/null
    trap 'rm -f "$JOB"' EXIT
    return 0
}

# ---------------------------------------------------------------- reading
function engine_version() {
    [ -x "$BIN" ] || return 0
    "$BIN" version 2>&1 | tr -d ' ' | head -n 1
}

function unit_state() {
    local state
    state=$(systemctl is-active "$UNIT" 2>/dev/null)
    case "$state" in
    active | activating | failed | inactive) echo "$state" ;;
    *) systemctl list-unit-files "$UNIT" >/dev/null 2>&1 && echo "inactive" || echo "absent" ;;
    esac
}

function conf_json() {
    local key value first=1
    printf '{'
    for key in $NODE_KEYS; do
        value=$(grep -E "^${key}=" "$CONF" 2>/dev/null | tail -n 1 | cut -d= -f2- | tr -d '"' | tr -d "'")
        [ $first -eq 1 ] || printf ','
        first=0
        jkv "$key" "$value"
    done
    printf '}'
}

function show() {
    local trace="" warp="" ip="" colo="" loc="" org="" city="" geo=""
    if systemctl is-active --quiet "$UNIT"; then
        trace=$(curl -s -x "$PROXY" --connect-timeout 5 https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null)
        warp=$(grep -E '^warp=' <<<"$trace" | cut -d= -f2)
        ip=$(grep -E '^ip=' <<<"$trace" | cut -d= -f2)
        colo=$(grep -E '^colo=' <<<"$trace" | cut -d= -f2)
        loc=$(grep -E '^loc=' <<<"$trace" | cut -d= -f2)
        if [ -n "$ip" ]; then
            geo=$(curl -s -x "$PROXY" --connect-timeout 5 "http://ip-api.com/json?fields=country,city,org" 2>/dev/null)
            org=$(jq -r '.org // empty' <<<"$geo" 2>/dev/null)
            city=$(jq -r '.city // empty' <<<"$geo" 2>/dev/null)
        fi
    fi
    printf '{'
    jkv name warp
    printf ','
    jkv engine "$(engine_version)"
    printf ','
    jkv installed "$([ -x "$BIN" ] && echo yes || echo no)"
    printf ','
    jkv state "$(unit_state)"
    printf ','
    jkv enabled "$(systemctl is-enabled "$UNIT" 2>/dev/null)"
    printf ','
    jkv panel_mode "$(hconfig warp_mode disable)"
    printf ','
    jkv warp "$warp"
    printf ','
    jkv ip "$ip"
    printf ','
    jkv colo "$colo"
    printf ','
    jkv loc "$loc"
    printf ','
    jkv org "$org"
    printf ','
    jkv city "$city"
    printf ','
    jkv job "$(job_action)"
    printf ','
    jkv job_log "$(tail -n 3 "$JOBLOG" 2>/dev/null | tr '\n' ' ' | sed -e 's/\x1b\[[0-9;]*m//g')"
    printf ','
    printf '"settings":%s' "$(conf_json)"
    printf '}\n'
}

# ---------------------------------------------------------------- writing
function set_key() {
    local key="$1" value="$2"
    case " $NODE_KEYS " in
    *" $key "*) ;;
    *)
        echo "- $key is not a node setting."
        return 1
        ;;
    esac
    case "$key" in
    MODE)
        case "$value" in
        warp | gool | cfon) ;;
        *)
            echo "- MODE must be warp, gool or cfon."
            return 1
            ;;
        esac
        ;;
    COUNTRY)
        case " $NODE_COUNTRIES " in
        *" $value "*) ;;
        *)
            echo "- $value is not a country the engine can use."
            return 1
            ;;
        esac
        ;;
    IPV)
        case "$value" in
        auto | 4 | 6) ;;
        *)
            echo "- IPV must be auto, 4 or 6."
            return 1
            ;;
        esac
        ;;
    SCAN)
        case "$value" in
        0 | 1) ;;
        *)
            echo "- SCAN must be 0 or 1."
            return 1
            ;;
        esac
        ;;
    DNS)
        if ! grep -qE '^[0-9a-fA-F:.]{3,45}$' <<<"$value"; then
            echo "- DNS must be an IP address."
            return 1
        fi
        ;;
    TEST_URL)
        # Measured in round 128: an https address here never lets the proxy
        # open, so the only thing accepted is a plain http one.
        if ! grep -qE '^http://[A-Za-z0-9._~:/?#@!$&()*+,;=%-]{3,120}$' <<<"$value"; then
            echo "- TEST_URL must be a plain http address, for example http://1.1.1.1"
            return 1
        fi
        ;;
    esac
    [ -f "$CONF" ] || {
        echo "- The engine has no settings file yet, run.sh writes it."
        return 1
    }
    # In place, so a comment an operator wrote stays where it was.
    if grep -qE "^${key}=" "$CONF"; then
        sed -i -E "s|^${key}=.*|${key}=${value}|" "$CONF"
    else
        echo "${key}=${value}" >>"$CONF"
    fi
    chmod 600 "$CONF" 2>/dev/null
    echo "- $key is now $value"
}

function turn_on() {
    job_start on || return 1
    {
        echo "- Turning the WARP node on."
        systemctl enable "$UNIT" 2>&1 | sed 's|^|    |'
        WS_WARP_FORCE=1 WS_WARP_WAIT="${WS_WARP_WAIT:-30}" bash run.sh
    } >"$JOBLOG" 2>&1
    local rc=$?
    cat "$JOBLOG"
    return $rc
}

function turn_off() {
    job_start off || return 1
    bash disable.sh >"$JOBLOG" 2>&1
    local rc=$?
    cat "$JOBLOG"
    return $rc
}

function change_ip() {
    job_start change-ip || return 1
    WS_WARP_WAIT="${WS_WARP_WAIT:-20}" bash change_ip.sh >"$JOBLOG" 2>&1
    local rc=$?
    cat "$JOBLOG"
    return $rc
}

case "$1" in
show) show ;;
on) turn_on ;;
off) turn_off ;;
change-ip) change_ip ;;
set) set_key "$2" "$3" ;;
*)
    echo "usage: node.sh show|on|off|change-ip|set KEY VALUE"
    exit 1
    ;;
esac
