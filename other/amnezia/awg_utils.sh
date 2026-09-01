# watashi: the separate AmneziaWG system v12.2.62
#
# AmneziaWG is run by its own daemon here, not inside the sing-box core. The
# core is meant to come from its own upstream repository one day, and upstream
# sing-box has no "awg" endpoint type at all, so this tunnel has to be able to
# stand on its own feet.
#
# Nothing in this file starts or stops anything. It only names things, so that
# install.sh, run.sh and disable.sh can never drift apart on a path or a unit.

SERVER_AWG_NIC=watashi-awg
AWG_DIR=/etc/amnezia/amneziawg
AWG_CONF="$AWG_DIR/$SERVER_AWG_NIC.conf"
AWG_UNIT="awg-quick@$SERVER_AWG_NIC"
AWG_LOG=/opt/hiddify-manager/log/system/amnezia.log

# awg-quick keeps wg-quick's rule for interface names:
#     ^[a-zA-Z0-9_=+.-]{1,15}$
# "watashi-awg" is 11 characters and the dash is inside that set, so the name
# is also safe as a systemd instance in awg-quick@watashi-awg.service, where
# systemd hands it to the unit as %i without touching the dash.
ws_awg_name_ok() {
    printf '%s' "$SERVER_AWG_NIC" | grep -Eq '^[a-zA-Z0-9_=+.-]{1,15}$'
}

# amneziawg-tools installs both "awg" and "awg-quick". A userspace build
# answers to the same two names once it is on the path, so one test covers
# either way of getting it onto the machine.
ws_awg_ready() {
    command -v awg >/dev/null 2>&1 && command -v awg-quick >/dev/null 2>&1
}

# H1..H4 are the four packet type numbers AmneziaWG writes instead of the ones
# WireGuard uses. Plain WireGuard uses 1, 2, 3 and 4, so any value below 5
# leaves the packet header exactly as recognisable as it was.
ws_awg_headers_disguised() {
    local h
    for h in "$1" "$2" "$3" "$4"; do
        case "$h" in
            '' | *[!0-9]*) return 1 ;;
        esac
        [ "$h" -ge 5 ] || return 1
    done
}

ws_awg_say() {
    echo "amnezia: $*"
    mkdir -p "$(dirname "$AWG_LOG")" >/dev/null 2>&1
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >>"$AWG_LOG" 2>/dev/null || true
}
