#!/bin/bash
# Watashi v12.2.37 : only the words on screen changed here
cd $(dirname -- "$0")
source ./utils.sh
if [ "$(id -u)" -ne 0 ]; then
    echo 'This script must be run by root' >&2
    exit 1
fi


checkOS






export DEBIAN_FRONTEND=noninteractive
NAME="installer"
LOG_FILE="$(log_file $NAME)"
export USE_VENV=true

if [ ! -f /opt/hiddify-manager/install.sh ]; then
    rm -rf /opt/hiddify-manager
fi



if [ ! -d "/opt/hiddify-manager/" ] && [ -d "/opt/hiddify-config/" ]; then
    mv /opt/hiddify-config /opt/hiddify-manager
    ln -s /opt/hiddify-manager /opt/hiddify-config
fi
if [ ! -d "/opt/hiddify-manager/" ] && [ -d "/opt/hiddify-server/" ]; then
    mv /opt/hiddify-config /opt/hiddify-manager
    ln -s /opt/hiddify-manager /opt/hiddify-server
fi

function install_panel() {
    local force=${2:-true}
    local package_mode=${1:-release}
    if [ "$package_mode" == "false" ]; then
        package_mode="release"
    fi
    local update=0
    local panel_update=0
    update_progress "Upgrading..." "Upgrading Linux Packages for extra security..." 5
    apt update
    #apt upgrade -y
    # apt -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" --only-upgrade upgrade
    # apt dist-upgrade -y
    
    if ! is_installed hiddifypanel; then
        sed -i "s|/opt/hiddify-manager/menu.sh||g" ~/.bashrc
        sed -i "s|cd /opt/hiddify-manager/||g" ~/.bashrc
        echo "/opt/hiddify-manager/menu.sh" >>~/.bashrc
        echo "cd /opt/hiddify-manager/" >>~/.bashrc
    fi

    


    install_package curl clang libev-dev libevdev2 default-libmysqlclient-dev build-essential git ca-certificates pkg-config   jq wireguard  pkg-config #needed for installing uv and hiddifypanel

    update_panel "$package_mode" "$force"
    panel_update=$?
    # We downgrade the marshmallow because of api_flask is not supporting v4
    #/opt/hiddify-manager/.venv/bin/pip install "marshmallow<=3.26.1"
    
    update_config "$package_mode" "$force"
    config_update=$?
    post_update_tasks  "$panel_update" "$config_update" "$package_mode"
    
    if is_installed hiddifypanel && [[ -n "$package_mode" && ($package_mode == "develop" || $package_mode == "beta" || $package_mode == "release") ]]; then
        hiddify-panel-cli set-setting -k package_mode -v "$package_mode"
    fi

}

# watashi v12.2.130l: every place below used to run "uv pip install" against
# /opt/hiddify-manager/hiddify-panel/src whether or not that folder existed. On a
# fresh server the version picker runs from the bootstrap copy in /tmp, before
# the manager is unpacked, so uv answered "Distribution not found" and the next
# line called the panel broken. The folder is checked first now.
function ws_install_panel_source() {
    local src=/opt/hiddify-manager/hiddify-panel/src
    if [ ! -f "$src/pyproject.toml" ] && [ ! -f "$src/setup.py" ]; then
        echo "the panel source is not unpacked yet, it is installed later in this run"
        return 2
    fi
    uv pip install "$src" || return 1
    if ! python -c "import hiddifypanel" >/dev/null 2>&1; then
        echo "the panel did not import on the first try, installing it again"
        uv pip install --force-reinstall "$src" || return 1
        python -c "import hiddifypanel" >/dev/null 2>&1 || return 1
    fi
    return 0
}

function update_panel() {
    update_progress "Checking for Update..." "Watashi Panel" 5
    local package_mode=$1
    local force=$2
    local current_panel_version=$(get_installed_panel_version)
    # Your existing logic for checking and updating the panel version based on the package mode
    # Set panel_update to 1 if an update is performed
    
    case "$package_mode" in
        docker)
            activate_python_venv
            # install_python310
            # uv pip install -U --no-deps --force-reinstall hiddify-panel/src
            ws_install_panel_source
            # pip install -U hiddifypanel
        ;;
        v*)
            update_progress "Updating..." "Watashi Panel from $current_panel_version to $latest" 10
            panel_path=$(hiddifypanel_path)
            disable_panel_services
            # watashi v12.2.130g: the version picker used to fetch the panel from
            # the upstream project, which quietly replaced ours. The manager
            # for this mode is our own tagged release, so the panel is taken
            # from the source inside it.
            if [ -z "$USE_VENV" ]; then
                install_python310
            fi
            ws_install_panel_from_source
            update_progress "Updated..." "Watashi Panel to ${package_mode}" 50
            return 0
        ;;
        develop|dev)
            # Use the latest commit from GitHub
            latest=$(get_commit_version Hiddify-Panel)
            activate_python_venv
            warning "DEVELOP: watashi panel version current=$current_panel_version latest=$latest"
            if [[ "$current_panel_version" != "$latest" ]]; then
                error "The current develop version is outdated! Updating..."
            fi
            if [[ $force == "true" || "$latest" != "$current_panel_version" ]]; then
                update_progress "Updating..." "Watashi Panel from $current_panel_version to $latest" 10
               
                disable_panel_services
                
                # watashi v12.2.130g: the develop mode installed the panel from the
                # upstream project, which is how our own work disappeared from a
                # server. The source in this folder is what we ship, so it is
                # what gets installed.
                ws_install_panel_from_source || return 1
                panel_path=$(hiddifypanel_path)
                echo "setting $latest in $panel_path/VERSION"
                echo $latest > $panel_path/VERSION
                sed -i "s/__version__='[^']*'/__version__='$latest'/" $panel_path/VERSION.py
                update_progress "Updated..." "Watashi Panel to $latest" 50
                return 0
            fi
        ;;
        beta)
            activate_python_venv
            latest=$(get_pre_release_version Hiddify-Custom-Edition)
            warning "BETA: watashi panel version current=$current_panel_version latest=$latest"
            if [[ "$current_panel_version" != "$latest" ]]; then
                error "The current beta version is outdated! Updating..."
            fi
            if [[ $force == "true" || "$current_panel_version" != "$latest" ]]; then
                update_progress "Updating..." "Watashi Panel from $current_panel_version to $latest" 10
                # pip install -U --pre hiddifypanel==$latest
                disable_panel_services
                # watashi v12.2.130: this used to pull the panel from PyPI, where a
                # different build than the one in this folder lives. An update could
                # therefore replace a working panel with code that never matched the
                # rest of the manager, and a failed install left no panel at all.
                # The source next to us is the only thing we ship, so it is what we
                # install, and if it will not import we say so instead of carrying on.
                ws_install_panel_source
                case $? in
                1) error "the panel could not be imported after the install"; return 1 ;;
                esac
                update_progress "Updated..." "Watashi Panel to $latest" 50
                return 0
            fi
        ;;
        release) 
            # Python 3.13 is now used via USE_VENV=313 (configured in lines 347-350)
            activate_python_venv
            # error "you can not install release version 8 using this script"
            # exit 1
            latest=$(get_release_version Hiddify-Custom-Edition)
            if [[ "$current_panel_version" != "$latest" ]]; then
                error "The current beta version is outdated! Updating..."
            fi
            warning "watashi panel version current=$current_panel_version latest=$latest"
            if [[ $force == "true" || "$current_panel_version" != "$latest" ]]; then
                update_progress "Updating..." "Watashi Panel from $current_panel_version to $latest" 10
                # pip3 install -U hiddifypanel==$latest
                disable_panel_services
                # watashi v12.2.130: this used to pull the panel from PyPI, where a
                # different build than the one in this folder lives. An update could
                # therefore replace a working panel with code that never matched the
                # rest of the manager, and a failed install left no panel at all.
                # The source next to us is the only thing we ship, so it is what we
                # install, and if it will not import we say so instead of carrying on.
                ws_install_panel_source
                case $? in
                1) error "the panel could not be imported after the install"; return 1 ;;
                esac
                update_progress "Updated..." "Watashi Panel to $latest" 50
                return 0
            fi
        ;;
        *)
            echo "Unknown package mode: $package_mode"
            exit 1
        ;;
    esac
    
    return 1
}

function update_config() {
    update_progress "Checking for Update..." "Watashi Config" 55
    local package_mode=$1
    local force=$2
    local current_config_version=$(get_installed_config_version)
    
    case "$package_mode" in
        docker)
            echo "installing in docker mode"
            DO_NOT_RUN=true bash /opt/hiddify-manager/install.sh docker --no-gui --no-log
            echo "installing in docker mode finishs"
        ;;
        v*)
            update_progress "Updating..." "Watashi Config from $current_config_version to $latest" 60
            export HIDDIFY_DISABLE_UPDATE=true
            #update_from_github "hiddify-manager.tar.gz" "https://github.com/mn-hacker/Hiddify-Custom-Edition/archive/refs/tags/${package_mode}.tar.gz" $latest
            update_from_github "hiddify-manager.zip" "https://github.com/mn-hacker/Hiddify-Custom-Edition/releases/download/${package_mode}/hiddify-manager.zip" $latest
            update_progress "Updated..." "Watashi Config to $latest" 100
            return 0
        ;;
        develop|dev)
            local latest=$(get_commit_version hiddify-manager)
            echo "DEVELOP: Current Config Version=$current_config_version -- Latest=$latest"
            if [[ "$force" == "true" || "$latest" != "$current_config_version" ]]; then
                update_progress "Updating..." "Watashi Config from $current_config_version to $latest" 60
                update_from_github "hiddify-manager.tar.gz" "https://github.com/mn-hacker/Hiddify-Custom-Edition/archive/refs/heads/dev.tar.gz" $latest
                
                update_progress "Updated..." "Watashi Config to $latest" 100
                return 0
            fi
        ;;
        beta)
            local latest=$(get_pre_release_version Hiddify-Manager)
            echo "BETA: Current Config Version=$current_config_version -- Latest=$latest"
            if [[ "$force" == "true" || "$latest" != "$current_config_version" ]]; then
                update_progress "Updating..." "Watashi Config from $current_config_version to $latest" 60
                update_from_github "hiddify-manager.zip" "https://github.com/mn-hacker/Hiddify-Custom-Edition/releases/download/v$latest/hiddify-manager.zip"
                update_progress "Updated..." "Watashi Config to $latest" 100
                return 0
            fi
        ;;
        release)
            # error "you can not install release version 8 using this script"
            # exit 1
            local latest=$(get_release_version hiddify-manager)
            echo "RELEASE: Current Config Version=$current_config_version -- Latest=$latest"
            if [[ "$force" == "true" || "$latest" != "$current_config_version" ]]; then
                update_progress "Updating..." "Watashi Config from $current_config_version to $latest" 60
                update_from_github "hiddify-manager.zip" "https://github.com/mn-hacker/Hiddify-Custom-Edition/releases/latest/download/hiddify-manager.zip"
                update_progress "Updated..." "Watashi Config to $latest" 100
                return 0
            fi
            
        ;;
        *)
            echo "Unknown package mode: $package_mode"
            exit 1
        ;;
    esac
    
    return 1
}

function post_update_tasks() {
    local panel_update=$1
    local config_update=$2
    local package_mode=$3
    
    if [[ $config_update != 0 ]]; then
        echo "---------------------Finished!------------------------"
    fi
    remove_lock $NAME

    if [ "$package_mode" != "docker" ];then
      # Always stop panel first to ensure clean restart
      systemctl stop hiddify-panel.service 2>/dev/null || true
      systemctl stop hiddify-panel-background-tasks.service 2>/dev/null || true

      # If panel was updated OR config was updated, apply configs
      # watashi v12.2.130g: the manager files and the panel arrive in two separate
      # steps, and the panel can be installed before the new files are on
      # disk. Installing once more here, from the source that is now present,
      # makes the order harmless and keeps the panel and the manager in step.
      if [[ $panel_update == 0 || $config_update == 0 ]]; then
          ws_install_panel_from_source || true
      fi

      if [[ $panel_update == 0 || $config_update == 0 ]]; then
          echo "Applying configurations..."
          bash /opt/hiddify-manager/apply_configs.sh --no-gui --no-log
      fi
      
      # Restart all core services to ensure new version is used
      echo "Restarting services..."
      systemctl daemon-reload
      systemctl restart hiddify-redis.service 2>/dev/null || true
      sleep 1
      systemctl restart hiddify-panel.service 2>/dev/null || true
      systemctl restart hiddify-panel-background-tasks.service 2>/dev/null || true
      
      cd /opt/hiddify-manager/hiddify-panel
      if [ "$CREATE_EASYSETUP_LINK" == "true" ];then
          hiddify-panel-cli set-setting --key create_easysetup_link --val True
      fi

      case "$package_mode" in
          release|beta)
              hiddify-panel-cli set-setting --key package_mode --val $package_mode
          ;;
          dev|develop)
              hiddify-panel-cli set-setting --key package_mode --val develop
          ;;
      esac
      
      echo "Update completed. Panel should now show new features."
    fi
}

function update_from_github() {
    local file_name=$1
    local url=$2
    local override_version=$3
    
    local file_type=${file_name##*.}
    mkdir -p /opt/hiddify-manager
    cd /opt/hiddify-manager
    curl -sL -o "$file_name" "$url"
    
    if [[ "$file_type" == "zip" ]]; then
        install_package unzip
        unzip -q -o "$file_name"
    elif [[ "$file_type" == "gz" ]]; then
        tar xzf "$file_name" --strip-components=1
    else
        echo "Unsupported file type: $file_type"
        return 1
    fi
    if [[ ! -z "$override_version" ]]; then
        echo "$override_version" >VERSION
    fi
    rm "$file_name"
    rm -f xray/configs/*.json
    rm -f singbox/configs/*.json
    rm -f /opt/hiddify-manager/xray/configs/05_inbounds_10*.json*
    rm -f /opt/hiddify-manager/xray/configs/05_inbounds_h2*.json*
    rm -f /opt/hiddify-manager/xray/configs/05_inbounds_02_realitygrpc*.json*
    rm -f /opt/hiddify-manager/xray/configs/05_inbounds_02_realityh2*.json*
    rm -f /opt/hiddify-manager/singbox/configs/05_inbounds_2071_realitygrpc_main.json*
    rm -f /opt/hiddify-manager/singbox/configs/05_inbounds_20[123][1234]*.json*

    bash install.sh --no-gui --no-log
    bash install.sh --no-gui --no-log #temporary fix
}

function custom_version_installer(){
    #TAGS=$(curl -s "https://api.github.com/repos/hiddify/hiddify-manager/tags?per_page=1000" | jq -r '.[].name')
    TAGS=$(curl -s "https://pypi.org/pypi/hiddifypanel/json" | jq -r '.releases | keys[]'|sort -V -r)
    version_gt() {
        [ "$(printf '%s\n' "$@" | sort -V | head -n 1)" != "$1" ]
    }
    FILTERED_TAGS=("release" "" "beta" "" "dev" "")
    for tag in $TAGS; do
        if [[ ! $tag =~ dev ]] && version_gt "$tag" "10.0.0"; then
            FILTERED_TAGS+=("v$tag" "")
        fi
    done
    TAG_LIST=$(printf "%s " "${FILTERED_TAGS[@]}")
    SELECTED_TAG=$(whiptail --title "Watashi version picker" --menu "Choose a version! Note: Downgrade is not supported!" 20 70 12 "${FILTERED_TAGS[@]}" 3>&1 1>&2 2>&3)
    if [ $? -eq 0 ]; then
        echo "You selected: $SELECTED_TAG"
        $0 $SELECTED_TAG
    else
        echo "No tag selected."
        exit 1
    fi
}

if [[ " $@ " == *" custom "* ]];then
    custom_version_installer
    exit $?
fi


export USE_VENV=313
if [[ " $@ " == *" dev "* || " $@ " == *" docker "* || " $@ " == *" develop "* || " $@ " == *" beta "* ]];then
    export USE_VENV=313
fi

# Run the main function and log the output
if [[ " $@ " == *" --no-gui "* || "$(get_installed_panel_version) " == "8."* || "$NO_UI" == "true" ]]; then
    set -- "${@/--no-gui/}"
    set_lock $NAME
    if [[ " $@ " == *" --no-log "* ]]; then
        set -- "${@/--no-log/}"
        install_panel "$@"
        error_code=$?
    else
        install_panel "$@" |& tee $LOG_FILE
        error_code="${PIPESTATUS[0]}"
    fi
    
    remove_lock $NAME
else
    
    show_progress_window --subtitle "Installer" --log $LOG_FILE $0 $@ --no-gui --no-log
    
    error_code=$?
    if [[ $error_code != "0" ]]; then
        # echo less -r -P"Installation Failed! Press q to exit" +G "$log_file"
        msg_with_hiddify "Installation Failed! code=$error_code"
    else
        msg_with_hiddify "The installation has successfully completed."
        check_hiddify_panel $@ |& tee -a $LOG_FILE
        read -p "Press any key to go  to menu" -n 1 key
    fi
    bash /opt/hiddify-manager/menu.sh
fi
exit $error_code
