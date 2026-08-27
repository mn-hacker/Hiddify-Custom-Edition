# watashi v12.2.53: every unit name this folder has ever installed.
for unit in mtproxy mtproto-proxy telemt; do
    systemctl stop "$unit" >/dev/null 2>&1
    systemctl disable "$unit" >/dev/null 2>&1
done
exit 0
