# watashi: the separate AmneziaWG system v12.2.62
# watashi v12.2.130an: the panel could say the unit was running and nothing more.
# Every question that matters when a handshake never arrives is asked
# here, in one file, and the answers land in one log the panel can show.
#
# Nothing is started, stopped or changed. The exit code is always 0,
# because common/commander.py runs this with check=True.

cd "$(dirname "$0")" || exit 0
source ./awg_utils.sh

LOG=/opt/hiddify-manager/log/system/amnezia-status.log
mkdir -p "$(dirname "$LOG")" >/dev/null 2>&1

say() { echo "$*"; echo "$*" >>"$LOG" 2>/dev/null || true; }

: >"$LOG" 2>/dev/null || true
say "amnezia status  $(date "+%Y-%m-%d %H:%M:%S")"
say "interface name: $SERVER_AWG_NIC"
say ""

if ! ws_awg_ready; then
    say "tools:         awg / awg-quick are NOT installed on this machine"
    say "nothing else can be read without them. install amneziawg and amneziawg-tools."
    exit 0
fi
say "tools:         awg and awg-quick are installed"

# --- the unit -------------------------------------------------------
UNIT_STATE="$(systemctl is-active "$AWG_UNIT" 2>/dev/null)"
[ -n "$UNIT_STATE" ] || UNIT_STATE=unknown
say "unit:          $AWG_UNIT is $UNIT_STATE"

# --- the interface --------------------------------------------------
if ip link show "$SERVER_AWG_NIC" >/dev/null 2>&1; then
    say "interface:     up"
    say "addresses:     $(ip -o addr show dev "$SERVER_AWG_NIC" 2>/dev/null | awk "{print \$4}" | tr "\n" " ")"
else
    say "interface:     NOT present"
fi

# --- the port -------------------------------------------------------
PORT="$(awg show "$SERVER_AWG_NIC" listen-port 2>/dev/null)"
if [ -n "$PORT" ]; then
    say "listen port:   $PORT"
    if ss -lunp 2>/dev/null | grep -q ":$PORT "; then
        say "udp socket:    something is listening on udp $PORT"
    else
        say "udp socket:    NOTHING is listening on udp $PORT"
    fi
    if iptables -C INPUT -p udp --dport "$PORT" -j ACCEPT >/dev/null 2>&1; then
        say "iptables:      udp $PORT is accepted"
    else
        say "iptables:      no ACCEPT rule for udp $PORT was found"
    fi
else
    say "listen port:   could not be read, the interface is probably down"
fi

# --- forwarding -----------------------------------------------------
FWD="$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null)"
if [ "$FWD" = "1" ]; then
    say "ip_forward:    on"
else
    say "ip_forward:    OFF, so traffic would not leave this box"
fi

# --- the peers ------------------------------------------------------
say ""
PEERS=0
SEEN=0
while read -r pub handshake; do
    [ -n "$pub" ] || continue
    PEERS=$((PEERS + 1))
    case "$handshake" in
        "" | 0)
            say "peer $pub: never completed a handshake" ;;
        *)
            SEEN=$((SEEN + 1))
            say "peer $pub: last handshake $(( $(date +%s) - handshake )) seconds ago" ;;
    esac
done <<EOF
$(awg show "$SERVER_AWG_NIC" latest-handshakes 2>/dev/null)
EOF

say ""
say "peers loaded:  $PEERS"
say "peers seen:    $SEEN"

# --- the verdict ----------------------------------------------------
say ""
if [ "$PEERS" -gt 0 ] && [ "$SEEN" = "0" ]; then
    say "verdict: the server side is complete and not one packet ever arrived."
    say "this is what a cloud firewall looks like from in here. the machine"
    say "opens the port itself, the provider does not."
    say "on AWS it is the security group, on Oracle the security list, on GCP"
    say "the vpc firewall. each one needs an inbound Custom UDP rule for this"
    say "port, for 0.0.0.0/0 and ::/0."
elif [ "$PEERS" = "0" ]; then
    say "verdict: no peer is loaded at all. no user has an amnezia config yet,"
    say "or apply_configs.sh has not been run since the last change."
else
    say "verdict: handshakes are arriving, the tunnel is alive."
fi

exit 0
