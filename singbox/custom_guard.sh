#!/bin/bash
# watashi v12.3.42dev: the safety net of the hand built sing-box inbounds
# (advanced mode), the twin of xray/custom_guard.sh.
#
#   pre   singbox/run.sh, before sing-box reloads or restarts: every row of the
#         custom file is checked on its own, then the whole config directory is
#         checked, and whatever sing-box would refuse is taken out of the file
#   boot  ExecStartPre of watashi-singbox.service, before every start (an apply,
#         a reboot, a crash): the two things that break between applies, a
#         certificate that is gone and a port another program took, are found
#         without starting sing-box
#   post  singbox/run.sh, after sing-box (re)started: when it does not come up,
#         the inbound it names is taken out, or all of them, and it starts again
#
# A row is one inbound, or two for ShadowTLS: custom-N and the inner custom-N-in
# it hands its connections to, which always go together. What was taken out
# and why goes to log/custom_inbounds_singbox.status, which the Inbounds page
# reads. The panel then leaves those rows out of the next render and out of the
# subscriptions until the owner changes them, so one bad row can never keep the
# panel's own sing-box inbounds from starting.
# No file of the panel's own inbounds is ever touched here.

DIR=/opt/watashi-manager/singbox
CUSTOM=$DIR/configs/05_inbounds_90_custom.json
STATUS=/opt/watashi-manager/log/custom_inbounds_singbox.status
KEEP=/opt/watashi-manager/log/custom_inbounds_singbox.rejected.json
CUR=/opt/watashi-manager/current.json
SINGBOX=$DIR/sing-box
UNIT=watashi-singbox.service
SSL_RE='^/opt/watashi-manager/ssl/[A-Za-z0-9._-]+$'
TYPES='["hysteria2", "tuic", "anytls", "naive", "shadowtls", "shadowsocks", "snell"]'

command -v jq >/dev/null 2>&1 || exit 0

# the rows: every inbound but the inner ones of ShadowTLS
count() { jq -r '[(.inbounds // [])[] | select(.tag | endswith("-in") | not)] | length' "$CUSTOM" 2>/dev/null || echo 0; }
tags() { jq -r '(.inbounds // [])[] | .tag | select(endswith("-in") | not)' "$CUSTOM" 2>/dev/null; }
rev_now() { jq -r '.custom_inbounds_rev_singbox // ""' "$CUR" 2>/dev/null; }
# sing-box colours its level and puts it in front of every line
plain() { sed 's/\x1b\[[0-9;]*[A-Za-z]//g; s/^\(FATAL\|ERROR\|WARN\|INFO\|DEBUG\|TRACE\)\[[0-9]*\] *//'; }
short() { plain | grep -v '^[[:space:]]*$' | tail -n 3 | tr '\n' ' ' | cut -c1-500; }
# "proto port" for every port a row listens on, of every row or of one
uses() {
    jq -r --arg t "${1:-}" '(.inbounds // [])[] | select(.tag | endswith("-in") | not) | select($t == "" or .tag == $t)
        | select(.listen_port != null) | .listen_port as $p
        | (if .type == "hysteria2" or .type == "tuic" then ["udp"]
           elif .type == "shadowsocks" or .type == "naive" then
               (if .network == "tcp" then ["tcp"] elif .network == "udp" then ["udp"] else ["tcp", "udp"] end)
           else ["tcp"] end)[]
        | "\(.) \($p)"' "$CUSTOM" 2>/dev/null
}

status_begin() { # status_begin stage: a fresh status for this apply
    # The same set as last time was rendered without the rows that apply took
    # out (the panel leaves them out while nothing changed), so they are not in
    # the file to be judged again: what was said about them still holds, and
    # forgetting it would put them back into the next render.
    # "Try again" on the Inbounds page clears this on purpose (xray/custom_apply.sh).
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

drop_tag() { # drop_tag stage tag reason: the row, with its inner inbound when it has one
    keep_copy
    write_custom '[(.inbounds // [])[] | select(.tag != $t and .tag != ($t + "-in"))] as $left
        | if ($left | length) == 0 then {} else .inbounds = $left end' --arg t "$2"
    status_reject "$1" "$2" "$3"
    echo "watashi: the sing-box inbound $2 was taken out: $3"
}

drop_all() { # drop_all stage reason
    local tag
    keep_copy
    for tag in $(tags); do
        status_reject "$1" "$tag" "$2"
    done
    echo '{}' >"$CUSTOM"
    chmod 600 "$CUSTOM"
    echo "watashi: every hand built sing-box inbound was taken out: $2"
}

holder() { # holder tcp|udp port: the name of the program that holds the port
    local flag=-Htlnp
    [ "$1" == "udp" ] && flag=-Hulnp
    ss $flag "sport = :$2" 2>/dev/null | grep -o 'users:(("[^"]*"' | head -1 | cut -d'"' -f2
}

foreign_listener() { # foreign_listener tcp|udp port: a program other than this sing-box holds the port
    # Told apart by its process id, not by its name: another panel on the same
    # server can run a binary called sing-box as well. Before a start (boot)
    # this sing-box holds nothing, so every listener counts.
    local flag=-Htlnp mine
    [ "$1" == "udp" ] && flag=-Hulnp
    command -v ss >/dev/null 2>&1 || return 1
    mine=$(systemctl show -p MainPID --value $UNIT 2>/dev/null)
    [[ $mine =~ ^[1-9][0-9]*$ ]] || mine=none
    ss $flag "sport = :$2" 2>/dev/null | grep -v "pid=$mine," | grep -q .
}

static_problem() { # static_problem tag: what is wrong without starting sing-box
    local tag=$1 file proto port who
    # the rows of the Inbounds page and nothing else
    if jq -e --arg t "$tag" --argjson types "$TYPES" '[(.inbounds // [])[] | select(.tag == $t or .tag == ($t + "-in"))
            | select(.type as $y | $types | index($y) | not)] | length > 0' "$CUSTOM" >/dev/null 2>&1; then
        echo "this kind of inbound cannot be built by hand"
        return
    fi
    # a row takes the certificate of a domain of the panel and nothing else:
    # no certificate of its own, no ACME, no client certificates to read
    if jq -e --arg t "$tag" '[(.inbounds // [])[] | select(.tag == $t or .tag == ($t + "-in")) | .. | objects | keys[]
            | select(. == "acme" or . == "certificate" or . == "key" or startswith("client_certificate"))] | length > 0' \
        "$CUSTOM" >/dev/null 2>&1; then
        echo "a hand built inbound can only use the certificate of a domain of the panel"
        return
    fi
    # Hysteria2 may look like a site, but it never serves a folder of this server
    if jq -e --arg t "$tag" '[(.inbounds // [])[] | select(.tag == $t or .tag == ($t + "-in")) | .. | objects | select(has("masquerade"))
            | .masquerade | select(type != "string" or (test("^https?://[^\\s\"]{1,250}$") | not))] | length > 0' \
        "$CUSTOM" >/dev/null 2>&1; then
        echo "masquerade can only be the http:// or https:// address of a site"
        return
    fi
    # ShadowTLS hands its connections to its own inner inbound, nothing else does
    if jq -e --arg t "$tag" '[(.inbounds // [])[] | select(.tag == $t or .tag == ($t + "-in")) | select(has("detour"))
            | select(.type != "shadowtls" or .tag != $t or .detour != ($t + "-in"))] | length > 0' \
        "$CUSTOM" >/dev/null 2>&1; then
        echo "only ShadowTLS hands its connections on, and only to its own inner inbound"
        return
    fi
    while read -r file; do
        [ -n "$file" ] || continue
        if ! [[ $file =~ $SSL_RE ]] || [[ $file == *..* ]]; then
            echo "the certificate $file is not one of the panel's certificates"
            return
        fi
        if [ ! -s "$file" ]; then
            echo "the certificate file $file is missing"
            return
        fi
    done < <(jq -r --arg t "$tag" '(.inbounds // [])[] | select(.tag == $t or .tag == ($t + "-in")) | .. | objects
        | to_entries[] | select(.key == "certificate_path" or .key == "key_path") | .value | tostring' "$CUSTOM" 2>/dev/null)
    if ! jq -e --arg t "$tag" '(.inbounds // []) | any(.tag == $t and (.listen_port | type) == "number")' "$CUSTOM" >/dev/null 2>&1; then
        echo "the inbound has no port"
        return
    fi
    while read -r proto port; do
        [[ $port =~ ^[0-9]+$ ]] || continue
        if foreign_listener "$proto" "$port"; then
            # the name only when ss can see the process behind the socket
            who=$(holder "$proto" "$port")
            echo "another program already listens on $port/$proto${who:+: $who}"
            return
        fi
    done < <(uses "$tag")
}

alone_problem() { # alone_problem tag: what sing-box says about this row by itself
    local tag=$1 tmp out
    tmp=$(mktemp -d) || return 0
    jq --arg t "$tag" '{log: {disabled: true},
        inbounds: [(.inbounds // [])[] | select(.tag == $t or .tag == ($t + "-in"))],
        outbounds: [{type: "direct", tag: "freedom"}]}' "$CUSTOM" >"$tmp/one.json" 2>/dev/null
    if ! out=$(cd "$tmp" && "$SINGBOX" check -c "$tmp/one.json" 2>&1); then
        echo "$out" | short
    fi
    rm -rf "$tmp"
}

ports_up() { # every row left in the file listens, and it is this sing-box that listens
    local proto port mine flag
    command -v ss >/dev/null 2>&1 || return 0
    mine=$(systemctl show -p MainPID --value $UNIT 2>/dev/null)
    [[ $mine =~ ^[1-9][0-9]*$ ]] || return 1
    while read -r proto port; do
        [[ $port =~ ^[0-9]+$ ]] || continue
        flag=-Htlnp
        [ "$proto" == "udp" ] && flag=-Hulnp
        ss $flag "sport = :$port" 2>/dev/null | grep -q "pid=$mine," || return 1
    done < <(uses)
    return 0
}

wait_up() { # up to 20 seconds for sing-box to run with every custom port open
    local i
    for i in $(seq 1 40); do
        if systemctl is-active --quiet $UNIT && ports_up; then
            sleep 1
            # still up a second later: not one of the short lives of a failing start
            systemctl is-active --quiet $UNIT && ports_up && return 0
        fi
        sleep 0.5
    done
    return 1
}

restart_core() {
    # the failing starts before this one count against the start limit of the
    # unit; this start is a new config, so it gets its own chance
    systemctl reset-failed $UNIT 2>/dev/null
    systemctl restart $UNIT 2>/dev/null
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
    if [ "$(count)" -gt 0 ] && ! out=$("$SINGBOX" check -C "$DIR/configs" 2>&1); then
        # Each one is fine alone, together with the rest they are not. Only
        # when the directory passes without them is it their fault.
        tmp=$(mktemp -d)
        cp "$DIR"/configs/*.json "$tmp"/ 2>/dev/null
        rm -f "$tmp/$(basename "$CUSTOM")"
        if "$SINGBOX" check -C "$tmp" >/dev/null 2>&1; then
            drop_all pre "$(echo "$out" | short)"
        else
            echo "watashi: the sing-box configs fail even without the hand built inbounds, so those are left alone"
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
    local since=${1:-$(date +%s)} round log tag hit before line why
    command -v systemctl >/dev/null 2>&1 || return 0
    [ "$(count)" -gt 0 ] || return 0
    for round in 1 2 3; do
        wait_up && { status_finish; return 0; }
        # systemd itself holds a healthy sing-box down once it was started five
        # times in 300 seconds (StartLimitBurst of the unit) and the last one
        # ended cleanly: no row is to blame for that, it only needs a start
        if [ "$(systemctl show -p Result --value $UNIT 2>/dev/null)" == "start-limit-hit" ] &&
            [ "$(systemctl show -p ExecMainStatus --value $UNIT 2>/dev/null)" == "0" ]; then
            echo "watashi: sing-box was held down by the systemd start limit, starting it again"
            since=$(date +%s)
            restart_core
            continue
        fi
        log=$(journalctl -u $UNIT --since "@$since" -o cat --no-pager 2>/dev/null | plain | tail -n 80)
        hit=""
        # sing-box names the inbound it could not start: inbound/anytls[custom-3]
        for tag in $(echo "$log" | grep -oE 'inbound/[a-z0-9]+\[custom-[0-9]+(-in)?\]' | grep -oE 'custom-[0-9]+' | sort -u); do
            jq -e --arg t "$tag" '(.inbounds // []) | any(.tag == $t)' "$CUSTOM" >/dev/null 2>&1 || continue
            line=$(echo "$log" | grep -F "[$tag" | tail -n 1 | sed 's/^.*start service: //' | cut -c1-300)
            drop_tag post "$tag" "sing-box could not start it: ${line:-no reason given}"
            hit=1
        done
        if [ -z "$hit" ]; then
            # a status to go back to, should sing-box fail without them as well
            [ -s "$STATUS" ] || status_begin post
            before=$(mktemp)
            cp -f "$CUSTOM" "$before"
            cp -f "$STATUS" "$before.status" 2>/dev/null
            why=$(echo "$log" | grep -iE 'fatal|error' | short)
            # with no line of its own, what systemd says about the unit
            [ -n "$why" ] || why="systemd says $(systemctl show -p Result --value $UNIT 2>/dev/null)"
            drop_all post "sing-box did not start with them: $why"
            since=$(date +%s)
            restart_core
            if ! wait_up; then
                # sing-box fails without them as well: it was never their fault
                echo "watashi: sing-box does not start even without the hand built inbounds, so they are put back"
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
        restart_core
        [ "$(count)" -gt 0 ] || { wait_up; status_finish; return 0; }
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
