#!/bin/bash
# watashi v12.3.40dev: the old project name was taken out of this file (names, paths and links only)
# Watashi v12.2.37 : only the words on screen changed here
cd $(dirname -- "$0")
source ./common/utils.sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# Create necessary directories and define constants

NAME="update"
LOG_FILE="$(log_file $NAME)"
function cleanup() {
    error "Script interrupted. Exiting..."
    # disable_ansii_modes
    #    reset
    remove_lock $NAME
    exit 1
}

trap cleanup SIGINT

function main() {
    update_progress "Watashi Updater" "Checking for update" 1
    echo "Checking for update..."
    local force=false
    local manager_update=0
    local panel_update=0

    if [[ -n "$1" ]]; then
        local package_mode=$1
        force=true
    else
        local package_mode=$(get_package_mode)
    fi
    local current_config_version=$(get_installed_config_version)
    local current_panel_version=$(get_installed_panel_version)

    # watashi v12.3.40dev: an old commented-out call to common/downgrade.sh stood here; that
    # script (an unused upstream downgrade that took the panel from PyPI) was removed.

    rm -rf sniproxy caddy
    update_progress "Watashi Updater" "Creating a backup" 5
    echo "Creating a backup ..."
    ./watashi-panel/backup.sh

    update_script="https://raw.githubusercontent.com/mn-hacker/Watashi-Manager/refs/heads/main/common/download.sh"
    case "$package_mode" in
    develop)
        # watashi dev-channel: use get_dev_version (get_commit_version returns empty;
        # the dev branch does not exist, so its download.sh cannot be fetched)
        latest_manager=$(get_dev_version Watashi-Manager)
        latest_panel=$latest_manager
        update_script="https://raw.githubusercontent.com/mn-hacker/Watashi-Manager/refs/heads/main/common/download.sh"
        ;;
    beta)
        # Use tags instead of releases for beta - only check Watashi-Manager
        latest_manager=$(get_pre_release_version Watashi-Manager)
        latest_panel=$latest_manager
        update_script="https://raw.githubusercontent.com/mn-hacker/Watashi-Manager/refs/heads/main/common/download.sh"
        ;;
    release)
        latest_manager=$(get_release_version Watashi-Manager)
        latest_panel=$latest_manager
        update_script="https://raw.githubusercontent.com/mn-hacker/Watashi-Manager/refs/heads/main/common/download.sh"
        ;;
    esac

    [[ "$latest_panel" != "$current_panel_version" ]] && panel_update=1
    [[ "$latest_manager" != "$current_config_version" ]] && manager_update=1
    echo "$package_mode Latest panel version: $latest_panel Installed: $current_panel_version Lastest manager version: $latest_manager Installed: $current_config_version"
    if [[ "$force" == "true" || $panel_update == 1 || $manager_update == 1 ]]; then
        bash <(curl -sSL $update_script) "$package_mode" "$force" "--no-gui" "--no-log"
    else
        echo "Nothing to update"
    fi
    remove_lock $NAME
    finish_progress "Updating..."

}
if [[ "$WATASHI_DISABLE_UPDATE" == "1" || "$WATASHI_DISABLE_UPDATE" == "true" ]];then
    error "Updating is disabled because env variable WATASHI_DISABLE_UPDATE == $WATASHI_DISABLE_UPDATE"
    exit 9
elif [[ " $@ " == *" --no-gui "* ]]; then
    set -- "${@/--no-gui/}"
    set_lock $NAME
    if [[ " $@ " == *" --no-log "* ]]; then
        set -- "${@/--no-log/}"
        main "$@"
    else
        main "$@" |& tee $LOG_FILE
    fi
    error_code=$?
    remove_lock $NAME
else
    show_progress_window --subtitle "Updater" --log $LOG_FILE ./update.sh $@ --no-gui --no-log
    error_code=$?
    if [[ $error_code != "0" ]]; then
        # echo less -r -P"Installation Failed! Press q to exit" +G "$log_file"
        msg_with_watashi "Installation Failed! code=$error_code"
    else
        msg_with_watashi "The update has successfully completed."
        check_watashi_panel $@ |& tee -a $LOG_FILE
    fi
fi
exit $error_code
