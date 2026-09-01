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
ws_awg_say "the separate amneziawg system is off. while it is off, the sing-box endpoint keeps serving amnezia exactly as before."
