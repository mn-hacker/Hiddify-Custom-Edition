#!/bin/bash
# watashi: warp v12.2.126
#
# The command systemd runs. It only reads engine.args, one argument per line,
# which run.sh renders from the panel settings. The service therefore never
# needs the panel database at boot time: if the database is not ready yet,
# the engine still starts with the last known settings.

cd "$(dirname -- "$0")" || exit 1

ARGS=()
if [ -f engine.args ]; then
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        case "$line" in
        "#"*) continue ;;
        esac
        ARGS+=("$line")
    done <engine.args
fi

if [ ${#ARGS[@]} -eq 0 ]; then
    # a safe default that still honours the panel contract: socks on 3000
    ARGS=("-b" "127.0.0.1:3000" "--cache-dir" "/opt/hiddify-manager/other/warp/warpplus/cache")
fi

exec ./warp-plus "${ARGS[@]}"
