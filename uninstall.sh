#!/bin/bash
# Watashi Manager remover, v12.2.130k
#
# Two jobs, one script:
#
#   ./uninstall.sh              take the panel off this server, keep the
#                               database, the backups and the secrets so a
#                               reinstall finds its users again
#   ./uninstall.sh purge        leave nothing behind: files, database, units,
#                               cron, certificates, sysctl, accounts
#
# Flags:
#   --yes              do not ask (for scripts and for the menu, which asks
#                      its own question before calling this)
#   --remove-db-server also take MariaDB itself off the box. Off by default,
#                      because other software on the server may be using it.
#                      Purge always drops our own database and our own user.
#
# The old version asked twice: once for the word "yes" and then again, in the
# middle of the work, whether MariaDB should go. The second question arrived
# after the panel was already gone and there was no good way to answer it, so
# it is a flag now and the script never stops half way.

cd "$(dirname -- "$0")" || exit 1
source ./common/utils.sh 2>/dev/null || true

PURGE_MODE=false
ASSUME_YES=false
REMOVE_DB_SERVER=false
for arg in "$@"; do
    case "$arg" in
    purge) PURGE_MODE=true ;;
    --yes | -y | --assume-yes) ASSUME_YES=true ;;
    --remove-db-server) REMOVE_DB_SERVER=true ;;
    esac
done

PANEL_DIR=/opt/hiddify-manager
LOG_FILE=/tmp/watashi-uninstall.log
DB_NAME=hiddifypanel
DB_USER=hiddifypanel

function log() {
    echo "[$(date '+%H:%M:%S')] $1"
}

function ws_mysql() {
    # root over the unix socket is how every other script on this box talks to
    # the server; if MariaDB is already gone this simply does nothing.
    mysql -u root -e "$1" >/dev/null 2>&1 || true
}

echo "============================================="
if [[ "$PURGE_MODE" == "true" ]]; then
    echo "  Watashi Manager - PURGE"
    echo "  Everything goes: panel, database, users, certificates."
else
    echo "  Watashi Manager - uninstall"
    echo "  The panel goes. Database, backups and secrets stay,"
    echo "  so installing again brings your users back."
fi
echo "============================================="
echo ""

if [[ "$ASSUME_YES" != "true" ]]; then
    if [[ "$PURGE_MODE" == "true" ]]; then
        echo "This cannot be undone. Type PURGE to go ahead, anything else to stop."
        read -r -p "> " confirm
        if [[ "$confirm" != "PURGE" ]]; then
            echo "Nothing was touched."
            exit 0
        fi
    else
        read -r -p "Remove the panel and keep the data? [y/N] " confirm
        if [[ "${confirm,,}" != "y" && "${confirm,,}" != "yes" ]]; then
            echo "Nothing was touched."
            exit 0
        fi
    fi
fi

# One last backup before an uninstall, because the whole point of keeping the
# database is being able to come back to it.
function ws_final_backup() {
    [[ "$PURGE_MODE" == "true" ]] && return 0
    local cli="$PANEL_DIR/.venv313/bin/hiddify-panel-cli"
    [[ -x "$cli" ]] || cli=$(ls -1 "$PANEL_DIR"/.venv*/bin/hiddify-panel-cli 2>/dev/null | head -1)
    if [[ -x "$cli" ]]; then
        log "Taking one last backup..."
        (cd "$PANEL_DIR/hiddify-panel" && "$cli" backup >/dev/null 2>&1) || log "  the backup did not run, moving on"
    fi
}

SERVICES=(
    hiddify-panel
    hiddify-panel-background-tasks
    hiddify-singbox
    hiddify-xray
    hiddify-nginx
    hiddify-haproxy
    hiddify-redis
    hiddify-warp
    hiddify-cli
    hiddify-ssh-liberty-bridge
    hiddify-ss-faketls
    hiddify-caddy
    watashi-mita
    watashi-cert-renew.timer
    watashi-cert-renew
    telemt
    mtproxy
    shadowtls
    rathole
    wg-quick@warp
)

function main() {
    ws_final_backup

    log "Stopping services..."
    for service in "${SERVICES[@]}"; do
        systemctl stop "$service" >/dev/null 2>&1
        systemctl disable "$service" >/dev/null 2>&1
        systemctl reset-failed "$service" >/dev/null 2>&1
    done

    log "Removing unit files..."
    # watashi v12.2.130k: the old list only knew hiddify-*, so watashi-mita,
    # the certificate renewal timer and telemt stayed behind as enabled units
    # aimed at files that were about to be deleted. That is where the endless
    # "Failed to open /etc/systemd/system/watashi-mita.service" came from.
    rm -f /etc/systemd/system/hiddify-*.service
    rm -f /etc/systemd/system/watashi-*.service /etc/systemd/system/watashi-*.timer
    rm -f /etc/systemd/system/telemt.service /etc/systemd/system/mtproxy.service
    rm -f /etc/systemd/system/shadowtls.service /etc/systemd/system/rathole.service
    rm -f /etc/systemd/system/wg-quick@warp.service
    rm -f /etc/systemd/system/multi-user.target.wants/hiddify-*.service
    rm -f /etc/systemd/system/multi-user.target.wants/watashi-*.service
    rm -f /etc/systemd/system/timers.target.wants/watashi-*.timer
    rm -f /etc/systemd/system/multi-user.target.wants/telemt.service
    systemctl daemon-reload
    systemctl reset-failed >/dev/null 2>&1

    log "Removing cron jobs..."
    rm -f /etc/cron.d/hiddify* /etc/cron.d/watashi*
    rm -f /etc/cron.daily/hiddify* /etc/cron.daily/watashi*
    service cron reload >/dev/null 2>&1 || true

    log "Removing the WARP interface..."
    ip link del warp >/dev/null 2>&1 || true
    rm -f /etc/wireguard/warp.conf

    log "Removing web server configs..."
    rm -f /etc/nginx/sites-enabled/hiddify* /etc/nginx/sites-available/hiddify*
    rm -f /etc/nginx/conf.d/hiddify* /etc/haproxy/haproxy.cfg.hiddify*
    systemctl restart nginx >/dev/null 2>&1 || true
    systemctl restart haproxy >/dev/null 2>&1 || true

    log "Removing shortcuts and the boot menu..."
    rm -f /usr/local/bin/hiddify* /usr/bin/hiddify* /usr/local/bin/watashi*
    rm -f /opt/hiddify-config /opt/hiddify-server
    sed -i '/hiddify-manager/d;/hiddify-config/d;/watashi/d' ~/.bashrc 2>/dev/null || true

    if [[ "$PURGE_MODE" != "true" ]]; then
        ws_uninstall_keep_data
    else
        ws_purge_everything
    fi

    ws_leftovers
}

function ws_uninstall_keep_data() {
    log "Removing panel files, keeping data..."
    # What is worth keeping: the backups, the database password (without it the
    # existing database cannot be opened again) and app.cfg, which holds the
    # panel's own secret key.
    local keep=/opt/watashi-keep
    rm -rf "$keep"
    mkdir -p "$keep"
    cp -a "$PANEL_DIR/backup" "$keep/" 2>/dev/null
    cp -a "$PANEL_DIR/hiddify-panel/backup" "$keep/panel-backup" 2>/dev/null
    cp -a "$PANEL_DIR/other/mysql/mysql_pass" "$keep/" 2>/dev/null
    cp -a "$PANEL_DIR/hiddify-panel/app.cfg" "$keep/" 2>/dev/null
    cp -a "$PANEL_DIR/current.json" "$keep/" 2>/dev/null

    rm -rf "$PANEL_DIR"
    mkdir -p "$PANEL_DIR/other/mysql" "$PANEL_DIR/hiddify-panel"
    cp -a "$keep/backup" "$PANEL_DIR/" 2>/dev/null
    cp -a "$keep/panel-backup" "$PANEL_DIR/hiddify-panel/backup" 2>/dev/null
    cp -a "$keep/mysql_pass" "$PANEL_DIR/other/mysql/" 2>/dev/null
    cp -a "$keep/app.cfg" "$PANEL_DIR/hiddify-panel/" 2>/dev/null
    cp -a "$keep/current.json" "$PANEL_DIR/" 2>/dev/null
    chmod 600 "$PANEL_DIR/other/mysql/mysql_pass" 2>/dev/null
    chmod 600 "$PANEL_DIR/hiddify-panel/app.cfg" 2>/dev/null
    rm -rf "$keep"

    log "============================================="
    log "Done. The database and the backups are still here:"
    log "  $PANEL_DIR/backup"
    log "Install again and your users come back."
    log "============================================="
}

function ws_purge_everything() {
    log "Dropping the database..."
    # The old script dropped "hiddify_panel", a name this panel has never used;
    # ours is hiddifypanel, created by other/mysql/install.sh.
    ws_mysql "DROP DATABASE IF EXISTS $DB_NAME;"
    ws_mysql "DROP USER IF EXISTS '$DB_USER'@'localhost';"
    ws_mysql "DROP DATABASE IF EXISTS hiddify_panel;"
    ws_mysql "DROP USER IF EXISTS 'hiddify'@'localhost';"
    ws_mysql "FLUSH PRIVILEGES;"

    log "Removing certificates..."
    rm -rf /root/.acme.sh

    log "Removing every panel file..."
    cd /
    rm -rf "$PANEL_DIR"
    rm -rf /tmp/hiddify /tmp/hiddify-* /tmp/watashi-* /tmp/ws-*
    rm -rf /var/lib/private/telemt /var/lib/telemt
    rm -rf /var/log/hiddify*
    rm -f /etc/sysctl.d/98-watashi-*.conf
    sysctl --system >/dev/null 2>&1 || true

    log "Removing the accounts the panel made..."
    # mita runs under its own account; ssh-liberty-bridge adds panel users to
    # the box, and those are removed with the database anyway.
    userdel mita >/dev/null 2>&1 || true
    groupdel mita >/dev/null 2>&1 || true

    log "Removing the python package..."
    pip3 uninstall -y hiddifypanel >/dev/null 2>&1 || true

    if [[ "$REMOVE_DB_SERVER" == "true" ]]; then
        log "Removing MariaDB as asked..."
        apt purge -y mariadb-server mariadb-client >/dev/null 2>&1 || true
        apt purge -y mysql-server mysql-client >/dev/null 2>&1 || true
        rm -rf /var/lib/mysql
        apt autoremove -y >/dev/null 2>&1 || true
    else
        log "MariaDB stays on the server (--remove-db-server takes it too)."
    fi

    log "============================================="
    log "PURGE COMPLETE. Nothing of the panel is left."
    log "============================================="
}

function ws_leftovers() {
    # Saying "complete" is easy; showing it is better. Anything printed here is
    # something the removal missed.
    local found=0
    local paths=(
        /etc/systemd/system/hiddify-panel.service
        /etc/systemd/system/watashi-mita.service
        /etc/systemd/system/telemt.service
        /etc/cron.d/hiddify_auto_backup
        /opt/hiddify-config
        /root/.acme.sh
    )
    [[ "$PURGE_MODE" == "true" ]] && paths+=("$PANEL_DIR")
    log "Checking what is left..."
    for p in "${paths[@]}"; do
        if [[ -e "$p" ]]; then
            log "  still here: $p"
            found=1
        fi
    done
    if [[ "$PURGE_MODE" == "true" ]] && mysql -u root -e "USE $DB_NAME;" >/dev/null 2>&1; then
        log "  still here: the $DB_NAME database"
        found=1
    fi
    if systemctl list-units --all --no-legend 'hiddify-*' 'watashi-*' 'telemt*' 2>/dev/null | grep -q .; then
        log "  systemd still lists panel units, a reboot clears the last of them"
    fi
    [[ "$found" == "0" ]] && log "  nothing left behind."
    return 0
}

main 2>&1 | tee "$LOG_FILE"

echo ""
echo "The log of this run is at: $LOG_FILE"
