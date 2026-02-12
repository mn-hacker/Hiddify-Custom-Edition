#!/bin/bash
cd $(dirname -- "$0")
source ./common/utils.sh
NAME="0-install"
LOG_FILE="$(log_file $NAME)"
# Fix the installation directory
if [ ! -d "/opt/hiddify-manager/" ] && [ -d "/opt/hiddify-server/" ]; then
    mv /opt/hiddify-server /opt/hiddify-manager
    ln -s /opt/hiddify-manager /opt/hiddify-server
fi
if [ ! -d "/opt/hiddify-manager/" ] && [ -d "/opt/hiddify-config/" ]; then
    mv /opt/hiddify-config/ /opt/hiddify-manager/
    ln -s /opt/hiddify-manager /opt/hiddify-config
fi

export DEBIAN_FRONTEND=noninteractive
if [ "$(id -u)" -ne 0 ]; then
    echo 'This script must be run by root' >&2
    exit 1
fi

# Handle --check-only mode (for reboot)
if [[ " $@ " == *" --check-only "* ]]; then
    echo "Running in check-only mode (post-reboot service start)"
    echo "Starting critical services after reboot..."
    
    # Phase 1: Start Redis first (required by panel)
    systemctl start hiddify-redis 2>/dev/null || true
    sleep 1
    
    # Phase 2: Start panel
    systemctl start hiddify-panel 2>/dev/null || true
    sleep 1
    
    # Phase 3: Start background tasks (requires panel and redis)
    systemctl start hiddify-panel-background-tasks 2>/dev/null || true
    
    # Phase 4: Start proxy services
    systemctl start hiddify-nginx 2>/dev/null || true
    systemctl start hiddify-haproxy 2>/dev/null || true
    systemctl start hiddify-xray 2>/dev/null || true
    systemctl start hiddify-singbox 2>/dev/null || true
    
    # Phase 5: Start optional services if enabled
    systemctl start hiddify-warp 2>/dev/null || true
    systemctl start hiddify-ssh-liberty-bridge 2>/dev/null || true
    systemctl start hiddify-cli 2>/dev/null || true
    systemctl start hiddify-ip-limiter 2>/dev/null || true
    
    # Start rathole if installed
    if [ -f /etc/systemd/system/rathole.service ]; then
        systemctl start rathole 2>/dev/null || true
    fi
    
    echo "All services started successfully"
    exit 0
fi

function main() {
    update_progress "Please wait..." "We are going to install Hiddify..." 0
    export ERROR=0
    
    export PROGRESS_ACTION="Installing..."
    if [ "$MODE" == "apply_users" ];then
        export DO_NOT_INSTALL="true"
    elif [ -d "/hiddify-data-default/" ] && [ -z "$(ls -A /hiddify-data/ 2>/dev/null)" ]; then
        cp -r /hiddify-data-default/* /hiddify-data/
    fi
    if [ "$DO_NOT_INSTALL" == "true" ];then
        PROGRESS_ACTION="Applying..."
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
        
        update_progress "${PROGRESS_ACTION}" "Hiddify Panel" 12
        install_run hiddify-panel  # No & - sequential
    fi
    
    if [ "$DO_NOT_RUN" != "true" ];then
        update_progress "HiddifyPanel" "Reading Configs from Panel..." 15
        set_config_from_hpanel

        update_progress "Applying Configs" "..." 18
        bash common/replace_variables.sh
    fi
    
    if [ "$MODE" != "apply_users" ]; then
        bash ./other/deprecated/remove_deprecated.sh
        
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
        # PHASE 3: Non-apt operations can run in parallel
        # ============================================================
        update_progress "${PROGRESS_ACTION}" "Additional Services" 75
        
        # These don't have apt in run.sh, safe to parallelize
        install_run other/speedtest $(hconfig "speed_test")
        install_run other/telegram $(hconfig "telegram_enable")
        install_run other/ssfaketls $(hconfig "ssfaketls_enable")
        install_run other/ssh $(hconfig "ssh_server_enable")
        install_run other/hiddify-cli $(hconfig "hiddifycli_enable" "true")

        # IP Limiter (Connection Enforcement)
        echo "Installing IP Limiter Service..."
        cp hiddify-panel/hiddify-ip-limiter.service /etc/systemd/system/
        systemctl enable hiddify-ip-limiter.service
        systemctl restart hiddify-ip-limiter.service

        
        # WARP install (has apt, run sequentially first)
        update_progress "${PROGRESS_ACTION}" "Warp" 85
        pushd other/warp > /dev/null && bash install.sh && popd > /dev/null
        if [[ $(hconfig "warp_mode") != "disable" ]];then
            install_run other/warp 1
        else   
            install_run other/warp 0
        fi
    fi

    update_progress "${PROGRESS_ACTION}" "Wireguard" 90
    install_run other/wireguard $(hconfig "wireguard_enable")
    
    update_progress "${PROGRESS_ACTION}" "Almost Finished" 95
    # wait  # Wait for all parallel operations
    
    echo "---------------------Finished!------------------------"
    remove_lock $NAME
    if [ "$MODE" != "apply_users" ]; then
        systemctl kill -s SIGTERM hiddify-panel 2>/dev/null || true
    fi
    systemctl start hiddify-panel
    update_progress "${PROGRESS_ACTION}" "Done" 100
    
}

function clean_files() {
    rm -rf log/system/xray*
    rm -rf /opt/hiddify-manager/xray/configs/*.json
    rm -rf /opt/hiddify-manager/singbox/configs/*.json
    rm -rf /opt/hiddify-manager/haproxy/*.cfg
    find ./ -type f -name "*.template" -exec rm -f {} \;
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
        error "Exception in Hiddify Panel. Please send the log to hiddify@gmail.com"
        exit 4
    fi
    
    export SERVER_IP=$(curl --connect-timeout 1 -s https://v4.ident.me/)
    export SERVER_IPv6=$(curl --connect-timeout 1 -s https://v6.ident.me/)
}

function install_run() {
    echo "======================$1====================================={"
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
    pushd $2 >>/dev/null
    # if [[ $? != 0]];then
    #         echo "$2 not found"
    # fi
    if [[ $? == 0 && -f $command ]]; then
        
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
    else
        main |& tee $LOG_FILE
    fi
    error_code=$?
    remove_lock $NAME
else
    show_progress_window --subtitle $(get_installed_config_version) --log $LOG_FILE ./install.sh $@ --no-gui --no-log
    error_code=$?
    if [[ $error_code != "0" ]]; then
        # echo less -r -P"Installation Failed! Press q to exit" +G "$log_file"
        msg_with_hiddify "Installation Failed! $error_code"
    else
        msg_with_hiddify "The installation has successfully completed."
        check_hiddify_panel $@ |& tee -a $LOG_FILE
    fi
fi

exit $error_code
