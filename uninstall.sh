#!/bin/bash
# watashi v12.3.40dev: the old project name was taken out of this file (names, paths and links only)
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

PANEL_DIR=/opt/watashi-manager
LOG_FILE=/tmp/watashi-uninstall.log
DB_NAME=watashipanel
DB_USER=watashipanel

# watashi v12.2.130z: a step that takes minutes is invisible in a log that only
# carries a wall clock, so every line also says how long the run has been
# going. SECONDS starts at zero when bash starts.
function log() {
    echo "[$(date '+%H:%M:%S')] (+${SECONDS}s) $1"
}

function ws_mysql() {
    # root over the unix socket is how every other script on this box talks to
    # the server; if MariaDB is already gone this simply does nothing.
    # watashi v12.2.130z: without a lock wait of its own, a DROP DATABASE waits for
    # the server default, which is a year. That is the five minute pause at
    # the end of a purge: the statement was not slow, it was waiting.
    timeout 30 mysql --connect-timeout=5 -u root \
        -e "SET SESSION lock_wait_timeout=15; SET SESSION innodb_lock_wait_timeout=15; $1" >/dev/null 2>&1 || true
}

function ws_free_database() {
    # watashi v12.2.130z: a database cannot be dropped while another session still
    # holds a table of it open. Gunicorn and celery keep a pool of such
    # sessions, and a worker that outlived its unit keeps them open for as
    # long as it lives. They are ended here, before the drop is asked for.
    pkill -f watashipanel >/dev/null 2>&1 || true
    pkill -f "gunicorn.*watashi" >/dev/null 2>&1 || true
    pkill -f "celery.*watashi" >/dev/null 2>&1 || true
    local ids id
    ids=$(timeout 10 mysql --connect-timeout=3 -u root -N -B -e \
        "SELECT id FROM information_schema.processlist WHERE db = '$DB_NAME' AND id <> CONNECTION_ID();" 2>/dev/null)
    for id in $ids; do
        timeout 10 mysql --connect-timeout=3 -u root -e "KILL $id;" >/dev/null 2>&1 || true
    done
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
    local cli="$PANEL_DIR/.venv313/bin/watashi-panel-cli"
    [[ -x "$cli" ]] || cli=$(ls -1 "$PANEL_DIR"/.venv*/bin/watashi-panel-cli 2>/dev/null | head -1)
    if [[ -x "$cli" ]]; then
        log "Taking one last backup..."
        (cd "$PANEL_DIR/watashi-panel" && "$cli" backup >/dev/null 2>&1) || log "  the backup did not run, moving on"
    fi
}

SERVICES=(
    watashi-panel
    watashi-panel-background-tasks
    watashi-singbox
    watashi-xray
    watashi-nginx
    watashi-haproxy
    watashi-redis
    watashi-warp
    watashi-ssh-liberty-bridge
    watashi-ss-faketls
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
    # watashi v12.2.130z: systemd gives a unit ninety seconds to stop on its own.
    # A unit stuck in activating uses every one of them, so it is given ten
    # and then killed.
    for service in "${SERVICES[@]}"; do
        timeout 10 systemctl stop "$service" >/dev/null 2>&1 || systemctl kill -s KILL "$service" >/dev/null 2>&1
        timeout 10 systemctl disable "$service" >/dev/null 2>&1
        systemctl reset-failed "$service" >/dev/null 2>&1
    done

    log "Removing unit files..."
    # watashi v12.2.130k: the old list only knew the core units, so watashi-mita,
    # the certificate renewal timer and telemt stayed behind as enabled units
    # aimed at files that were about to be deleted. That is where the endless
    # "Failed to open /etc/systemd/system/watashi-mita.service" came from.
    # watashi v12.3.40dev: the rename left two copies of some lines here; one
    # of each is enough. Units from before the rename are removed further down
    # by common/watashi_legacy.sh.
    rm -f /etc/systemd/system/watashi-*.service /etc/systemd/system/watashi-*.timer
    rm -f /etc/systemd/system/telemt.service /etc/systemd/system/mtproxy.service
    rm -f /etc/systemd/system/shadowtls.service /etc/systemd/system/rathole.service
    rm -f /etc/systemd/system/wg-quick@warp.service
    rm -f /etc/systemd/system/multi-user.target.wants/watashi-*.service
    rm -f /etc/systemd/system/timers.target.wants/watashi-*.timer
    rm -f /etc/systemd/system/multi-user.target.wants/telemt.service
    systemctl daemon-reload
    systemctl reset-failed >/dev/null 2>&1

    log "Removing cron jobs..."
    rm -f /etc/cron.d/watashi* /etc/cron.daily/watashi* /etc/cron.hourly/watashi*
    service cron reload >/dev/null 2>&1 || true

    log "Removing the WARP interface..."
    ip link del warp >/dev/null 2>&1 || true
    rm -f /etc/wireguard/warp.conf

    log "Removing web server configs..."
    rm -f /etc/nginx/sites-enabled/watashi* /etc/nginx/sites-available/watashi*
    rm -f /etc/nginx/conf.d/watashi* /etc/haproxy/haproxy.cfg.watashi*
    # watashi v12.2.130z: during a purge these two are on their way out, and haproxy
    # without a config file only retries and waits. Restart them only when
    # the panel is being removed but the box keeps serving.
    if [[ "$PURGE_MODE" == "true" ]]; then
        timeout 10 systemctl stop nginx >/dev/null 2>&1 || true
        timeout 10 systemctl stop haproxy >/dev/null 2>&1 || true
    else
        timeout 20 systemctl restart nginx >/dev/null 2>&1 || true
        timeout 20 systemctl restart haproxy >/dev/null 2>&1 || true
    fi

    log "Removing shortcuts and the boot menu..."
    rm -f /usr/local/bin/watashi* /usr/bin/watashi*
    # watashi v12.3.40dev: the two compatibility links from before the rename
    # and their .bashrc lines are handled by common/watashi_legacy.sh below.
    sed -i '/watashi-manager/d;/watashi/d' ~/.bashrc 2>/dev/null || true
    # watashi v12.2.130k: the acme.sh installer adds a line that sources
    # /root/.acme.sh/acme.sh.env from the login shell. Removing the folder
    # without removing that line greeted every later ssh login with
    # "-bash: /root/.acme.sh/acme.sh.env: No such file or directory".
    for rc in ~/.bashrc ~/.profile ~/.bash_profile /etc/profile.d/acme.sh.sh; do
        [[ -f "$rc" ]] && sed -i '/acme\.sh\.env/d' "$rc" 2>/dev/null
    done
    rm -f /etc/profile.d/acme.sh.sh
    crontab -l 2>/dev/null | grep -v 'acme.sh' | crontab - 2>/dev/null || true

    # watashi v12.3.40dev: the system files this panel owns under its current
    # name. The sysctl link points into the folder that is about to go, and the
    # other three only make sense while the panel is here.
    rm -f /etc/sysctl.d/watashi.conf /etc/sysctl.d/watashi-ipv6.conf /etc/sysctl.d/watashi-reserved.conf
    rm -f /etc/sudoers.d/watashi /etc/logrotate.d/watashi-manager

    # watashi v12.3.40dev: anything a server still carries from the time before
    # the rename (units, cron, sysctl, accounts, links). Its own script, so the
    # old names live in one file only. Only a purge takes the old database too.
    log "Removing what was left from before the rename..."
    if [[ -f ./common/watashi_legacy.sh ]]; then
        if [[ "$PURGE_MODE" == "true" ]]; then
            bash ./common/watashi_legacy.sh purge --data 2>&1 | sed 's/^/  /'
        else
            bash ./common/watashi_legacy.sh purge 2>&1 | sed 's/^/  /'
        fi
    fi

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
    cp -a "$PANEL_DIR/watashi-panel/backup" "$keep/panel-backup" 2>/dev/null
    cp -a "$PANEL_DIR/other/mysql/mysql_pass" "$keep/" 2>/dev/null
    cp -a "$PANEL_DIR/watashi-panel/app.cfg" "$keep/" 2>/dev/null
    cp -a "$PANEL_DIR/current.json" "$keep/" 2>/dev/null

    rm -rf "$PANEL_DIR"
    mkdir -p "$PANEL_DIR/other/mysql" "$PANEL_DIR/watashi-panel"
    cp -a "$keep/backup" "$PANEL_DIR/" 2>/dev/null
    cp -a "$keep/panel-backup" "$PANEL_DIR/watashi-panel/backup" 2>/dev/null
    cp -a "$keep/mysql_pass" "$PANEL_DIR/other/mysql/" 2>/dev/null
    cp -a "$keep/app.cfg" "$PANEL_DIR/watashi-panel/" 2>/dev/null
    cp -a "$keep/current.json" "$PANEL_DIR/" 2>/dev/null
    chmod 600 "$PANEL_DIR/other/mysql/mysql_pass" 2>/dev/null
    chmod 600 "$PANEL_DIR/watashi-panel/app.cfg" 2>/dev/null
    rm -rf "$keep"

    log "============================================="
    log "Done. The database and the backups are still here:"
    log "  $PANEL_DIR/backup"
    log "Install again and your users come back."
    log "============================================="
}

function ws_purge_everything() {
    log "Dropping the database..."
    ws_free_database
    # Ours is watashipanel, created by other/mysql/install.sh.
    # watashi v12.3.40dev: the two extra DROPs for a name this panel never used
    # are gone; the database from before the rename is dropped by
    # watashi_legacy.sh purge --data above.
    ws_mysql "DROP DATABASE IF EXISTS $DB_NAME;"
    ws_mysql "DROP USER IF EXISTS '$DB_USER'@'localhost';"
    ws_mysql "FLUSH PRIVILEGES;"

    log "Removing certificates..."
    rm -rf /root/.acme.sh

    log "Removing every panel file..."
    cd /
    rm -rf "$PANEL_DIR"
    rm -rf /tmp/watashi /tmp/watashi-* /tmp/ws-*
    rm -rf /var/lib/private/telemt /var/lib/telemt
    rm -rf /var/log/watashi*
    rm -f /etc/sysctl.d/98-watashi-*.conf
    sysctl --system >/dev/null 2>&1 || true

    log "Removing the accounts the panel made..."
    # mita runs under its own account; ssh-liberty-bridge adds panel users to
    # the box, and those are removed with the database anyway.
    userdel mita >/dev/null 2>&1 || true
    groupdel mita >/dev/null 2>&1 || true
    # watashi v12.3.40dev: the panel's own account (watashi-panel/install.sh)
    # and the group common/install.sh made for it and root stayed behind with
    # the home folder, and so did the two tunnels of the panel: their units
    # were still enabled and brought the interfaces back after a reboot.
    if id watashi-panel >/dev/null 2>&1; then
        pkill -KILL -u watashi-panel >/dev/null 2>&1 || true
        userdel -r watashi-panel >/dev/null 2>&1 || userdel watashi-panel >/dev/null 2>&1 || true
    fi
    getent group watashi-panel >/dev/null 2>&1 && groupdel watashi-panel >/dev/null 2>&1
    getent group watashi-common >/dev/null 2>&1 && groupdel watashi-common >/dev/null 2>&1
    rm -rf /home/watashi-panel
    for unit in wg-quick@watashiwg awg-quick@watashi-awg; do
        timeout 20 systemctl stop "$unit" >/dev/null 2>&1 || true
        systemctl disable "$unit" >/dev/null 2>&1 || true
    done
    ip link del watashiwg >/dev/null 2>&1 || true
    ip link del watashi-awg >/dev/null 2>&1 || true
    rm -f /etc/wireguard/watashiwg.conf /etc/amnezia/amneziawg/watashi-awg.conf /etc/sysctl.d/watashi-awg.conf
    rm -f /var/lib/systemd/timers/stamp-watashi-*
    # the ssh warning common/run.sh.j2 puts in /etc/motd
    [ -f /etc/motd ] && sed -i '/Your server is vulnerable/d' /etc/motd
    systemctl daemon-reload >/dev/null 2>&1 || true

    log "Removing the python package..."
    timeout 60 pip3 uninstall -y watashipanel >/dev/null 2>&1 || true

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
        /etc/systemd/system/watashi-panel.service
        /etc/systemd/system/watashi-mita.service
        /etc/systemd/system/telemt.service
        /etc/cron.d/watashi_auto_backup
        /etc/sudoers.d/watashi
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
    if [[ "$PURGE_MODE" == "true" ]] && timeout 5 mysql --connect-timeout=3 -u root -e "USE $DB_NAME;" >/dev/null 2>&1; then
        log "  still here: the $DB_NAME database"
        found=1
    fi
    if grep -qs 'acme\.sh\.env' ~/.bashrc ~/.profile ~/.bash_profile; then
        log "  still here: the acme.sh line in your login shell"
        found=1
    fi
    if timeout 5 systemctl list-units --all --no-legend 'watashi-*' 'telemt*' 2>/dev/null | grep -q .; then
        log "  systemd still lists panel units, a reboot clears the last of them"
    fi
    [[ "$found" == "0" ]] && log "  nothing left behind."
    return 0
}

main 2>&1 | tee "$LOG_FILE"

echo ""
echo "The log of this run is at: $LOG_FILE"
