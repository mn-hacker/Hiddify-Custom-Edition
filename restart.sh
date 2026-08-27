#!/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

cd $( dirname -- "$0"; )
source ./common/utils.sh
# watashi: service order v12.2.43
# "systemctl is-active" answers with a single word. The old test compared it
# with a wildcard on both sides, which also accepted "inactive",
# "activating" and "deactivating", so the wait ended on its first reading and
# the caller believed a starting service was already up. These two ask for
# the exact word instead.
function ws_is_active() {
    [ "$(systemctl is-active "$1" 2>/dev/null)" == "active" ]
}
function ws_wait_active() {
    local s=$1
    local tries=${2:-30}
    local i
    for ((i = 0; i < tries; i++)); do
        ws_is_active "$s" && return 0
        sleep 1
    done
    return 1
}
function restart_service() {
    local s=$1
    s=${s##*/}
    s=${s%%.*}
    if systemctl is-enabled $s >/dev/null 2>&1 ; then
        before_stat=$(get_pretty_service_status $s 2>&1)
        systemctl restart $s
        ws_wait_active $s 30
        new_status=$(get_pretty_service_status $s 2>&1)
        printf "%-30s %-20s ---> %+19s \n" $s $before_stat  $new_status
    fi
}
function main() {
    echo -e "\n----------------------------------------------------------------"
    warning "$(printf "%-30s %-20s %s \n" "Name" "Old Status" "New Status")"
    
    # The database and the cache go first, one after the other, and each one
    # is waited on until it really answers "active". Everything else talks to
    # them, so having them in the same parallel wave as their own users is
    # what made the panel answer 503 right after a restart.
    for ss in mariadb hiddify-redis;do
        restart_service $ss
    done

    # Restart services and get their status (except hiddify-panel)
    for ss in other/**/*.service **/*.service wg-quick@warp mtproto-proxy.service mtproxy.service;do
        case "$ss" in
            hiddify-panel*|other/hiddify-cli*|*hiddify-redis*|mariadb)
                continue
                ;;
            wg-quick@warp)
                [ "$(hconfig warp_mode)" == "disable" ] && continue
                ;;
        esac
        restart_service $ss &
    done
    wait
    # Restart hiddify-panel separately from others
    for ss in hiddify-panel hiddify-panel-background-tasks;do
        restart_service $ss &
    done
    wait

    for ss in hiddify-cli;do
        restart_service $ss &
    done
    wait
    echo -e "----------------------------------------------------------------\n"
}
mkdir -p log/system/
main $@|& tee log/system/restart.log
