#!/bin/bash
# watashi v12.2.130: warp-plus launcher for hiddify-warp.service
#
# This script is what the systemd unit actually runs (ExecStart).
# run.sh builds engine.args (one argument per line) and then calls
# "systemctl restart hiddify-warp.service", which brings us here.
# We read those args and exec the binary in place of this shell so
# systemd tracks the right PID and the unit stops cleanly.

cd /opt/hiddify-manager/other/warp/warpplus || exit 1

ARGS_FILE="engine.args"

if [ ! -f "$ARGS_FILE" ]; then
    echo "warp: engine.args not found — run.sh must run before the service starts." >&2
    exit 1
fi

if [ ! -x "./warp-plus" ]; then
    echo "warp: ./warp-plus is missing or not executable." >&2
    exit 1
fi

# Read one argument per line into an array.
# mapfile preserves spaces inside argument values correctly.
mapfile -t ARGS < "$ARGS_FILE"

# exec replaces this shell with warp-plus, so systemd owns the right PID.
exec ./warp-plus "${ARGS[@]}"
