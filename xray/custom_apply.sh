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
#
# watashi v12.3.42dev: the rows of the sing-box protocols are rendered into the
# sing-box configs in the same go, and each core restarts only when its own
# rows changed (its rev against the one its guard wrote last), so a new
# Hysteria2 row never restarts xray and a new VLESS row never restarts
# sing-box. sing-box goes through singbox/run.sh, which carries its safety net
# (singbox/custom_guard.sh).
cd /opt/watashi-manager || exit 1
source ./common/utils.sh
activate_python_venv >/dev/null 2>&1

TARGET=/opt/watashi-manager/current.json
PENDING=/opt/watashi-manager/log/custom_inbounds.pending
STATUS=/opt/watashi-manager/log/custom_inbounds.status
STATUS_SB=/opt/watashi-manager/log/custom_inbounds_singbox.status  # watashi v12.3.42dev
# --retry: the inbounds the last apply took out are rendered and judged again
RETRY=0
[ "$1" == "--retry" ] && RETRY=1

fetch() { # fetch file: the panel's configuration, as reload_all_configs gets it
    if watashi-http-api admin/all-configs/ >"$1" 2>/dev/null && jq -e '.users' "$1" >/dev/null 2>&1; then
        return 0
    fi
    watashi-panel-cli all-configs >"$1" 2>/dev/null && jq -e '.users' "$1" >/dev/null 2>&1
}

held_by_other() { # held_by_other unit core: the other core holds a port of the new rows of this core
    # watashi v12.3.42dev
    local pid port file=xray/configs/05_inbounds_90_custom.json key=.port
    [ "$2" == singbox ] && file=singbox/configs/05_inbounds_90_custom.json && key=.listen_port
    command -v ss >/dev/null 2>&1 || return 1
    pid=$(systemctl show -p MainPID --value "$1" 2>/dev/null)
    [[ $pid =~ ^[1-9][0-9]*$ ]] || return 1
    for port in $(jq -r "(.inbounds // [])[] | $key // empty" "$file" 2>/dev/null); do
        [[ $port =~ ^[0-9]+$ ]] || continue
        ss -Htulnp "sport = :$port" 2>/dev/null | grep -q "pid=$pid," && return 0
    done
    return 1
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
        # watashi v12.3.42dev: only the core that took rows out goes again
        for st in "$STATUS" "$STATUS_SB"; do
            [ -s "$st" ] || continue
            [ "$(jq -r '(.rejected // []) | length' "$st" 2>/dev/null)" == "0" ] && continue
            if jq '.rev = "" | .rejected = [] | .rejected_tags = [] | .state = "ok"' "$st" >"$st.tmp" 2>/dev/null; then
                mv -f "$st.tmp" "$st"
                chmod 644 "$st"
            fi
            rm -f "$st.tmp"
        done
        RETRY=0
        done_rev=""
    fi
    if ! fetch "$fresh"; then
        echo "watashi: the panel returned no usable configuration, nothing was changed"
        exit 1
    fi
    want=$(jq -r '.custom_inbounds_rev // ""' "$fresh")
    # watashi v12.3.42dev: and the rev of the sing-box rows; a round carries both
    want_sb=$(jq -r '.custom_inbounds_rev_singbox // ""' "$fresh")
    # a save that landed while the last round read the panel is in that round already
    if [ "$round" -gt 1 ] && [ "$want/$want_sb" == "$done_rev" ]; then
        echo "watashi: round $round has nothing new, the last round carried it"
        break
    fi
    echo "watashi: applying the hand built inbounds (round $round, xray rev ${want:-none}, sing-box rev ${want_sb:-none})"
    # written beside the real file and moved over it, so it is never half written
    merged=$(mktemp /opt/watashi-manager/.current.XXXXXX) || exit 1
    if ! jq --slurpfile f "$fresh" \
        '.users = $f[0].users | .custom_inbounds = ($f[0].custom_inbounds // []) | .custom_inbounds_rev = ($f[0].custom_inbounds_rev // "")
         | .custom_inbounds_rev_singbox = ($f[0].custom_inbounds_rev_singbox // "")' \
        "$TARGET" >"$merged" || ! jq -e '.users' "$merged" >/dev/null 2>&1; then
        echo "watashi: $TARGET could not be updated, nothing was changed"
        exit 1
    fi
    chmod 600 "$merged"
    mv -f "$merged" "$TARGET" || exit 1
    # watashi v12.3.42dev: the xray and the sing-box configs, nothing else
    python common/jinja.py custom
    # a core goes again only when its rows are not what its guard applied last
    do_xray=0
    do_sb=0
    [ "$want" != "$(jq -r '.rev // ""' "$STATUS" 2>/dev/null)" ] && do_xray=1
    [ "$want_sb" != "$(jq -r '.rev // ""' "$STATUS_SB" 2>/dev/null)" ] && do_sb=1
    if [ "$round" == 1 ] && [ "$do_xray" == 0 ] && [ "$do_sb" == 0 ]; then
        # nothing new on either side: Apply now was pressed, so every core
        # that serves such rows goes again, as it always did
        [ -n "$want" ] && do_xray=1
        [ -n "$want_sb" ] && do_sb=1
    fi
    # A row that moved from one core to the other on the same port is still
    # held by the core it left, so that core goes first.
    first=xray
    if [ "$do_xray" == 1 ] && [ "$do_sb" == 1 ] && held_by_other watashi-singbox.service xray; then
        first=singbox
    fi
    for core in $first $([ "$first" == xray ] && echo singbox || echo xray); do
        if [ "$core" == xray ] && [ "$do_xray" == 1 ]; then
            echo "watashi: xray takes the new rows"
            (cd xray && MODE=custom bash run.sh)
        elif [ "$core" == singbox ] && [ "$do_sb" == 1 ]; then
            echo "watashi: sing-box takes the new rows"
            (cd singbox && MODE=custom bash run.sh)
        fi
    done
    bash xray/custom_ports.sh --reserve
    done_rev="$want/$want_sb"
    # another save came in while this ran: one more round for it
    if [ -e "$PENDING" ] || { fetch "$fresh" && [ "$(jq -r '"\(.custom_inbounds_rev // "")/\(.custom_inbounds_rev_singbox // "")"' "$fresh")" != "$done_rev" ]; }; then
        [ "$round" -lt 20 ] && continue
        rm -f "$PENDING"
        echo "watashi: the inbounds kept changing during 20 rounds; press Apply now on the Inbounds page when the changes are done"
    fi
    break
done
echo "watashi: done, the state is in log/custom_inbounds.status and log/custom_inbounds_singbox.status"
cat /opt/watashi-manager/log/custom_inbounds.status 2>/dev/null
echo
cat /opt/watashi-manager/log/custom_inbounds_singbox.status 2>/dev/null  # watashi v12.3.42dev
echo
exit 0
