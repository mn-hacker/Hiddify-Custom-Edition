#!/bin/bash
# cd "$(dirname -- "$0")"
cd /opt/hiddify-manager/
source common/utils.sh

sed -i "s|/opt/hiddify-config/menu.sh|/opt/hiddify-manager/menu.sh|g" ~/.bashrc
sed -i "s|/opt/hiddify-server/menu.sh|/opt/hiddify-manager/menu.sh|g" ~/.bashrc

if [[ $(grep "/opt/hiddify-manager/menu.sh" ~/.bashrc | wc -l) > 0 ]]; then
    sed -i "s|/opt/hiddify-manager/menu.sh||g" ~/.bashrc
    sed -i "s|cd /opt/hiddify-manager/||g" ~/.bashrc
    echo "/opt/hiddify-manager/menu.sh" >>~/.bashrc
    echo "cd /opt/hiddify-manager/" >>~/.bashrc
fi


if ! grep -rxq "PasswordAuthentication.*no" /etc/ssh/sshd*; then
    # @hiddify/@iam54r1n4 make a better message with a link to why should disable pass-auth
    WARNING_MSG="Your server is vulnerable to abuses because PasswordAuthentication is enabled. To secure your server, please switch to key authentication mechanism and turn off PasswordAuthentication in your ssh config file."
    whiptail --title "WARNING" --msgbox "$WARNING_MSG" 10 78
fi
#PACKAGE_MODE=$(get_package_mode)
#LATEST_CONFIG_VERSION=$(get_release_version hiddify-manager)
#LATEST_PANEL_VERSION=$(get_release_version hiddifypanel)


# if [[ "$PACKAGE_MODE" == "develop" ]] || [[ "$CURRENT_CONFIG_VERSION" == "$LATEST_CONFIG_VERSION" && "$CURRENT_PANEL_VERSION" == "$LATEST_PANEL_VERSION" ]]; then
#     UPDATE_NEED=""
# else
#     UPDATE_NEED="*UPDATE AVAILABLE* Config=v$LATEST_CONFIG_VERSION Panel=v$LATEST_PANEL_VERSION"
# fi


export CURRENT_CONFIG_VERSION=$(get_installed_config_version)
export CURRENT_PANEL_VERSION=$(get_installed_panel_version)
export WS_VERSION_LINE="Config=v$CURRENT_CONFIG_VERSION Panel=v$CURRENT_PANEL_VERSION"

# --- Watashi v12.2.37 : the old whiptail home screen, kept as the safety net ---
function menu_classic() {
    whiptail --clear \
        --backtitle "$BACKTITLE" \
        --title "$TITLE" \
        --menu "$MENU" \
        $HEIGHT $WIDTH $CHOICE_HEIGHT \
        "${OPTIONS[@]}" \
        3>&1 1>&2 2>&3
}

function menu() {
    

    HEIGHT=20
    WIDTH=70
    CHOICE_HEIGHT=12
    # watashi v12.2.84: one name, spaced the way the banner writes it
    WS_TITLE_WORD="W A T A S H I   M A N A G E R"
    BACKTITLE="$WS_TITLE_WORD (Config=v$CURRENT_CONFIG_VERSION Panel=v$CURRENT_PANEL_VERSION)   $UPDATE_NEED  "
    TITLE="$WS_TITLE_WORD"
    WS_SUB="$WS_TAG   $UPDATE_NEED"
    MENU="Choose one of the following options:"

    OPTIONS=(status "View status of system"
        admin "Show admin link"
        log "Read the system logs"
        restart "Restart Services without changing the configs"
        install "Reinstall the server"
        update "Update $UPDATE_NEED"
        advanced "Uninstall, Remote Assistant, Downgrade,..."
        Quit ""
    )

    # our own home screen first, the classic box if it cannot run
    CHOICE=""
    if declare -F ws_menu >/dev/null 2>&1; then
        ws_menu "$WS_SUB" \
            status "View the state of the system" \
            admin "Show the admin link" \
            log "Read the system logs" \
            restart "Restart the services, configs untouched" \
            install "Reinstall the server" \
            update "Update $UPDATE_NEED" \
            advanced "Uninstall, remote assistant, downgrade, ..." \
            Quit "Leave the menu"
        WS_CODE=$?
        if [[ $WS_CODE == 1 ]]; then
            clear
            exit 1
        fi
        if [[ $WS_CODE == 0 ]]; then
            CHOICE="$WS_MENU_CHOICE"
        fi
    fi
    if [[ -z "$CHOICE" ]]; then
        CHOICE=$(menu_classic)
        if [[ $? != 0 ]]; then
            clear
            exit 1
        fi
    fi
    clear
    echo "Watashi: Command $CHOICE"
    echo "=========================================="
    NEED_KEY=1
    case $CHOICE in
    "") exit 1 ;;
    "Quit") exit 1 ;;
    'log')
        W=()
        while read -r line; do
            size=$(ls -lah log/system/"$line" | awk -F " " '{print $5}')
            W+=("$line" "$size")
        done < <(ls -1 log/system)
        LOG=$(whiptail --clear \
            --backtitle "$BACKTITLE" \
            --title "$TITLE" \
            --menu "$MENU" \
            $HEIGHT $WIDTH $CHOICE_HEIGHT \
            "${W[@]}" \
            3>&1 1>&2 2>&3)
        clear
        echo -e "\033[0m"
        if [[ $LOG != "" ]]; then
            less -r -P"Press q to exit" +G "log/system/$LOG"
        fi
        NEED_KEY=0
        ;;
    "advanced")
        OPTIONS=(
            warp "Check Warp Status"
            add_remote "Add remote assistant access to this server"
            remove_remote "Remove remote assistant access to this server"
            enable "show this menu on start up"
            disable "disable this menu"
            uninstall "Uninstall the panel :("
            purge "Uninstall completely and remove database :("
            Back ""
        )
        CHOICE=$(whiptail --clear --backtitle "$BACKTITLE" --title "$TITLE" --menu "$MENU" $HEIGHT $WIDTH $CHOICE_HEIGHT "${OPTIONS[@]}" 3>&1 1>&2 2>&3)
        case $CHOICE in
        "enable")
            echo "/opt/hiddify-manager/menu.sh" >>~/.bashrc
            echo "cd /opt/hiddify-manager/" >>~/.bashrc
            NEED_KEY=0
            ;;
        "disable")
            sed -i "s|/opt/hiddify-manager/menu.sh||g" ~/.bashrc
            sed -i "s|cd /opt/hiddify-manager/||g" ~/.bashrc
            NEED_KEY=0
            ;;
        "uninstall")
            # watashi v12.2.130k: the question is asked here, in the same kind of
            # box as the rest of the menu, and uninstall.sh is then told not to
            # ask again. Before this, the menu asked nothing and the script
            # asked twice, the second time in the middle of the work.
            if whiptail --clear --backtitle "$BACKTITLE" --title "Uninstall" \
                --yes-button "Uninstall" --no-button "Cancel" --defaultno \
                --yesno "Remove the panel from this server?\n\nThe database, the backups and your settings stay where they are, so installing again brings your users back." 14 70; then
                bash uninstall.sh --yes
            else
                NEED_KEY=0
            fi
            ;;
        "purge")
            if whiptail --clear --backtitle "$BACKTITLE" --title "Purge" \
                --yes-button "Erase everything" --no-button "Cancel" --defaultno \
                --yesno "Erase the panel and everything it owns?\n\nUsers, admins, domains, certificates, backups and the database are all deleted. This cannot be undone and there is no way back without a backup you saved elsewhere." 15 70; then
                WS_DB_SERVER=""
                if whiptail --clear --backtitle "$BACKTITLE" --title "Purge" \
                    --yes-button "Remove it too" --no-button "Keep it" --defaultno \
                    --yesno "MariaDB is the database server itself. Other software on this server may be using it.\n\nRemove MariaDB as well?" 12 70; then
                    WS_DB_SERVER="--remove-db-server"
                fi
                bash uninstall.sh purge --yes $WS_DB_SERVER
            else
                NEED_KEY=0
            fi
            ;;
        "add_remote")
            bash common/add_remote_assistant.sh
            ;;
        "remove_remote")
            bash common/remove_remote_assistant.sh
            ;;
        "warp")
            (
                cd other/warp/
                bash status.sh | less -r -P"Press q to exit" +G
            )
            NEED_KEY=0
            ;;
        *) NEED_KEY=0 ;;
        esac
        ;;

    "update")
        OPTIONS=(default "Based on the configuration in panel"
                release "stable (suggested) $UPDATE_NEED"
                beta "pre-release version - may have bugs"
                Back ""
        )
        CHOICE=$(whiptail --clear --backtitle "$BACKTITLE" --title "$TITLE" --menu "$MENU" $HEIGHT $WIDTH $CHOICE_HEIGHT "${OPTIONS[@]}" 3>&1 1>&2 2>&3)
        case $CHOICE in
        "default")
            bash update.sh
            ;;
        "release")
            bash update.sh release
            ;;
        "beta")
            bash update.sh beta
            ;;
        *) NEED_KEY=0 ;;
        esac
        export CURRENT_CONFIG_VERSION=$(get_installed_config_version)
        export CURRENT_PANEL_VERSION=$(get_installed_panel_version)
        export WS_VERSION_LINE="Config=v$CURRENT_CONFIG_VERSION Panel=v$CURRENT_PANEL_VERSION"

        ;;
    "admin")
        source common/utils.sh
        check_hiddify_panel
        declare -F ws_flush_keys >/dev/null 2>&1 && ws_flush_keys
        read -p "Press 'r' to reset admin password or press any other key to return to the main menu: " -n 1 key
        echo  # This adds a newline for better output readability
        if [[ "$key" == 'r' ]]; then
            echo "reseting owner password..."
            hiddify-panel-cli reset-owner-password
        fi
        NEED_KEY=0
        ;;
    "status")
        bash status.sh | less -r -P"Press q to exit" +G
        NEED_KEY=0
        ;;
    *)
        bash "$CHOICE.sh"
        ;;
    esac

    if [[ $NEED_KEY == 1 ]]; then
        declare -F ws_flush_keys >/dev/null 2>&1 && ws_flush_keys
        read -p "Press any key to return to menu" -n 1 key
    fi

    return 0
}

# One turn of the menu per round. The old code called itself, so every
# visit left another frame on the stack. The loop keeps that flat and,
# more importantly, keys typed during a long job are dropped before the
# next screen is drawn, so the panel never opens an option on its own.
while true; do
    declare -F ws_flush_keys >/dev/null 2>&1 && ws_flush_keys
    menu
done
