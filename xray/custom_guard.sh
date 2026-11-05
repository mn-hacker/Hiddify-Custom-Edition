#!/bin/bash
# watashi v12.3.41dev: the safety net of the hand built inbounds (advanced mode).
#
#   pre   xray/run.sh, before xray restarts: every inbound of the custom file is
#         tried on its own, then the whole config directory is tried, and
#         whatever xray would refuse is taken out of the custom file
#   boot  pre-start.sh, before every start of xray (an apply, a reboot, a crash):
#         the two things that break between applies, a certificate that is gone
#         and a port another program took, are checked without starting xray
#   post  xray/run.sh, after xray restarted: when xray does not come up, the
#         inbound it names is taken out, or all of them, and xray starts again
#
# What was taken out and why goes to log/custom_inbounds.status, which the
# Inbounds page reads. The panel then leaves those inbounds out of the next
# render and out of the subscriptions until the owner changes them, so one bad
# inbound can never keep the panel's own inbounds from starting.
# No file of the panel's own inbounds is ever touched here.

DIR=/opt/watashi-manager/xray
CUSTOM=$DIR/configs/05_inbounds_90_custom.json
STATUS=/opt/watashi-manager/log/custom_inbounds.status
KEEP=/opt/watashi-manager/log/custom_inbounds.rejected.json
CUR=/opt/watashi-manager/current.json
XRAY=$DIR/bin/xray
SSL_RE='^/opt/watashi-manager/ssl/[A-Za-z0-9._-]+$'

command -v jq >/dev/null 2>&1 || exit 0

count() { jq -r '(.inbounds // []) | length' "$CUSTOM" 2>/dev/null || echo 0; }
tags() { jq -r '(.inbounds // [])[] | .tag' "$CUSTOM" 2>/dev/null; }
rev_now() { jq -r '.custom_inbounds_rev // ""' "$CUR" 2>/dev/null; }
short() { grep -v '^[[:space:]]*$' | grep -iv 'deprecated' | tail -n 3 | tr '\n' ' ' | cut -c1-500; }

status_begin() { # status_begin stage: a fresh status for this apply
    # The same set as last time was rendered without the inbounds that apply
    # took out (the panel leaves them out while nothing changed), so they are
    # not in the file to be judged again: what was said about them still
    # holds, and forgetting it would put them back into the next render.
    # "Try again" on the Inbounds page clears this on purpose (custom_apply.sh).
    local rev old='[]'
    rev=$(rev_now)
    if [ -n "$rev" ] && [ -s "$STATUS" ] && [ "$(jq -r '.rev // ""' "$STATUS" 2>/dev/null)" == "$rev" ]; then
        old=$(jq -c --argjson here "$(jq -c '[(.inbounds // [])[] | .tag]' "$CUSTOM" 2>/dev/null || echo '[]')" \
            '[(.rejected // [])[] | select(type == "object" and .tag != null) | select(.tag as $t | $here | index($t) | not)]' \
            "$STATUS" 2>/dev/null) || old='[]'
    fi
    jq -n --arg rev "$rev" --arg stage "$1" --argjson t "$(date +%s)" --argjson old "${old:-[]}" \
        '{state: "ok", rev: $rev, stage: $stage, time: $t, rejected: $old, rejected_tags: ($old | map(.tag))}' >"$STATUS.tmp" &&
        mv -f "$STATUS.tmp" "$STATUS"
    chmod 644 "$STATUS" 2>/dev/null
}

status_reject() { # status_reject stage tag reason
    [ -s "$STATUS" ] || status_begin "$1"
    jq --arg stage "$1" --arg tag "$2" --arg why "$3" --argjson t "$(date +%s)" \
        '.stage = $stage | .time = $t
         | .rejected = ((.rejected // []) | map(select(.tag != $tag))) + [{tag: $tag, reason: $why}]
         | .rejected_tags = (.rejected | map(.tag))' "$STATUS" >"$STATUS.tmp" 2>/dev/null &&
        mv -f "$STATUS.tmp" "$STATUS"
    chmod 644 "$STATUS" 2>/dev/null
}

status_finish() { # status_finish: ok, partial or rejected, from what is left in the file
    [ -s "$STATUS" ] || return 0
    jq --argjson left "$(count)" \
        '.state = (if (.rejected | length) == 0 then "ok" elif $left == 0 then "rejected" else "partial" end)' \
        "$STATUS" >"$STATUS.tmp" 2>/dev/null && mv -f "$STATUS.tmp" "$STATUS"
    chmod 644 "$STATUS" 2>/dev/null
}

keep_copy() { # the file as it was rendered, once per apply, for whoever wants to look
    [ -f "$KEEP.$$" ] && return 0
    cp -f "$CUSTOM" "$KEEP" 2>/dev/null && chmod 600 "$KEEP" 2>/dev/null
    : >"$KEEP.$$"
}

write_custom() { # write_custom jq-filter [args...]
    local filter=$1
    shift
    jq "$@" "$filter" "$CUSTOM" >"$CUSTOM.tmp" 2>/dev/null || { rm -f "$CUSTOM.tmp"; return 1; }
    chmod 600 "$CUSTOM.tmp"
    mv -f "$CUSTOM.tmp" "$CUSTOM"
}

drop_tag() { # drop_tag stage tag reason
    keep_copy
    write_custom 'if ((.inbounds // []) | map(select(.tag != $t)) | length) == 0 then {} else .inbounds |= map(select(.tag != $t)) end' --arg t "$2"
    status_reject "$1" "$2" "$3"
    echo "watashi: the inbound $2 was taken out: $3"
}

drop_all() { # drop_all stage reason
    local tag
    keep_copy
    for tag in $(tags); do
        status_reject "$1" "$tag" "$2"
    done
    echo '{}' >"$CUSTOM"
    chmod 600 "$CUSTOM"
    echo "watashi: every hand built inbound was taken out: $2"
}

foreign_listener() { # foreign_listener tcp|udp port: a program other than this xray holds the port
    # Told apart by its process id, not by its name: another panel on the
    # same server (x-ui and the like) runs a binary called xray as well.
    # Before a start (boot) this xray holds nothing, so every listener counts.
    local flag=-Htlnp mine
    [ "$1" == "udp" ] && flag=-Hulnp
    command -v ss >/dev/null 2>&1 || return 1
    mine=$(systemctl show -p MainPID --value watashi-xray.service 2>/dev/null)
    [[ $mine =~ ^[1-9][0-9]*$ ]] || mine=none
    ss $flag "sport = :$2" 2>/dev/null | grep -v "pid=$mine," | grep -q .
}

static_problem() { # static_problem tag: what is wrong without starting xray
    local tag=$1 file port net
    while read -r file; do
        [ -n "$file" ] || continue
        if ! [[ $file =~ $SSL_RE ]]; then
            echo "the certificate $file is not one of the panel's certificates"
            return
        fi
        if [ ! -s "$file" ]; then
            echo "the certificate file $file is missing"
            return
        fi
    done < <(jq -r --arg t "$tag" '.inbounds[] | select(.tag == $t) | .streamSettings.tlsSettings.certificates[]? | .certificateFile, .keyFile' "$CUSTOM" 2>/dev/null)
    if jq -e --arg t "$tag" '.inbounds[] | select(.tag == $t) | [.. | objects | select(has("fallbacks"))] | length > 0' "$CUSTOM" >/dev/null 2>&1; then
        echo "fallbacks are not allowed in a hand built inbound"
        return
    fi
    read -r port net < <(jq -r --arg t "$tag" '.inbounds[] | select(.tag == $t) | "\(.port) \(.settings.network // "tcp")"' "$CUSTOM" 2>/dev/null)
    [[ $port =~ ^[0-9]+$ ]] || { echo "the inbound has no port"; return; }
    if foreign_listener tcp "$port"; then
        echo "another program already listens on $port/tcp: $(ss -Htlnp "sport = :$port" 2>/dev/null | grep -o 'users:(("[^"]*"' | head -1 | cut -d'"' -f2)"
        return
    fi
    if [[ $net == *udp* ]] && foreign_listener udp "$port"; then
        echo "another program already listens on $port/udp: $(ss -Hulnp "sport = :$port" 2>/dev/null | grep -o 'users:(("[^"]*"' | head -1 | cut -d'"' -f2)"
        return
    fi
}

alone_problem() { # alone_problem tag: what xray says about this one inbound by itself
    local tag=$1 tmp out
    tmp=$(mktemp -d) || return 0
    echo '{"log": {"loglevel": "none"}, "outbounds": [{"protocol": "freedom", "tag": "freedom"}]}' >"$tmp/00_base.json"
    jq --arg t "$tag" '{inbounds: [.inbounds[] | select(.tag == $t)]}' "$CUSTOM" >"$tmp/10_one.json" 2>/dev/null
    if ! out=$("$XRAY" run -test -confdir "$tmp" 2>&1); then
        echo "$out" | short
    fi
    rm -rf "$tmp"
}

ports_up() { # every inbound left in the file listens, and it is this xray that listens
    local port net mine
    mine=$(systemctl show -p MainPID --value watashi-xray.service 2>/dev/null)
    [[ $mine =~ ^[1-9][0-9]*$ ]] || return 1
    while read -r port net; do
        [[ $port =~ ^[0-9]+$ ]] || continue
        ss -Htlnp "sport = :$port" 2>/dev/null | grep -q "pid=$mine," || return 1
        if [[ $net == *udp* ]]; then
            ss -Hulnp "sport = :$port" 2>/dev/null | grep -q "pid=$mine," || return 1
        fi
    done < <(jq -r '(.inbounds // [])[] | "\(.port) \(.settings.network // "tcp")"' "$CUSTOM" 2>/dev/null)
    return 0
}

wait_up() { # up to 8 seconds for xray to run with every custom port open
    local i
    for i in $(seq 1 16); do
        if systemctl is-active --quiet watashi-xray.service && ports_up; then
            sleep 1
            # still up a second later: not one of the short lives of a failing start
            systemctl is-active --quiet watashi-xray.service && ports_up && return 0
        fi
        sleep 0.5
    done
    return 1
}

stage_pre() {
    local tag why out tmp
    status_begin pre
    [ "$(count)" -gt 0 ] || { status_finish; return 0; }
    for tag in $(tags); do
        why=$(static_problem "$tag")
        [ -n "$why" ] || why=$(alone_problem "$tag")
        [ -n "$why" ] && drop_tag pre "$tag" "$why"
    done
    if [ "$(count)" -gt 0 ] && ! out=$("$XRAY" run -test -confdir "$DIR/configs" 2>&1); then
        # Each one is fine alone, together with the rest they are not. Only
        # when the directory passes without them is it their fault.
        tmp=$(mktemp -d)
        cp "$DIR"/configs/*.json "$tmp"/ 2>/dev/null
        rm -f "$tmp/$(basename "$CUSTOM")"
        if "$XRAY" run -test -confdir "$tmp" >/dev/null 2>&1; then
            drop_all pre "$(echo "$out" | short)"
        else
            echo "watashi: the xray configs fail even without the hand built inbounds, so those are left alone"
        fi
        rm -rf "$tmp"
    fi
    status_finish
}

stage_boot() {
    local tag why
    [ "$(count)" -gt 0 ] || return 0
    for tag in $(tags); do
        why=$(static_problem "$tag")
        [ -n "$why" ] && drop_tag boot "$tag" "$why"
    done
    status_finish
}

stage_post() {
    local since=${1:-$(date +%s)} round log ports port tag hit before
    command -v systemctl >/dev/null 2>&1 || return 0
    [ "$(count)" -gt 0 ] || return 0
    for round in 1 2 3; do
        wait_up && { status_finish; return 0; }
        log=$(journalctl -u watashi-xray.service --since "@$since" -o cat --no-pager 2>/dev/null | tail -n 80)
        ports=$(echo "$log" | grep -oE 'listen (tcp|udp)[46]? [^ ]*:[0-9]+: bind' | grep -oE ':[0-9]+: bind' | grep -oE '[0-9]+' | sort -u)
        hit=""
        for port in $ports; do
            for tag in $(jq -r --argjson p "$port" '(.inbounds // [])[] | select(.port == $p) | .tag' "$CUSTOM" 2>/dev/null); do
                drop_tag post "$tag" "xray could not open port $port, another program holds it"
                hit=1
            done
        done
        if [ -z "$hit" ]; then
            # a status to go back to, should xray fail without them as well
            [ -s "$STATUS" ] || status_begin post
            before=$(mktemp)
            cp -f "$CUSTOM" "$before"
            cp -f "$STATUS" "$before.status" 2>/dev/null
            drop_all post "xray did not start with them: $(echo "$log" | grep -iE 'failed|error' | short)"
            since=$(date +%s)
            systemctl restart watashi-xray.service
            if ! wait_up; then
                # xray fails without them as well: it was never their fault
                echo "watashi: xray does not start even without the hand built inbounds, so they are put back"
                cp -f "$before" "$CUSTOM"
                chmod 600 "$CUSTOM"
                if [ -s "$before.status" ]; then
                    cp -f "$before.status" "$STATUS"
                    chmod 644 "$STATUS"
                fi
            fi
            rm -f "$before" "$before.status"
            status_finish
            return 0
        fi
        since=$(date +%s)
        systemctl restart watashi-xray.service
        [ "$(count)" -gt 0 ] || { status_finish; return 0; }
    done
    status_finish
}

case "$1" in
pre) stage_pre ;;
boot) stage_boot ;;
post) stage_post "$2" ;;
*) echo "usage: $0 pre|boot|post [since]" ;;
esac
rm -f "$KEEP.$$"
exit 0
