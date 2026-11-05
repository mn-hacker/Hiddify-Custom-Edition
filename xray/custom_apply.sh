#!/bin/bash
# watashi v12.3.41dev: puts the hand built inbounds of the Inbounds page
# (advanced mode) on the server without a full apply.
#
# Only what these inbounds need is taken from the panel: the inbound rows and
# the user list. Every other setting stays exactly as the last full apply left
# it, so a setting the owner changed but did not apply yet cannot sneak onto
# the server through this door. Then the xray configs alone are rendered,
# xray restarts through run.sh (which carries the safety net,
# xray/custom_guard.sh) and the firewall follows (xray/custom_ports.sh).
# A save that arrives while this runs is picked up by one more round.
cd /opt/watashi-manager || exit 1
source ./common/utils.sh
activate_python_venv >/dev/null 2>&1

TARGET=/opt/watashi-manager/current.json
PENDING=/opt/watashi-manager/log/custom_inbounds.pending
STATUS=/opt/watashi-manager/log/custom_inbounds.status
# --retry: the inbounds the last apply took out are rendered and judged again
RETRY=0
[ "$1" == "--retry" ] && RETRY=1

fetch() { # fetch file: the panel's configuration, as reload_all_configs gets it
    if watashi-http-api admin/all-configs/ >"$1" 2>/dev/null && jq -e '.users' "$1" >/dev/null 2>&1; then
        return 0
    fi
    watashi-panel-cli all-configs >"$1" 2>/dev/null && jq -e '.users' "$1" >/dev/null 2>&1
}

[ -s "$TARGET" ] || { echo "watashi: $TARGET is missing, run a full apply first"; exit 1; }
fresh=$(mktemp /tmp/watashi-custom.XXXXXX) || exit 1
merged=""
trap 'rm -f "$fresh" $merged' EXIT

# watashi v12.3.41dev: as many rounds as the saves keep coming, with a cap so
# a panel that never settles cannot keep xray restarting for ever
round=0
done_rev=""
while :; do
    round=$((round + 1))
    # saves that come in a row share one restart of xray
    [ "$round" -gt 1 ] && sleep 1
    grep -qx retry "$PENDING" 2>/dev/null && RETRY=1
    rm -f "$PENDING"
    if [ "$RETRY" == 1 ]; then
        # the panel leaves out what the last apply of this very set took out;
        # an emptied list lets those rows in again, and the safety net judges
        # them once more (xray/custom_guard.sh)
        if [ -s "$STATUS" ] && jq '.rev = "" | .rejected = [] | .rejected_tags = [] | .state = "ok"' "$STATUS" >"$STATUS.tmp" 2>/dev/null; then
            mv -f "$STATUS.tmp" "$STATUS"
            chmod 644 "$STATUS"
        fi
        rm -f "$STATUS.tmp"
        RETRY=0
        done_rev=""
    fi
    if ! fetch "$fresh"; then
        echo "watashi: the panel returned no usable configuration, nothing was changed"
        exit 1
    fi
    want=$(jq -r '.custom_inbounds_rev // ""' "$fresh")
    # a save that landed while the last round read the panel is in that round already
    if [ "$round" -gt 1 ] && [ "$want" == "$done_rev" ]; then
        echo "watashi: round $round has nothing new, the last round carried it"
        break
    fi
    echo "watashi: applying the hand built inbounds (round $round, rev ${want:-none})"
    # written beside the real file and moved over it, so it is never half written
    merged=$(mktemp /opt/watashi-manager/.current.XXXXXX) || exit 1
    if ! jq --slurpfile f "$fresh" \
        '.users = $f[0].users | .custom_inbounds = ($f[0].custom_inbounds // []) | .custom_inbounds_rev = ($f[0].custom_inbounds_rev // "")' \
        "$TARGET" >"$merged" || ! jq -e '.users' "$merged" >/dev/null 2>&1; then
        echo "watashi: $TARGET could not be updated, nothing was changed"
        exit 1
    fi
    chmod 600 "$merged"
    mv -f "$merged" "$TARGET" || exit 1
    python common/jinja.py xray
    (cd xray && MODE=custom bash run.sh)
    bash xray/custom_ports.sh --reserve
    done_rev=$want
    # another save came in while this ran: one more round for it
    if [ -e "$PENDING" ] || { fetch "$fresh" && [ "$(jq -r '.custom_inbounds_rev // ""' "$fresh")" != "$want" ]; }; then
        [ "$round" -lt 20 ] && continue
        rm -f "$PENDING"
        echo "watashi: the inbounds kept changing during 20 rounds; press Apply now on the Inbounds page when the changes are done"
    fi
    break
done
echo "watashi: done, the state is in log/custom_inbounds.status"
cat /opt/watashi-manager/log/custom_inbounds.status 2>/dev/null
echo
exit 0
