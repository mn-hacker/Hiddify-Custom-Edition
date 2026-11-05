#!/bin/bash
# watashi v12.3.40dev: the old project name was taken out of this file (names, paths and links only)
# Watashi v12.2.37 : only the words on screen changed here
cd $(dirname -- "$0")
source ./utils.sh
if [ "$(id -u)" -ne 0 ]; then
    echo 'This script must be run by root' >&2
    exit 1
fi


checkOS

# watashi v12.3.40dev: where a release zip may already be waiting. The move
# from the old name below fetches it first, so a release that is not out yet
# (or a download that fails) stops the run before anything was changed.
WS_RELEASE_CACHE=/tmp/watashi-release
WS_RELEASE_REPO="https://github.com/mn-hacker/Watashi-Manager"

# watashi v12.3.40dev: the zip a package mode installs. update_config below
# asks for the same addresses; this is only the copy the move needs early.
function ws_release_zip_url() {
    local mode=${1:-release} v
    case "$mode" in
    v*) echo "$WS_RELEASE_REPO/releases/download/${mode}/watashi-manager.zip" ;;
    develop | dev)
        v=$(get_dev_version Watashi-Manager)
        [ -n "$v" ] || return 1
        echo "$WS_RELEASE_REPO/releases/download/v${v}/watashi-manager.zip"
        ;;
    beta)
        v=$(get_pre_release_version Watashi-Manager)
        [ -n "$v" ] || return 1
        echo "$WS_RELEASE_REPO/releases/download/v${v}/watashi-manager.zip"
        ;;
    release) echo "$WS_RELEASE_REPO/releases/latest/download/watashi-manager.zip" ;;
    *) return 1 ;;
    esac
}

# watashi v12.3.40dev: a zip is only good if it unpacks and is laid out under
# the new names. A release from before the rename has neither the move script
# nor the panel under its new folder, so it is refused here.
function ws_release_zip_ok() {
    local zip=$1 list
    [ -s "$zip" ] || return 1
    install_package unzip >/dev/null 2>&1
    unzip -tq "$zip" >/dev/null 2>&1 || return 1
    list=$(unzip -Z1 "$zip" 2>/dev/null)
    grep -qx 'common/watashi_legacy.sh' <<<"$list" || return 1
    grep -qx 'watashi-panel/src/pyproject.toml' <<<"$list" || return 1
    return 0
}

# watashi v12.3.40dev: puts the zip for this run into WS_RELEASE_CACHE and
# remembers where it came from. WATASHI_LOCAL_ZIP hands over a zip that is
# already on the disk (offline installs and tests), nothing is downloaded then.
function ws_fetch_release_zip() {
    local url=$1 zip="$WS_RELEASE_CACHE/watashi-manager.zip"
    mkdir -p "$WS_RELEASE_CACHE" && chmod 700 "$WS_RELEASE_CACHE"
    if [ -n "$WATASHI_LOCAL_ZIP" ]; then
        cp -f "$WATASHI_LOCAL_ZIP" "$zip" 2>/dev/null || return 1
    else
        rm -f "$zip"
        curl -fsSL --retry 3 -o "$zip" "$url" || { rm -f "$zip"; return 1; }
    fi
    ws_release_zip_ok "$zip" || { rm -f "$zip"; return 1; }
    echo "$url" >"$WS_RELEASE_CACHE/url"
    return 0
}

# watashi v12.3.40dev: a server that still lives under the old name is moved
# over before anything else touches /opt/watashi-manager (log_file below
# already makes folders there). Every old name is kept in that one script;
# it does nothing on a server that has nothing old left.
WS_LEGACY_SCRIPT=""
for ws_f in "$(pwd)/watashi_legacy.sh" /opt/watashi-manager/common/watashi_legacy.sh; do
    if [ -f "$ws_f" ]; then
        WS_LEGACY_SCRIPT="$ws_f"
        break
    fi
done
ws_pm=""
for ws_a in "$@"; do
    case "$ws_a" in
    --* | true | false | "") ;;
    *) ws_pm=$ws_a; break ;;
    esac
done
ws_pm=${ws_pm:-release}
if [ -n "$WS_LEGACY_SCRIPT" ] && [ "$ws_pm" != "custom" ] && [ "$ws_pm" != "docker" ]; then
    if bash "$WS_LEGACY_SCRIPT" needed; then
        echo "This server still runs under the old name; it is moved over first."
        ws_url=$(ws_release_zip_url "$ws_pm")
        if [ -z "$ws_url" ] && [ -z "$WATASHI_LOCAL_ZIP" ]; then
            echo "The $ws_pm release could not be found, nothing was changed." >&2
            exit 1
        fi
        if ! ws_fetch_release_zip "$ws_url"; then
            echo "The $ws_pm release ($ws_url) could not be downloaded or is from before the rename, nothing was changed." >&2
            exit 1
        fi
    fi
    if ! bash "$WS_LEGACY_SCRIPT" migrate --no-install; then
        echo "The move from the old name stopped half way; its log is /var/log/watashi-migrate.log. Run the same command again to finish it." >&2
        exit 1
    fi
fi

export DEBIAN_FRONTEND=noninteractive
NAME="installer"
LOG_FILE="$(log_file $NAME)"
export USE_VENV=true

if [ ! -f /opt/watashi-manager/install.sh ]; then
    rm -rf /opt/watashi-manager
fi

# watashi v12.3.40dev: the two blocks that moved the folders of the oldest
# releases were dropped; that move, and every later one, is done by
# watashi_legacy.sh above.

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
    
    if ! is_installed watashipanel; then
        sed -i "s|/opt/watashi-manager/menu.sh||g" ~/.bashrc
        sed -i "s|cd /opt/watashi-manager/||g" ~/.bashrc
        echo "/opt/watashi-manager/menu.sh" >>~/.bashrc
        echo "cd /opt/watashi-manager/" >>~/.bashrc
    fi

    


    install_package curl clang libev-dev libevdev2 default-libmysqlclient-dev build-essential git ca-certificates pkg-config   jq wireguard  pkg-config #needed for installing uv and watashipanel

    update_panel "$package_mode" "$force"
    panel_update=$?
    # We downgrade the marshmallow because of api_flask is not supporting v4
    #/opt/watashi-manager/.venv/bin/pip install "marshmallow<=3.26.1"
    
    update_config "$package_mode" "$force"
    config_update=$?
    post_update_tasks  "$panel_update" "$config_update" "$package_mode"
    
    if is_installed watashipanel && [[ -n "$package_mode" && ($package_mode == "develop" || $package_mode == "beta" || $package_mode == "release") ]]; then
        watashi-panel-cli set-setting -k package_mode -v "$package_mode"
    fi

}

# watashi v12.2.130l: every place below used to run "uv pip install" against
# /opt/watashi-manager/watashi-panel/src whether or not that folder existed. On a
# fresh server the version picker runs from the bootstrap copy in /tmp, before
# the manager is unpacked, so uv answered "Distribution not found" and the next
# line called the panel broken. The folder is checked first now.
function ws_install_panel_source() {
    local src=/opt/watashi-manager/watashi-panel/src
    if [ ! -f "$src/pyproject.toml" ] && [ ! -f "$src/setup.py" ]; then
        echo "the panel source is not unpacked yet, it is installed later in this run"
        return 2
    fi
    # watashi v12.3.40dev: right after the move from the old name the source
    # here is still the previous release; the new one comes with the zip.
    if type ws_panel_source_ok >/dev/null 2>&1 && ! ws_panel_source_ok "$src"; then
        echo "the panel source here is from before the rename, the new one is installed later in this run"
        return 2
    fi
    uv pip install "$src" || return 1
    # watashi v12.3.35dev: same guard as ws_install_panel_from_source
    type ws_heal_celery_redis >/dev/null 2>&1 && ws_heal_celery_redis
    if ! python -c "import watashipanel" >/dev/null 2>&1; then
        echo "the panel did not import on the first try, installing it again"
        uv pip install --force-reinstall "$src" || return 1
        python -c "import watashipanel" >/dev/null 2>&1 || return 1
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
            # uv pip install -U --no-deps --force-reinstall watashi-panel/src
            ws_install_panel_source
            # pip install -U watashipanel
        ;;
        v*)
            update_progress "Updating..." "Watashi Panel from $current_panel_version to $latest" 10
            panel_path=$(watashipanel_path)
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
            latest=$(get_dev_version Watashi-Manager)  # watashi dev-channel
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
                panel_path=$(watashipanel_path)
                echo "setting $latest in $panel_path/VERSION"
                echo $latest > $panel_path/VERSION
                sed -i "s/__version__='[^']*'/__version__='$latest'/" $panel_path/VERSION.py
                update_progress "Updated..." "Watashi Panel to $latest" 50
                return 0
            fi
        ;;
        beta)
            activate_python_venv
            latest=$(get_pre_release_version Watashi-Manager)
            warning "BETA: watashi panel version current=$current_panel_version latest=$latest"
            if [[ "$current_panel_version" != "$latest" ]]; then
                error "The current beta version is outdated! Updating..."
            fi
            if [[ $force == "true" || "$current_panel_version" != "$latest" ]]; then
                update_progress "Updating..." "Watashi Panel from $current_panel_version to $latest" 10
                # pip install -U --pre watashipanel==$latest
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
            latest=$(get_release_version Watashi-Manager)
            if [[ "$current_panel_version" != "$latest" ]]; then
                error "The current beta version is outdated! Updating..."
            fi
            warning "watashi panel version current=$current_panel_version latest=$latest"
            if [[ $force == "true" || "$current_panel_version" != "$latest" ]]; then
                update_progress "Updating..." "Watashi Panel from $current_panel_version to $latest" 10
                # pip3 install -U watashipanel==$latest
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
            DO_NOT_RUN=true bash /opt/watashi-manager/install.sh docker --no-gui --no-log
            echo "installing in docker mode finishs"
        ;;
        v*)
            update_progress "Updating..." "Watashi Config from $current_config_version to $latest" 60
            export WATASHI_DISABLE_UPDATE=true
            #update_from_github "watashi-manager.tar.gz" "https://github.com/mn-hacker/Watashi-Manager/archive/refs/tags/${package_mode}.tar.gz" $latest
            update_from_github "watashi-manager.zip" "https://github.com/mn-hacker/Watashi-Manager/releases/download/${package_mode}/watashi-manager.zip" $latest
            update_progress "Updated..." "Watashi Config to $latest" 100
            return 0
        ;;
        develop|dev)
            local latest=$(get_dev_version Watashi-Manager)  # watashi dev-channel
            echo "DEVELOP: Current Config Version=$current_config_version -- Latest=$latest"
            if [[ "$force" == "true" || "$latest" != "$current_config_version" ]]; then
                update_progress "Updating..." "Watashi Config from $current_config_version to $latest" 60
                update_from_github "watashi-manager.zip" "https://github.com/mn-hacker/Watashi-Manager/releases/download/v${latest}/watashi-manager.zip" $latest  # watashi dev-channel: release zip has submodules; branch tarball does not
                
                update_progress "Updated..." "Watashi Config to $latest" 100
                return 0
            fi
        ;;
        beta)
            local latest=$(get_pre_release_version Watashi-Manager)
            echo "BETA: Current Config Version=$current_config_version -- Latest=$latest"
            if [[ "$force" == "true" || "$latest" != "$current_config_version" ]]; then
                update_progress "Updating..." "Watashi Config from $current_config_version to $latest" 60
                update_from_github "watashi-manager.zip" "https://github.com/mn-hacker/Watashi-Manager/releases/download/v$latest/watashi-manager.zip"
                update_progress "Updated..." "Watashi Config to $latest" 100
                return 0
            fi
        ;;
        release)
            # error "you can not install release version 8 using this script"
            # exit 1
            local latest=$(get_release_version Watashi-Manager)
            echo "RELEASE: Current Config Version=$current_config_version -- Latest=$latest"
            if [[ "$force" == "true" || "$latest" != "$current_config_version" ]]; then
                update_progress "Updating..." "Watashi Config from $current_config_version to $latest" 60
                update_from_github "watashi-manager.zip" "https://github.com/mn-hacker/Watashi-Manager/releases/latest/download/watashi-manager.zip"
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
        finish_progress "Updating..."
    fi
    remove_lock $NAME

    if [ "$package_mode" != "docker" ];then
      # Always stop panel first to ensure clean restart
      systemctl stop watashi-panel.service 2>/dev/null || true
      systemctl stop watashi-panel-background-tasks.service 2>/dev/null || true

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
          bash /opt/watashi-manager/apply_configs.sh --no-gui --no-log
      fi
      
      # Restart all core services to ensure new version is used
      echo "Restarting services..."
      systemctl daemon-reload
      systemctl restart watashi-redis.service 2>/dev/null || true
      sleep 1
      systemctl restart watashi-panel.service 2>/dev/null || true
      # watashi v12.3.35dev: the unit now has a start limit; one that was parked
      # in failed would ignore this restart without reset-failed.
      systemctl reset-failed watashi-panel-background-tasks.service 2>/dev/null || true
      systemctl restart watashi-panel-background-tasks.service 2>/dev/null || true
      type ws_check_background_tasks >/dev/null 2>&1 && ws_check_background_tasks
      
      cd /opt/watashi-manager/watashi-panel
      if [ "$CREATE_EASYSETUP_LINK" == "true" ];then
          watashi-panel-cli set-setting --key create_easysetup_link --val True
      fi

      case "$package_mode" in
          release|beta)
              watashi-panel-cli set-setting --key package_mode --val $package_mode
          ;;
          dev|develop)
              watashi-panel-cli set-setting --key package_mode --val develop
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
    mkdir -p /opt/watashi-manager
    cd /opt/watashi-manager
    # watashi v12.3.40dev: curl without -f saved GitHub's "Not Found" page as
    # the zip, unzip failed on it and install.sh still ran over the old files
    # as if the update had arrived. A failed download or unpack stops here.
    # The zip fetched early for the move from the old name (same address), or
    # one handed over in WATASHI_LOCAL_ZIP, is used instead of a new download.
    if [[ "$file_type" == "zip" && -n "$WATASHI_LOCAL_ZIP" && -s "$WATASHI_LOCAL_ZIP" ]]; then
        echo "using the release zip at $WATASHI_LOCAL_ZIP"
        cp -f "$WATASHI_LOCAL_ZIP" "$file_name" || return 1
    elif [[ "$file_type" == "zip" && -s "$WS_RELEASE_CACHE/watashi-manager.zip" && "$(cat "$WS_RELEASE_CACHE/url" 2>/dev/null)" == "$url" ]]; then
        echo "using the release zip downloaded at the start of this run"
        mv -f "$WS_RELEASE_CACHE/watashi-manager.zip" "$file_name" || return 1
    elif ! curl -fsSL --retry 3 -o "$file_name" "$url"; then
        rm -f "$file_name"
        error "the release could not be downloaded from $url, nothing was changed"
        return 1
    fi
    rm -rf "$WS_RELEASE_CACHE"
    
    if [[ "$file_type" == "zip" ]]; then
        install_package unzip
        if ! unzip -q -o "$file_name"; then
            rm -f "$file_name"
            error "the release zip from $url could not be unpacked"
            return 1
        fi
    elif [[ "$file_type" == "gz" ]]; then
        tar xzf "$file_name" --strip-components=1 || { rm -f "$file_name"; return 1; }
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
    rm -f /opt/watashi-manager/xray/configs/05_inbounds_10*.json*
    rm -f /opt/watashi-manager/xray/configs/05_inbounds_h2*.json*
    rm -f /opt/watashi-manager/xray/configs/05_inbounds_02_realitygrpc*.json*
    rm -f /opt/watashi-manager/xray/configs/05_inbounds_02_realityh2*.json*
    rm -f /opt/watashi-manager/singbox/configs/05_inbounds_2071_realitygrpc_main.json*
    rm -f /opt/watashi-manager/singbox/configs/05_inbounds_20[123][1234]*.json*

    bash install.sh --no-gui --no-log
    bash install.sh --no-gui --no-log #temporary fix
}

function custom_version_installer(){
    # watashi v12.3.40dev: the list came from PyPI, where this panel is not
    # published, so the picker offered someone else's versions (and now
    # nothing). It is read from the tags of our own repository, and only
    # releases from the rename on are offered: older ones are laid out under
    # the old name and cannot be installed over this one.
    TAGS=$(curl -fsL "https://api.github.com/repos/mn-hacker/Watashi-Manager/tags?per_page=100" | jq -r '.[].name' 2>/dev/null | sed 's/^v//' | sort -V -r)
    version_gt() {
        [ "$(printf '%s\n' "$@" | sort -V | head -n 1)" != "$1" ]
    }
    FILTERED_TAGS=("release" "" "beta" "" "dev" "")
    for tag in $TAGS; do
        if version_gt "$tag" "12.3.39z"; then
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
    # watashi v12.3.40dev: once the new panel answers, the last traces of the
    # old name (its database account, the folder link kept for scripts that
    # were still running) are let go. It checks for itself and does nothing
    # when the panel is not up.
    if [ -f /opt/watashi-manager/common/watashi_legacy.sh ]; then
        bash /opt/watashi-manager/common/watashi_legacy.sh finish || true
    fi
else
    
    show_progress_window --subtitle "Installer" --log $LOG_FILE $0 $@ --no-gui --no-log
    
    error_code=$?
    if [[ $error_code != "0" ]]; then
        # echo less -r -P"Installation Failed! Press q to exit" +G "$log_file"
        msg_with_watashi "Installation Failed! code=$error_code"
    else
        msg_with_watashi "The installation has successfully completed."
        check_watashi_panel $@ |& tee -a $LOG_FILE
        read -p "Press any key to go  to menu" -n 1 key
    fi
    bash /opt/watashi-manager/menu.sh
fi
exit $error_code
