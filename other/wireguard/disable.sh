source ./wg_utils.sh

systemctl stop "wg-quick@${SERVER_WG_NIC}"
systemctl disable "wg-quick@${SERVER_WG_NIC}"

# watashi v12.2.130am: stopping the unit does not remove an interface that was
# brought up by hand or survived a failed stop, and while it is there it
# still holds its address. Switching wireguard off in the panel has to
# actually take the interface away.
if ip link show "${SERVER_WG_NIC}" >/dev/null 2>&1; then
    wg-quick down "${SERVER_WG_NIC}" >/dev/null 2>&1 || ip link del "${SERVER_WG_NIC}" >/dev/null 2>&1
fi
