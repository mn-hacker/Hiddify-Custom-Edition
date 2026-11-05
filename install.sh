#!/bin/bash
# watashi v12.3.40dev: the old project name was taken out of this file (names, paths and links only)
# Watashi v12.2.37 : only the words on screen changed here
# watashi: install pass v12.2.44
cd $(dirname -- "$0")
# watashi v12.3.40dev: a server that still sits under the old folder name (the
# files of this release were unpacked over an older install) is moved to the
# new names first; the move then runs this script again from the new folder.
# The old "/opt/...-server" and "/opt/...-config" folder fixes that stood here
# are part of that move now.
if [ -f ./common/watashi_legacy.sh ] && bash ./common/watashi_legacy.sh needed; then
    exec bash ./common/watashi_legacy.sh migrate "$@"
fi
source ./common/utils.sh
NAME="0-install"
LOG_FILE="$(log_file $NAME)"

export DEBIAN_FRONTEND=noninteractive
if [ "$(id -u)" -ne 0 ]; then
    echo 'This script must be run by root' >&2
    exit 1
fi

# Handle --check-only mode (for reboot)
if [[ " $@ " == *" --check-only "* ]]; then
    # watashi v12.3.40dev: when the server went down in the middle of the move
    # from the old name, the proxies of the old install are still the ones
    # serving and the new ones were never set up; only the full install that
    # was cut off can finish that, so it runs now instead of the quick start.
    if [ -s /var/lib/watashi-legacy/deferred ] && [ -f ./common/watashi_legacy.sh ]; then
        echo "The move from the old name was not finished, running the full install"
        exec bash ./common/watashi_legacy.sh migrate --no-gui --no-log
    fi
    echo "Running in check-only mode (post-reboot service start)"
    echo "Starting critical services after reboot..."
    
    # Phase 1: Start Redis first (required by panel)
    systemctl start watashi-redis 2>/dev/null || true
    sleep 1
    
    # Phase 2: Start panel
    systemctl start watashi-panel 2>/dev/null || true
    sleep 1
    
    # Phase 3: Start background tasks (requires panel and redis)
    # watashi v12.3.35dev: reset-failed, the unit has a start limit now
    systemctl reset-failed watashi-panel-background-tasks 2>/dev/null || true
    systemctl start watashi-panel-background-tasks 2>/dev/null || true
    
    # Phase 4: Start proxy services
    systemctl start watashi-nginx 2>/dev/null || true
    systemctl start watashi-haproxy 2>/dev/null || true
    systemctl start watashi-xray 2>/dev/null || true
    systemctl start watashi-singbox 2>/dev/null || true
    
    # Phase 5: Start optional services if enabled
    systemctl start watashi-warp 2>/dev/null || true
    systemctl start watashi-ssh-liberty-bridge 2>/dev/null || true
    # watashi v12.2.130ch: the CLI service of the old name is retired

    
    # Start rathole if installed
    if [ -f /etc/systemd/system/rathole.service ]; then
        systemctl start rathole 2>/dev/null || true
    fi
    
    echo "All services started successfully"
    exit 0
fi

function main() {
    update_progress "Please wait..." "We are going to install the Watashi panel..." 0
    export ERROR=0
    
    export PROGRESS_ACTION="Installing..."
    if [ "$MODE" == "apply_users" ];then
        export DO_NOT_INSTALL="true"
    elif [ -d "/watashi-data-default/" ] && [ -z "$(ls -A /watashi-data/ 2>/dev/null)" ]; then
        cp -r /watashi-data-default/* /watashi-data/
    fi
    if [ "$DO_NOT_INSTALL" == "true" ];then
        PROGRESS_ACTION="Applying..."
        export DO_NOT_INSTALL
    fi

    export USE_VENV=313

    # Check system resources and create swap if needed (BEFORE any installs)
    check_system_resources

    install_python
    activate_python_venv
    
    if [ "$MODE" != "apply_users" ]; then
        clean_files
        
        # ============================================================
        # PHASE 1: Sequential apt-based installations (no parallel!)
        # ============================================================
        update_progress "${PROGRESS_ACTION}" "Common Tools and Requirements" 2
        runsh install.sh common  # No & - sequential
        
        if [ "$MODE" != "docker" ];then
            update_progress "${PROGRESS_ACTION}" "Redis" 5
            install_run other/redis  # No & - sequential
            
            update_progress "${PROGRESS_ACTION}" "MySQL/MariaDB" 8
            install_run other/mysql  # No & - sequential
        fi
        
        update_progress "${PROGRESS_ACTION}" "Watashi Panel" 12
        install_run watashi-panel  # No & - sequential
    fi
    
    if [ "$DO_NOT_RUN" != "true" ];then
        update_progress "Watashi Panel" "Reading Configs from Panel..." 15
        set_config_from_hpanel

        update_progress "Applying Configs" "..." 18
        bash common/replace_variables.sh
    fi
    
    if [ "$MODE" != "apply_users" ]; then
        bash ./other/deprecated/remove_deprecated.sh
        # watashi v12.3.40dev: on a server moved over from the old name its
        # proxies kept serving until now; they make way here, right before the
        # new ones below take over their ports.
        bash ./common/watashi_legacy.sh stop-old
        
        # ============================================================
        # PHASE 2: More sequential apt installations
        # ============================================================
        update_progress "Configuring..." "System and Firewall settings" 20
        runsh run.sh common  # No & - sequential
        
        update_progress "${PROGRESS_ACTION}" "Nginx" 25
        install_run nginx  # No & - sequential (has apt)
        
        update_progress "${PROGRESS_ACTION}" "Haproxy for Splitting Traffic" 35
        install_run haproxy  # No & - sequential (has apt + add-apt-repository)
        
        update_progress "${PROGRESS_ACTION}" "Getting Certificates" 45
        install_run acme.sh  # No & - sequential (has apt socat)
        
        update_progress "${PROGRESS_ACTION}" "Xray" 55
        install_run xray 1  # No & - sequential (has apt unzip)
        
        update_progress "${PROGRESS_ACTION}" "Singbox" 65
        install_run singbox  # No & - sequential (has apt unzip)
        
        # ============================================================
        # PHASE 3: the optional extras, one after the other as well
        # ============================================================
        update_progress "${PROGRESS_ACTION}" "Additional Services" 75
        
        # None of these carries an ampersand any more, so they run one after
        # the other like everything above.
        install_run other/speedtest $(hconfig "speed_test")
        install_run other/telegram $(hconfig "telegram_enable")
        install_run other/ssfaketls $(hconfig "ssfaketls_enable")
        install_run other/ssh $(hconfig "ssh_server_enable")
        # watashi v12.2.130ch: the CLI service of the old name (its folder under other/) is retired
        # watashi v12.2.103: mieru is served by mita, not by sing-box.
        install_run other/mieru $(hconfig "mieru_enable")



        
        # WARP. install_run already runs other/warp/install.sh and then
        # run.sh, so the "pushd other/warp; bash install.sh; popd" that used
        # to sit here installed warp a second time - and it did so even when
        # warp is disabled, moments before disable.sh switched it back off.
        update_progress "${PROGRESS_ACTION}" "Warp" 85
        if [[ $(hconfig "warp_mode") != "disable" ]];then
            install_run other/warp 1
        else
            install_run other/warp 0
        fi
    fi

    # watashi v12.2.116: apply_users re-renders singbox/configs and the mieru
    # server.json, but every "install_run" that applies them sits inside the
    # "$MODE" != apply_users block above, so the running cores were never told
    # about the change. xray loses a user instantly through its gRPC API, while
    # sing-box has no live user management at all, so a disabled or deleted user
    # kept connecting over shadowsocks 2022 and shadowtls (and every other
    # sing-box inbound) until the next full apply_configs. The cores without a
    # live user API are applied here, on the light path too.
    if [ "$MODE" == "apply_users" ]; then
        update_progress "${PROGRESS_ACTION}" "Applying users to Singbox" 88
        install_run singbox
        install_run other/mieru $(hconfig "mieru_enable")
        # watashi v12.2.130t: shadowsocks over faketls lives in a daemon of its
        # own, and it was installed and disabled only on the heavy path, so
        # switching it off in the panel left the old daemon running until a
        # full reinstall. It is applied on the light path as well now.
        install_run other/ssfaketls $(hconfig "ssfaketls_enable")
    fi

    update_progress "${PROGRESS_ACTION}" "Wireguard" 90
    install_run other/wireguard $(hconfig "wireguard_enable")

    # watashi v12.2.62: AmneziaWG on a daemon of its own.
    # watashi v12.2.130u: and it is the only amnezia there is, so it follows
    # amnezia_enable. The core never had an awg endpoint to fall back on.
    update_progress "${PROGRESS_ACTION}" "AmneziaWG" 92
    install_run other/amnezia $(hconfig "amnezia_enable")
    
    update_progress "${PROGRESS_ACTION}" "Almost Finished" 95
    
    finish_progress
    remove_lock $NAME
    # A SIGTERM followed by "start" is not a restart: systemd can bring the
    # unit back on its own policy, and start on a unit it still believes is
    # active does nothing, so the panel could carry on with the configuration
    # it read before this install.
    if [ "$MODE" != "apply_users" ]; then
        systemctl restart watashi-panel
    else
        systemctl start watashi-panel
    fi
    update_progress "${PROGRESS_ACTION}" "Done" 100
    
}

function clean_files() {
    rm -rf log/system/xray*
    rm -rf /opt/watashi-manager/xray/configs/*.json
    rm -rf /opt/watashi-manager/singbox/configs/*.json
    rm -rf /opt/watashi-manager/haproxy/*.cfg
    find ./ -type f -name "*.template" -delete
}

function cleanup() {
    error "Script interrupted. Exiting..."
    # disable_ansii_modes
    remove_lock $NAME
    exit 9
}

# Trap the Ctrl+C signal and call the cleanup function
trap cleanup SIGINT

function set_config_from_hpanel() {
    reload_all_configs >/dev/null
    if [[ $? != 0 ]]; then
        error "The Watashi panel raised an exception. Please keep the log, it is the only thing that can explain this."
        exit 4
    fi
    
    export SERVER_IP=$(get_public_ip)
    export SERVER_IPv6=$(get_public_ipv6)
}

function install_run() {
    echo "======================$1====================================={"
    # watashi v12.2.107: runsh turns install.sh into disable.sh whenever the
    # feature flag is false/0, and install_run called runsh twice (once for
    # install.sh, once for run.sh). that is why every switched off service
    # printed "===disable.sh other/warp" and ran its disable.sh two times in a
    # row. a disabled service is disabled once now.
    if [[ "${2:-}" == "false" || "${2:-}" == "0" ]]; then
        runsh disable.sh $@
        echo "}========================$1==================================="
        return 0
    fi
   if [ "$DO_NOT_INSTALL" != "true" ];then
            runsh install.sh $@
        if [ "$MODE" != "apply_users" ] && [ "$MODE" != "docker"  ]; then
            systemctl daemon-reload
        fi
    fi
    if [ "$DO_NOT_RUN" != "true" ];then
         runsh run.sh $@
    fi   
    echo "}========================$1==================================="
}

function runsh() {
    command=$1
    if [[ $3 == "false" || $3 == "0" ]]; then
        command=disable.sh
    fi
    if ! pushd $2 >>/dev/null; then
        echo "$2 not found, skipping"
        return 1
    fi
    if [[ -f $command ]]; then
        
        echo "===$command $2"
        bash $command
    fi
    popd >>/dev/null
}

if [[ " $@ " == *" --no-gui "* ]]; then
    set -- "${@/--no-gui/}"
    export MODE="$1"
    set_lock $NAME
    if [[ " $@ " == *" --no-log "* ]]; then
        set -- "${@/--no-log/}"
        main
        error_code=$?
    else
        # "main |& tee" hands back tee's exit code, which is practically
        # always zero, so a failed installation used to end with a success
        # message. PIPESTATUS keeps main's own answer.
        main |& tee "$LOG_FILE"
        error_code=${PIPESTATUS[0]}
    fi
    remove_lock $NAME
else
    show_progress_window --subtitle "$(get_installed_config_version)" --log "$LOG_FILE" ./install.sh $@ --no-gui --no-log
    error_code=$?
    if [[ $error_code != "0" ]]; then
        # echo less -r -P"Installation Failed! Press q to exit" +G "$log_file"
        msg_with_watashi "Installation Failed! $error_code"
    else
        msg_with_watashi "The installation has successfully completed."
        check_watashi_panel $@ |& tee -a $LOG_FILE
    fi
fi

exit $error_code
