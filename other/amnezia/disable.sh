# watashi: the separate AmneziaWG system v12.2.62
#
# runsh() in install.sh calls this file instead of install.sh and run.sh when
# the switch it is given reads false or 0, so this is the whole of "off".

source ./awg_utils.sh

systemctl stop "$AWG_UNIT" >/dev/null 2>&1
systemctl disable "$AWG_UNIT" >/dev/null 2>&1

# The description of the interface is deliberately left on disk. Turning the
# switch back on should not have to rebuild what has not changed, and the file
# holds no user data once the peers are gone with the service.
# watashi v12.2.130u: the interface brings its own iptables rules down with it,
# but the udp port the panel opened around it stayed open, and there is no
# sing-box endpoint behind it any more to answer on that port.
if [ -f /opt/hiddify-manager/common/utils.sh ]; then
    source /opt/hiddify-manager/common/utils.sh >/dev/null 2>&1
    if command -v jq >/dev/null 2>&1 && [ -f /opt/hiddify-manager/current.json ]; then
        ws_awg_port=$(jq -r '.chconfigs["0"].amnezia_port // empty' /opt/hiddify-manager/current.json)
        if [ -n "$ws_awg_port" ] && [ -z "${ws_awg_port//[0-9]/}" ] && command -v ws_allow_del >/dev/null 2>&1; then
            ws_allow_del "udp" "$ws_awg_port"
        fi
    fi
fi

ws_awg_say "amneziawg is off and its port is closed. no other tunnel serves amnezia, so its users have nothing until it is switched back on."
