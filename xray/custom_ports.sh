#!/bin/bash
# watashi v12.3.41dev: the firewall holes of the hand built inbounds (advanced mode).
#
# The port of every inbound that serves is opened. The port of one that stopped
# serving is closed again, but only a port this script opened itself before,
# and never one the panel's own configs use. With --reserve the ports are also
# taken out of the ephemeral range, the same way common/run.sh does it for the
# panel's own ports (a full apply adds them to its list there).
source /opt/watashi-manager/common/utils.sh >/dev/null 2>&1
STATE=/opt/watashi-manager/log/custom_inbound_ports.last
CUR=/opt/watashi-manager/current.json
command -v jq >/dev/null 2>&1 || exit 0
[ -s "$CUR" ] || exit 0

want=$(jq -r '(.custom_inbounds // [])[] | select(.active) | .port as $p | (.firewall // "tcp") | split(",")[] | select(. == "tcp" or . == "udp") | "\(.) \($p)"' "$CUR" 2>/dev/null | sort -u)
old=$(grep -E '^(tcp|udp) [0-9]+$' "$STATE" 2>/dev/null | sort -u)
# the ports of the panel itself, which this script never closes
ours=$(jq -r '
    [ (.chconfigs["0"] // {}) | to_entries[] | select((.key | test("_ports?$")) and (.key | test("transport") | not)) | .value | tostring | split(",")[] ]
    + [ (.domains // [])[] | to_entries[] | select(.key | startswith("internal_port_")) | .value | tostring ]
    | .[] | select(test("^[0-9]+$"))' "$CUR" 2>/dev/null | sort -u)

while read -r proto port; do
    [ -n "$port" ] || continue
    allow_port "$proto" "$port"
done <<<"$want"

while read -r proto port; do
    [ -n "$port" ] || continue
    grep -qx "$proto $port" <<<"$want" && continue
    case " 22 53 80 443 $(echo $ours) " in *" $port "*) continue ;; esac
    deny_port "$proto" "$port"
done <<<"$old"

mkdir -p "$(dirname "$STATE")"
printf '%s\n' "$want" | grep -E '^(tcp|udp) [0-9]+$' >"$STATE"

if [ "$1" == "--reserve" ]; then
    # the list the kernel has now, without the ports this script reserved last
    # time, plus the ones it serves now
    list=$(sysctl -n net.ipv4.ip_local_reserved_ports 2>/dev/null | tr ',' '\n' | while read -r piece; do
        case "$piece" in
        *-*) seq "${piece%-*}" "${piece#*-}" ;;
        '') ;;
        *) echo "$piece" ;;
        esac
    done)
    drop=$(awk '{print $2}' <<<"$old" | sort -u)
    keep=$(printf '%s\n' $list | grep -vxF -f <(printf '%s\n' $drop) 2>/dev/null)
    [ -n "$drop" ] || keep=$list
    WS_RESERVED="$(echo $keep) $(awk '{print $2}' <<<"$want" | sort -u | tr '\n' ' ')"
    export WS_RESERVED
    ws_reserve_ports
fi

save_firewall
exit 0
