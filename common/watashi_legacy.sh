#!/bin/bash
# watashi v12.3.40dev: the one file that still knows the project's old name.
#
# Up to v12.3.39dev this panel was installed under the name of the project it
# was forked from: /opt/hiddify-manager, hiddify-* units, the hiddifypanel
# package and database, the hiddify-panel account. From v12.3.40dev on every
# one of those carries the Watashi name, and this script moves a server from
# the old names to the new ones, in place and without losing anything. Every
# other file of the project only knows the new names; the old ones live here,
# so a server that was never on the old names never runs any of it.
#
#   watashi_legacy.sh migrate [--no-install] [install.sh args]
#        move the server over. Without --no-install it then runs install.sh
#        from the new folder (with the arguments given) and finishes up.
#   watashi_legacy.sh stop-old
#        the proxies of the old install keep serving while the new panel is
#        set up; install.sh calls this right before their successors start.
#   watashi_legacy.sh finish
#        once the new panel is up: drop the old database account and remove
#        the link kept for scripts of the old release that were still running.
#   watashi_legacy.sh drop-link     (started by a timer that finish sets up)
#   watashi_legacy.sh purge [--data]
#        for uninstall.sh: take away whatever the old name left behind; with
#        --data the old database and logs as well.
#   watashi_legacy.sh needed        exit 0 when the old folder is still to be moved
#   watashi_legacy.sh status        print what is left from the old name
#
# Each step looks before it acts, so running it twice is harmless, and a run
# that stopped half way is finished by running it again. What it did is
# written to /var/log/watashi-migrate.log.

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

OLD=/opt/hiddify-manager
NEW=/opt/watashi-manager
OLD_DB=hiddifypanel
NEW_DB=watashipanel
OLD_DB_USER=hiddifypanel
NEW_DB_USER=watashipanel
OLD_USER=hiddify-panel
NEW_USER=watashi-panel
OLD_COMMON=hiddify-common
NEW_COMMON=watashi-common
OLD_CLI_USER=hiddify-cli
OLD_WG=hiddifywg
OLD_CHAIN=HIDDIFY_CONNLIMIT
OLD_PKG=hiddifypanel
LOG=/var/log/watashi-migrate.log
LOCK=/run/watashi-migrate.lock
STATE=/var/lib/watashi-legacy
SYSTEMD=/etc/systemd/system
# the units that carry traffic. They keep running through the move and are
# stopped by stop-old, right before the new ones take their ports.
DEFER_UNITS="hiddify-haproxy hiddify-nginx hiddify-xray hiddify-singbox hiddify-ssh-liberty-bridge hiddify-ss-faketls hiddify-warp"

# old path -> new path inside the folder, in this order: a folder first, then
# what lies in it, already under the folder's new name.
RENAMES="
hiddify-panel watashi-panel
watashi-panel/hiddify-panel.service watashi-panel/watashi-panel.service
watashi-panel/hiddify-panel-background-tasks.service watashi-panel/watashi-panel-background-tasks.service
watashi-panel/src/hiddifypanel watashi-panel/src/watashipanel
watashi-panel/src/watashipanel/panel/hiddify.py watashi-panel/src/watashipanel/panel/watashi.py
watashi-panel/src/watashipanel/templates/hiddify-flask-admin watashi-panel/src/watashipanel/templates/watashi-flask-admin
common/hiddify_installer.sh common/watashi_installer.sh
haproxy/hiddify-haproxy.service haproxy/watashi-haproxy.service
nginx/hiddify-nginx.service nginx/watashi-nginx.service
nginx/parts/hiddify.conf.j2 nginx/parts/watashi.conf.j2
operations/lxd/utils/hiddify_ports_to_csv.sh operations/lxd/utils/watashi_ports_to_csv.sh
other/redis/hiddify-redis.service other/redis/watashi-redis.service
other/ssfaketls/hiddify-ss-faketls.service.j2 other/ssfaketls/watashi-ss-faketls.service.j2
other/ssh/hiddify-ssh-liberty-bridge.service other/ssh/watashi-ssh-liberty-bridge.service
other/warp/singbox/hiddify-warp.service other/warp/singbox/watashi-warp.service
other/warp/warpplus/hiddify-warp.service other/warp/warpplus/watashi-warp.service
singbox/hiddify-singbox.service singbox/watashi-singbox.service
xray/hiddify-xray.service xray/watashi-xray.service
"

# files the old release generated or shipped and the new one does not; under
# the new folder names, since they are removed after the renames.
JUNK="
hiddify-cli
lib/hiddify-core.so
common/add_remote_assistant.sh
common/downgrade.sh
docs/HiddifyPanel.webp
docs/Turorials_en.webp
docs/Tutorials_cn.webp
docs/Tutorials_fa.webp
nginx/parts/hiddify.conf
other/ssfaketls/hiddify-ss-faketls.service
other/hiddify-cli
other/telegram/erlang
other/telegram/python
other/telegram/orig
other/telegram/disable.sh.b53
other/telegram/install.sh.j2.b53
other/telegram/run.sh.j2.b53
other/telegram/tgo/install.sh.b53
watashi-panel/src/build
watashi-panel/src/hiddifypanel.egg-info
watashi-panel/src/1pyproject.toml
watashi-panel/src/pyproject.toml.b54
watashi-panel/src/watashipanel/static/new
watashi-panel/src/watashipanel/static/images/splash
watashi-panel/src/watashipanel/static/images/WhiteLogo.png
watashi-panel/src/watashipanel/static/images/hiddify-dark.png
watashi-panel/src/watashipanel/static/images/hiddify-old.png
watashi-panel/src/watashipanel/static/images/hiddify.png
watashi-panel/src/watashipanel/static/images/hiddify2.png
watashi-panel/src/watashipanel/static/images/no_back_hiddify.png
watashi-panel/src/watashipanel/static/images/pwa-icon.png
watashi-panel/src/watashipanel/panel/user/templates/all_configs copy.txt
watashi-panel/src/watashipanel/drivers/ssh_liberty_bridge_api.py.b56
watashi-panel/src/watashipanel/drivers/user_driver.py.b56
watashi-panel/src/watashipanel/drivers/xray_api.py.b55
watashi-panel/src/watashipanel/hutils/proxy/shared.py.b52
watashi-panel/src/watashipanel/models/user.py.b55
watashi-panel/src/watashipanel/panel/admin/SettingAdmin.py.b53
watashi-panel/src/watashipanel/panel/admin/__init__.py.b51
watashi-panel/src/watashipanel/panel/cli.py.b52
watashi-panel/src/watashipanel/panel/common_bp/login.py.b52
watashi-panel/src/watashipanel/panel/common_bp/templates/login.html.b52
watashi-panel/src/watashipanel/panel/init_db.py.b46
watashi-panel/src/watashipanel/panel/init_db.py.b53
watashi-panel/src/watashipanel/panel/run_commander.py.b51
watashi-panel/src/watashipanel/panel/usage.py.b55
"

# ---------------------------------------------------------------- helpers

say() {
    local line="[$(date '+%F %T')] $*"
    echo "watashi-legacy: $*"
    echo "$line" >>"$LOG" 2>/dev/null
}

# runs a command, its output goes to the log only
quiet() {
    "$@" >>"$LOG" 2>&1
}

fail() {
    say "ERROR: $*"
    exit 1
}

take_lock() {
    mkdir -p "$(dirname "$LOCK")" 2>/dev/null
    exec 9>"$LOCK"
    if ! flock -w "${1:-900}" 9; then
        echo "watashi-legacy: another run is still busy ($LOCK), try again later" >&2
        exit 3
    fi
}

drop_lock() {
    flock -u 9 2>/dev/null
    exec 9>&- 2>/dev/null
}

is_real_dir() {
    [ -d "$1" ] && [ ! -L "$1" ]
}

# old path inside the folder -> its name after the move
map_rel() {
    local p=$1 o n
    while read -r o n; do
        [ -n "$o" ] || continue
        if [ "$p" = "$o" ]; then
            p=$n
        elif [ "${p#"$o"/}" != "$p" ]; then
            p="$n/${p#"$o"/}"
        fi
    done <<<"$RENAMES"
    echo "$p"
}

# an absolute path of the old folder -> the same thing in the new one
map_abs() {
    local p=$1
    case "$p" in
    "$OLD") echo "$NEW" ;;
    "$OLD"/*) echo "$NEW/$(map_rel "${p#"$OLD"/}")" ;;
    *) echo "$p" ;;
    esac
}

# the names our own files used: paths, units, the package, the account
sed_names() {
    sed -i -e "s#$OLD#$NEW#g" \
        -e 's#hiddify-panel#watashi-panel#g' \
        -e 's#hiddifypanel#watashipanel#g' \
        -e 's#hiddify-#watashi-#g' \
        -e 's#hiddify_#watashi_#g' "$@"
}

sed_paths() {
    sed -i -e "s#$OLD#$NEW#g" "$@"
}

# a file or folder is moved to its new name; when the new name is already
# there (a newer copy came with the update) the new one wins and the old one
# is dropped. Folders are merged file by file the same way.
merge_move() {
    local s="$NEW/$1" d="$NEW/$2" f rel
    [ -e "$s" ] || [ -L "$s" ] || return 0
    if [ -d "$s" ] && [ ! -L "$s" ]; then
        if [ ! -e "$d" ]; then
            mkdir -p "$(dirname "$d")" && mv "$s" "$d"
            return $?
        fi
        while IFS= read -r -d '' f; do
            rel=${f#"$s"/}
            if [ -e "$d/$rel" ] || [ -L "$d/$rel" ]; then
                rm -f "$f"
            else
                mkdir -p "$(dirname "$d/$rel")" && mv "$f" "$d/$rel"
            fi
        done < <(find "$s" \( -type f -o -type l \) -print0)
        rm -rf "$s"
        return 0
    fi
    if [ -e "$d" ] || [ -L "$d" ]; then
        rm -f "$s"
    else
        mkdir -p "$(dirname "$d")" && mv "$s" "$d"
    fi
}

sql() {
    timeout 300 mysql --connect-timeout=10 -u root -N -B -e "$1"
}

db_exists() {
    [ "$(sql "SELECT COUNT(*) FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='$1'" 2>/dev/null)" = "1" ]
}

db_tables() {
    sql "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='$1'" 2>/dev/null
}

db_user_exists() {
    [ "$(sql "SELECT COUNT(*) FROM mysql.user WHERE User='$1' AND Host='localhost'" 2>/dev/null)" = "1" ]
}

mysql_up() {
    command -v mysql >/dev/null 2>&1 || return 1
    timeout 20 mysql --connect-timeout=5 -u root -e "SELECT 1" >/dev/null 2>&1 && return 0
    systemctl start mariadb >/dev/null 2>&1 || systemctl start mysql >/dev/null 2>&1
    sleep 3
    timeout 20 mysql --connect-timeout=5 -u root -e "SELECT 1" >/dev/null 2>&1
}

# every unit of the old name systemd knows about, loaded or only on disk
old_units() {
    {
        systemctl list-units --all --plain --no-legend 'hiddify-*' 2>/dev/null | awk '{print $1}'
        systemctl list-unit-files --no-legend 'hiddify-*' 2>/dev/null | awk '{print $1}'
        ls -1 "$SYSTEMD" /lib/systemd/system /usr/lib/systemd/system 2>/dev/null | grep -E '^hiddify-.*\.(service|timer|socket)$'
    } | grep -E '^hiddify-' | sort -u
}

is_deferred() {
    local u=${1%.service} d
    for d in $DEFER_UNITS; do
        [ "$u" = "$d" ] && return 0
    done
    return 1
}

stop_unit() {
    timeout 30 systemctl stop "$1" >/dev/null 2>&1 || systemctl kill -s KILL "$1" >/dev/null 2>&1
    timeout 15 systemctl disable "$1" >/dev/null 2>&1
    systemctl reset-failed "$1" >/dev/null 2>&1
}

remove_unit_files() {
    local u=$1 dir
    for dir in "$SYSTEMD" /lib/systemd/system /usr/lib/systemd/system; do
        rm -f "$dir/$u"
        rm -rf "$dir/$u.d"
        rm -f "$dir"/*.wants/"$u" "$dir"/*.requires/"$u" 2>/dev/null
    done
}

wg_old_present() {
    [ -e "/etc/wireguard/$OLD_WG.conf" ] || ip link show "$OLD_WG" >/dev/null 2>&1 ||
        [ -e "$SYSTEMD/multi-user.target.wants/wg-quick@$OLD_WG.service" ]
}

chain_old_present() {
    local b
    for b in iptables ip6tables; do
        command -v "$b" >/dev/null 2>&1 || continue
        "$b" -n -L "$OLD_CHAIN" >/dev/null 2>&1 && return 0
    done
    grep -qs "$OLD_CHAIN" /etc/iptables/rules.v4 /etc/iptables/rules.v6
}

find_uv() {
    local c
    for c in "$(command -v uv 2>/dev/null)" /usr/local/bin/uv /root/.local/bin/uv /root/.cargo/bin/uv; do
        [ -n "$c" ] && [ -x "$c" ] && echo "$c" && return 0
    done
    return 1
}

# ---------------------------------------------------------------- steps

# A dump of the old database and a copy of every system file of the old name,
# into the backup folder the panel already keeps, before anything changes.
step_backup() {
    local dir=$1 stamp dump files
    stamp=$(date +%Y_%m_%d__%H_%M_%S)
    mkdir -p "$dir" || fail "cannot create $dir"
    if mysql_up && db_exists "$OLD_DB"; then
        dump="$dir/pre-watashi-rename-$stamp.sql.gz"
        if ! (set -o pipefail; timeout 1800 mysqldump -u root --single-transaction --routines --triggers --events "$OLD_DB" | gzip -c >"$dump"); then
            rm -f "$dump"
            fail "the database could not be backed up (disk full?), nothing was changed"
        fi
        chmod 600 "$dump"
        say "database backed up to $dump"
    fi
    files=$(ls -d /etc/cron.d/hiddify* /etc/cron.hourly/hiddify* /etc/cron.daily/hiddify* \
        /etc/sysctl.d/hiddify* /etc/sudoers.d/hiddify /etc/logrotate.d/hiddify* \
        /etc/wireguard/$OLD_WG.conf "$SYSTEMD"/hiddify-* "$SYSTEMD"/*.wants/hiddify-* \
        /etc/passwd /etc/group 2>/dev/null)
    if [ -n "$files" ]; then
        # shellcheck disable=SC2086
        tar -czhf "$dir/pre-watashi-rename-$stamp-system.tar.gz" $files >/dev/null 2>&1
        chmod 600 "$dir/pre-watashi-rename-$stamp-system.tar.gz" 2>/dev/null
        say "system files of the old name saved to $dir/pre-watashi-rename-$stamp-system.tar.gz"
    fi
    return 0
}

# The panel side goes down now (it is replaced in this run); the proxies keep
# running on a copy of their unit file, so the move cannot pull it away.
step_stop_panel_side() {
    local u target pid
    mkdir -p "$STATE"
    for u in $(old_units); do
        if is_deferred "$u" && systemctl is-active --quiet "$u" 2>/dev/null; then
            if [ -L "$SYSTEMD/$u" ]; then
                target=$(readlink -f "$SYSTEMD/$u")
                if [ -f "$target" ]; then
                    cp --remove-destination "$target" "$SYSTEMD/$u"
                fi
            fi
            local w
            for w in "$SYSTEMD"/*.wants/"$u"; do
                [ -L "$w" ] && ln -sfn "$SYSTEMD/$u" "$w"
            done
            grep -qx "$u" "$STATE/deferred" 2>/dev/null || echo "$u" >>"$STATE/deferred"
            say "$u keeps serving until the new one starts"
            continue
        fi
        stop_unit "$u"
        remove_unit_files "$u"
        say "stopped and removed $u"
    done
    systemctl daemon-reload >/dev/null 2>&1
    # workers that outlived their unit still hold the database and the account
    if id "$OLD_USER" >/dev/null 2>&1; then
        pkill -u "$OLD_USER" >/dev/null 2>&1
        sleep 2
        pkill -KILL -u "$OLD_USER" >/dev/null 2>&1
    fi
    for pid in $(pgrep -f "$OLD_PKG" 2>/dev/null); do
        [ "$pid" != "$$" ] && kill "$pid" >/dev/null 2>&1
    done
    return 0
}

step_move_folder() {
    if is_real_dir "$OLD"; then
        if [ -e "$NEW" ] && ! is_real_dir "$NEW"; then
            fail "$NEW exists and is not a folder, nothing was moved"
        fi
        if is_real_dir "$NEW"; then
            if [ -e "$NEW/install.sh" ]; then
                fail "both $OLD and $NEW hold an install; move one of them away by hand and run this again"
            fi
            # only what our own scripts made early in this run (log folders)
            cp -an "$NEW"/. "$OLD"/ 2>/dev/null
            rm -rf "$NEW"
        fi
        mv "$OLD" "$NEW" || fail "could not move $OLD to $NEW"
        ln -sfn "$NEW" "$OLD"
        say "moved $OLD to $NEW (the old path is a link for now)"
    fi
    local link
    for link in /opt/hiddify-config /opt/hiddify-server; do
        [ -L "$link" ] && rm -f "$link" && say "removed the link $link"
    done
    return 0
}

step_rename_inside() {
    local o n f base
    while read -r o n; do
        [ -n "$o" ] || continue
        if [ -e "$NEW/$o" ] || [ -L "$NEW/$o" ]; then
            merge_move "$o" "$n" && say "renamed $o -> $n"
        fi
    done <<<"$RENAMES"
    if [ ! -f "$NEW/log/system/.watashi-legacy-junk" ]; then
        while IFS= read -r f; do
            [ -n "$f" ] || continue
            if [ -e "$NEW/$f" ] || [ -L "$NEW/$f" ]; then
                rm -rf "${NEW:?}/$f"
            fi
        done <<<"$JUNK"
        if [ -d "$NEW/other/deprecated" ]; then
            find "$NEW/other/deprecated" -mindepth 1 -maxdepth 1 ! -name remove_deprecated.sh -exec rm -rf {} + 2>/dev/null
        fi
        rmdir "$NEW/lib" 2>/dev/null
        mkdir -p "$NEW/log/system" && date -u +%FT%TZ >"$NEW/log/system/.watashi-legacy-junk"
        say "files the new release no longer has were removed"
    fi
    # the logs keep their history under the new names
    for f in $(find "$NEW/log" -maxdepth 2 -name '*hiddify*' 2>/dev/null); do
        base=$(basename "$f")
        n="$(dirname "$f")/${base//hiddify/watashi}"
        if [ -e "$n" ]; then
            mv "$f" "$n.before-rename" 2>/dev/null
        else
            mv "$f" "$n" 2>/dev/null
        fi
    done
    return 0
}

step_accounts() {
    local m members
    if getent group "$OLD_COMMON" >/dev/null 2>&1; then
        if getent group "$NEW_COMMON" >/dev/null 2>&1; then
            members=$(getent group "$OLD_COMMON" | cut -d: -f4 | tr ',' ' ')
            for m in $members; do
                [ "$m" = "$OLD_USER" ] && m=$NEW_USER
                id "$m" >/dev/null 2>&1 && usermod -aG "$NEW_COMMON" "$m" >/dev/null 2>&1
            done
            groupdel "$OLD_COMMON" >/dev/null 2>&1
        else
            groupmod -n "$NEW_COMMON" "$OLD_COMMON" || fail "could not rename the group $OLD_COMMON"
        fi
        say "group $OLD_COMMON is $NEW_COMMON now"
    fi
    if id "$OLD_USER" >/dev/null 2>&1; then
        if id "$NEW_USER" >/dev/null 2>&1; then
            pkill -KILL -u "$OLD_USER" >/dev/null 2>&1
            userdel "$OLD_USER" >/dev/null 2>&1
            say "removed the account $OLD_USER, $NEW_USER already exists"
        else
            local i
            for i in 1 2 3 4 5; do
                pkill -KILL -u "$OLD_USER" >/dev/null 2>&1
                if [ -d "/home/$OLD_USER" ] && [ ! -e "/home/$NEW_USER" ]; then
                    usermod -l "$NEW_USER" -d "/home/$NEW_USER" -m "$OLD_USER" >>"$LOG" 2>&1 && break
                else
                    usermod -l "$NEW_USER" -d "/home/$NEW_USER" "$OLD_USER" >>"$LOG" 2>&1 && break
                fi
                sleep 2
            done
            id "$NEW_USER" >/dev/null 2>&1 || fail "could not rename the account $OLD_USER (still in use?)"
            say "account $OLD_USER is $NEW_USER now"
        fi
    fi
    if getent group "$OLD_USER" >/dev/null 2>&1; then
        if getent group "$NEW_USER" >/dev/null 2>&1; then
            groupdel "$OLD_USER" >/dev/null 2>&1
        else
            groupmod -n "$NEW_USER" "$OLD_USER" >/dev/null 2>&1
        fi
    fi
    if id "$NEW_USER" >/dev/null 2>&1; then
        mkdir -p "/home/$NEW_USER"
        [ -f "/home/$NEW_USER/.bashrc" ] && sed_paths "/home/$NEW_USER/.bashrc"
        chown "$NEW_USER:" "/home/$NEW_USER" 2>/dev/null
    fi
    for f in /etc/subuid /etc/subgid; do
        if grep -q "^$OLD_USER:" "$f" 2>/dev/null; then
            if grep -q "^$NEW_USER:" "$f"; then
                sed -i "/^$OLD_USER:/d" "$f"
            else
                sed -i "s/^$OLD_USER:/$NEW_USER:/" "$f"
            fi
        fi
    done
    if id "$OLD_CLI_USER" >/dev/null 2>&1; then
        pkill -KILL -u "$OLD_CLI_USER" >/dev/null 2>&1
        userdel "$OLD_CLI_USER" >/dev/null 2>&1 && say "removed the retired account $OLD_CLI_USER"
    fi
    getent group "$OLD_CLI_USER" >/dev/null 2>&1 && groupdel "$OLD_CLI_USER" >/dev/null 2>&1
    return 0
}

step_sudoers() {
    [ -e /etc/sudoers.d/hiddify ] || return 0
    local tmp=/etc/sudoers.d/.watashi.tmp
    echo "$NEW_USER ALL=(root) NOPASSWD: $NEW/common/commander.py" >"$tmp"
    chmod 440 "$tmp"
    if visudo -cf "$tmp" >/dev/null 2>&1; then
        mv -f "$tmp" /etc/sudoers.d/watashi
        rm -f /etc/sudoers.d/hiddify
        say "sudo rule moved to /etc/sudoers.d/watashi"
    else
        rm -f "$tmp"
        fail "the new sudo rule did not pass visudo"
    fi
}

step_database() {
    if ! mysql_up; then
        if [ -d /var/lib/mysql/"$OLD_DB" ]; then
            fail "MariaDB does not answer, the database could not be moved"
        fi
        return 0
    fi
    local pass="" cs co n_old n_new other stmt
    [ -f "$NEW/other/mysql/mysql_pass" ] && pass=$(tr -d '\r\n' <"$NEW/other/mysql/mysql_pass")
    if db_exists "$OLD_DB"; then
        n_old=$(db_tables "$OLD_DB")
        if db_exists "$NEW_DB"; then
            n_new=$(db_tables "$NEW_DB")
            if [ "${n_new:-0}" != "0" ] && [ "${n_old:-0}" != "0" ]; then
                fail "both $OLD_DB and $NEW_DB hold tables; nothing was moved"
            fi
        fi
        if [ "${n_old:-0}" != "0" ]; then
            cs=$(sql "SELECT DEFAULT_CHARACTER_SET_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='$OLD_DB'")
            co=$(sql "SELECT DEFAULT_COLLATION_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='$OLD_DB'")
            sql "CREATE DATABASE IF NOT EXISTS \`$NEW_DB\` CHARACTER SET ${cs:-utf8mb4} COLLATE ${co:-utf8mb4_unicode_ci}" ||
                fail "could not create the database $NEW_DB"
            other=$(sql "SELECT (SELECT COUNT(*) FROM information_schema.TRIGGERS WHERE TRIGGER_SCHEMA='$OLD_DB') + (SELECT COUNT(*) FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA='$OLD_DB') + (SELECT COUNT(*) FROM information_schema.EVENTS WHERE EVENT_SCHEMA='$OLD_DB') + (SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='$OLD_DB' AND TABLE_TYPE<>'BASE TABLE')")
            if [ "${other:-1}" = "0" ]; then
                # one statement, so either every table moves or none does
                stmt=$(sql "SET SESSION group_concat_max_len=1048576; SELECT CONCAT('RENAME TABLE ', GROUP_CONCAT(CONCAT('\`$OLD_DB\`.\`', TABLE_NAME, '\` TO \`$NEW_DB\`.\`', TABLE_NAME, '\`') SEPARATOR ', ')) FROM information_schema.TABLES WHERE TABLE_SCHEMA='$OLD_DB'")
                sql "$stmt" >>"$LOG" 2>&1 || fail "the tables could not be moved to $NEW_DB (nothing was moved)"
            else
                # triggers, views or routines cannot be renamed across
                # databases, so the whole thing goes through a dump
                if ! (set -o pipefail; timeout 1800 mysqldump -u root --single-transaction --routines --triggers --events "$OLD_DB" |
                    sed -E 's/DEFINER=`[^`]+`@`[^`]+`//g' | timeout 1800 mysql -u root "$NEW_DB"); then
                    fail "copying $OLD_DB into $NEW_DB failed; $OLD_DB is untouched"
                fi
            fi
            n_new=$(db_tables "$NEW_DB")
            if [ "${n_new:-0}" -lt "${n_old:-0}" ]; then
                fail "$NEW_DB has $n_new tables, $OLD_DB had $n_old; $OLD_DB was kept"
            fi
            if [ "$(db_tables "$OLD_DB")" != "0" ]; then
                sql "DROP DATABASE \`$OLD_DB\`" >>"$LOG" 2>&1 && say "the copied database $OLD_DB was dropped"
            fi
            say "database $OLD_DB is $NEW_DB now ($n_new tables)"
        fi
        if [ "$(db_tables "$OLD_DB")" = "0" ]; then
            sql "DROP DATABASE IF EXISTS \`$OLD_DB\`" >>"$LOG" 2>&1
        fi
    fi
    if db_exists "$NEW_DB" && [ -n "$pass" ]; then
        local p=${pass//\'/\'\'}
        sql "CREATE USER IF NOT EXISTS '$NEW_DB_USER'@'localhost' IDENTIFIED BY '$p'; ALTER USER '$NEW_DB_USER'@'localhost' IDENTIFIED BY '$p'; GRANT ALL PRIVILEGES ON \`$NEW_DB\`.* TO '$NEW_DB_USER'@'localhost'; GRANT ALL PRIVILEGES ON *.* TO '$NEW_DB_USER'@'localhost' WITH GRANT OPTION; FLUSH PRIVILEGES;" >>"$LOG" 2>&1 ||
            fail "could not set up the database account $NEW_DB_USER"
        if ! MYSQL_PWD="$pass" timeout 20 mysql -u "$NEW_DB_USER" -h localhost "$NEW_DB" -e "SELECT 1" >/dev/null 2>&1; then
            fail "the database account $NEW_DB_USER cannot log in"
        fi
        # the public halves of the ssh host keys carry the account name as
        # their comment; the key itself does not change
        sql "UPDATE \`$NEW_DB\`.str_config SET value=REPLACE(value, ' $OLD_USER@', ' $NEW_USER@') WHERE value LIKE '% $OLD_USER@%' AND \`key\` LIKE 'ssh_host_%_pub'" >>"$LOG" 2>&1
    fi
    return 0
}

step_app_cfg() {
    local f="$NEW/watashi-panel/app.cfg"
    [ -f "$f" ] || return 0
    grep -q "hiddify" "$f" || return 0
    sed -i -e "s#$OLD#$NEW#g" -e 's#^HIDDIFY_#WATASHI_#' \
        -e "s#mysql+mysqldb://$OLD_DB_USER:#mysql+mysqldb://$NEW_DB_USER:#" \
        -e "s#@localhost/$OLD_DB?#@localhost/$NEW_DB?#" "$f"
    say "app.cfg points at the new folder and database"
}

step_systemd() {
    local link target newt f
    # links of units that kept their name but pointed into the old folder
    while IFS= read -r -d '' link; do
        case "$(basename "$link")" in hiddify-*) continue ;; esac
        target=$(readlink "$link")
        newt=$(map_abs "$target")
        [ "$newt" != "$target" ] && ln -sfn "$newt" "$link" && say "link $link now points at $newt"
    done < <(find "$SYSTEMD" /lib/systemd/system -maxdepth 2 -type l -lname "$OLD*" -print0 2>/dev/null)
    # unit files of ours that still name the old folder or units
    while IFS= read -r -d '' f; do
        case "$(basename "$f")" in hiddify-*) continue ;; esac
        if grep -q "hiddify" "$f"; then
            sed_names "$f" && say "updated $f"
        fi
    done < <(find "$SYSTEMD" -maxdepth 1 -type f \( -name '*.service' -o -name '*.timer' \) -print0 2>/dev/null)
    systemctl daemon-reload >/dev/null 2>&1
    return 0
}

step_system_files() {
    local f n link target newt
    for f in /etc/cron.d/hiddify* /etc/cron.hourly/hiddify* /etc/cron.daily/hiddify*; do
        [ -e "$f" ] || continue
        n="$(dirname "$f")/$(basename "$f" | sed 's/hiddify/watashi/g')"
        if [ -e "$n" ]; then
            rm -f "$f"
        else
            sed_names "$f" && mv "$f" "$n"
        fi
        say "cron $f -> $n"
    done
    for f in /etc/logrotate.d/hiddify*; do
        [ -e "$f" ] || continue
        n="/etc/logrotate.d/$(basename "$f" | sed 's/hiddify/watashi/g')"
        if [ -e "$n" ]; then rm -f "$f"; else sed_names "$f" && mv "$f" "$n"; fi
        say "logrotate $f -> $n"
    done
    for f in /etc/sysctl.d/hiddify*; do
        [ -e "$f" ] || [ -L "$f" ] || continue
        n="/etc/sysctl.d/$(basename "$f" | sed 's/hiddify/watashi/g')"
        if [ -L "$f" ]; then
            target=$(readlink "$f")
            rm -f "$f"
            [ -e "$n" ] || ln -sfn "$(map_abs "$target")" "$n"
        elif [ -e "$n" ]; then
            rm -f "$f"
        else
            mv "$f" "$n"
        fi
        say "sysctl $f -> $n"
    done
    # two files that keep their name but carry a line of the old release: the
    # ssh warning in /etc/motd and the header of the reserved ports list. A
    # link (sysctl.d/watashi.conf points into the folder) is left alone.
    if [ -f /etc/motd ] && grep -q 'Hiddify! Your server is vulnerable' /etc/motd; then
        sed -i 's/Hiddify! Your server is vulnerable/Watashi! Your server is vulnerable/' /etc/motd && say "updated /etc/motd"
    fi
    for f in /etc/sysctl.d/watashi-*.conf; do
        [ -f "$f" ] && [ ! -L "$f" ] || continue
        grep -q 'hiddify-manager' "$f" && sed -i 's#hiddify-manager#watashi-manager#g' "$f" && say "updated $f"
    done
    # the menu shortcut of the old name goes; install.sh makes /usr/bin/watashi
    for f in /usr/bin/hiddify /usr/local/bin/hiddify; do
        if [ -L "$f" ] || [ -f "$f" ]; then
            rm -f "$f" && say "removed the shortcut $f"
        fi
    done
    [ -e /usr/bin/watashi ] || [ ! -f "$NEW/menu.sh" ] || ln -sf "$NEW/menu.sh" /usr/bin/watashi
    # other links into the old folder (xray, sing-box, ...)
    while IFS= read -r -d '' link; do
        target=$(readlink "$link")
        newt=$(map_abs "$target")
        [ "$newt" != "$target" ] && ln -sfn "$newt" "$link" && say "link $link now points at $newt"
    done < <(find /usr/bin /usr/sbin /usr/local/bin /usr/local/sbin /etc -maxdepth 3 -type l -lname "$OLD*" ! -path '/etc/systemd/*' -print0 2>/dev/null)
    # the shell start files of root; the two folder names of the upstream v7 era
    # (hiddify-config, hiddify-server) were rewritten by menu.sh until now.
    for f in /root/.bashrc /root/.profile /root/.bash_profile; do
        [ -f "$f" ] || continue
        grep -q -e "$OLD" -e /opt/hiddify-config -e /opt/hiddify-server "$f" || continue
        sed -i -e "s#$OLD#$NEW#g" -e "s#/opt/hiddify-config/#$NEW/#g" -e "s#/opt/hiddify-server/#$NEW/#g" "$f" && say "updated $f"
    done
    return 0
}

# acme.sh lives inside the folder and wrote its own path into its files,
# some of it base64 encoded (the reload command of an installed certificate).
step_acme() {
    local base="$NEW/acme.sh/lib" f key val dec enc tmp
    [ -d "$base" ] || return 0
    for f in "$base/acme.sh.env" "$base"/data/*.conf "$base"/certs/*/*.conf "$base"/*.conf; do
        [ -f "$f" ] || continue
        if grep -q '__ACME_BASE64__START_' "$f"; then
            tmp=$(mktemp)
            while IFS= read -r line || [ -n "$line" ]; do
                if [[ "$line" =~ ^([A-Za-z0-9_]+)=\'__ACME_BASE64__START_(.*)__ACME_BASE64__END_\'$ ]]; then
                    key=${BASH_REMATCH[1]}
                    val=${BASH_REMATCH[2]}
                    dec=$(printf '%s' "$val" | base64 -d 2>/dev/null)
                    if [[ "$dec" == *hiddify* ]]; then
                        dec=$(printf '%s' "$dec" | sed -e "s#$OLD#$NEW#g" -e 's#hiddify-#watashi-#g')
                        enc=$(printf '%s' "$dec" | base64 -w0)
                        line="$key='__ACME_BASE64__START_${enc}__ACME_BASE64__END_'"
                    fi
                fi
                printf '%s\n' "$line"
            done <"$f" >"$tmp"
            cat "$tmp" >"$f"
            rm -f "$tmp"
        fi
        grep -q "$OLD" "$f" && sed_paths "$f"
    done
    return 0
}

step_venv() {
    local v sp uv
    uv=$(find_uv)
    for v in "$NEW"/.venv*; do
        [ -d "$v" ] || continue
        grep -rlIZ "$OLD" "$v" 2>/dev/null | xargs -0 -r sed -i "s#$OLD#$NEW#g"
        for sp in "$v"/lib/python*/site-packages; do
            [ -d "$sp/$OLD_PKG" ] || ls "$sp"/"$OLD_PKG"-*.dist-info >/dev/null 2>&1 || continue
            if [ -n "$uv" ] && [ -x "$v/bin/python" ]; then
                quiet "$uv" pip uninstall --python "$v/bin/python" "$OLD_PKG"
            fi
            rm -rf "${sp:?}/$OLD_PKG" "$sp"/"$OLD_PKG"-*.dist-info "$sp"/__editable__*"$OLD_PKG"* "$sp"/"$OLD_PKG".egg-link 2>/dev/null
            rm -f "$v/bin/$OLD_PKG"
            say "the old panel package was removed from $v"
        done
    done
    [ -n "$uv" ] && quiet "$uv" cache clean "$OLD_PKG"
    return 0
}

# only when the update came as files unpacked into the old folder: the
# package description of the panel is not part of such an update.
step_pyproject() {
    local src="$NEW/watashi-panel/src"
    if [ -f "$src/pyproject.toml" ] && grep -q '^name = "hiddifypanel"$' "$src/pyproject.toml"; then
        sed -i \
            -e 's|^homepage = "https://hiddify.com"$|homepage = "https://watashi.cyou"|' \
            -e 's|^repository = "https://github.com/hiddify/hiddify-manager/"$|repository = "https://github.com/mn-hacker/Watashi-Manager/"|' \
            -e 's|^documentation = "https://hiddify.com/manager"$|documentation = "https://watashi.cyou"|' \
            -e 's|^name = "hiddifypanel"$|name = "watashipanel"|' \
            -e 's|^description = "hiddifypanel multi proxy panel"$|description = "watashipanel multi proxy panel"|' \
            -e 's|^authors = \[{ name = "hiddify" }\]$|authors = [{ name = "Watashi" }]|' \
            -e 's|^hiddifypanel = "hiddifypanel.__main__:main"$|watashipanel = "watashipanel.__main__:main"|' \
            -e 's|^include = \["hiddifypanel"\]$|include = ["watashipanel"]|' \
            -e 's|^"hiddifypanel" = \[$|"watashipanel" = [|' \
            -e 's|^#"" = \["hiddifypanel/translations|#"" = ["watashipanel/translations|' \
            "$src/pyproject.toml"
        say "pyproject.toml describes the watashipanel package now"
    fi
    if [ -f "$src/uv.lock" ] && grep -q '^name = "hiddifypanel"$' "$src/uv.lock"; then
        sed -i 's|^name = "hiddifypanel"$|name = "watashipanel"|' "$src/uv.lock"
    fi
    return 0
}

# ---------------------------------------------------------------- commands

cmd_needed() {
    is_real_dir "$OLD"
}

cmd_status() {
    local any=0 u
    is_real_dir "$OLD" && echo "folder: $OLD has not been moved yet" && any=1
    [ -L "$OLD" ] && echo "link: $OLD -> $(readlink "$OLD")" && any=1
    for u in $(old_units); do echo "unit: $u"; any=1; done
    wg_old_present && echo "wireguard: $OLD_WG" && any=1
    chain_old_present && echo "firewall: chain $OLD_CHAIN" && any=1
    ls -d /etc/cron.d/hiddify* /etc/cron.hourly/hiddify* /etc/sysctl.d/hiddify* /etc/sudoers.d/hiddify \
        /etc/logrotate.d/hiddify* /usr/bin/hiddify 2>/dev/null | sed 's/^/file: /' | grep . && any=1
    id "$OLD_USER" >/dev/null 2>&1 && echo "account: $OLD_USER" && any=1
    getent group "$OLD_COMMON" >/dev/null 2>&1 && echo "group: $OLD_COMMON" && any=1
    if mysql_up; then
        db_exists "$OLD_DB" && echo "database: $OLD_DB" && any=1
        db_user_exists "$OLD_DB_USER" && echo "database account: $OLD_DB_USER" && any=1
    fi
    [ -s "$STATE/deferred" ] && echo "still serving until install.sh replaces them: $(tr '\n' ' ' <"$STATE/deferred")" && any=1
    [ "$any" = 0 ] && echo "nothing is left from the old name"
    return 0
}

# the old proxies make way for the new ones
cmd_stop_old() {
    local u found=0
    [ -s "$STATE/deferred" ] && found=1
    ls "$SYSTEMD"/hiddify-* >/dev/null 2>&1 && found=1
    wg_old_present && found=1
    chain_old_present && found=1
    [ "$found" = 1 ] || return 0
    take_lock 600
    for u in $(old_units) $(cat "$STATE/deferred" 2>/dev/null); do
        stop_unit "$u"
        remove_unit_files "$u"
        say "stopped and removed $u"
    done
    rm -f "$STATE/deferred"
    if wg_old_present; then
        timeout 30 systemctl stop "wg-quick@$OLD_WG" >/dev/null 2>&1
        systemctl disable "wg-quick@$OLD_WG" >/dev/null 2>&1
        ip link del "$OLD_WG" >/dev/null 2>&1
        rm -f "/etc/wireguard/$OLD_WG.conf"
        say "the wireguard interface $OLD_WG was taken down; the new one is set up by install.sh"
    fi
    if chain_old_present; then
        local b
        for b in iptables ip6tables; do
            command -v "$b" >/dev/null 2>&1 || continue
            while "$b" -D INPUT -j "$OLD_CHAIN" >/dev/null 2>&1; do :; done
            "$b" -F "$OLD_CHAIN" >/dev/null 2>&1
            "$b" -X "$OLD_CHAIN" >/dev/null 2>&1
        done
        if grep -qs "$OLD_CHAIN" /etc/iptables/rules.v4 /etc/iptables/rules.v6; then
            iptables-save >/etc/iptables/rules.v4 2>/dev/null
            ip6tables-save >/etc/iptables/rules.v6 2>/dev/null
        fi
        say "the firewall chain $OLD_CHAIN was removed"
    fi
    systemctl daemon-reload >/dev/null 2>&1
    systemctl reset-failed >/dev/null 2>&1
    drop_lock
    return 0
}

cmd_migrate() {
    local install=1 args=()
    for a in "$@"; do
        case "$a" in
        --no-install) install=0 ;;
        # a move always needs the full install: the light "apply_users" pass
        # and the reboot quick start would leave the new panel uninstalled
        apply_users | --check-only) ;;
        *) args+=("$a") ;;
        esac
    done
    [ "$(id -u)" = "0" ] || { echo "watashi-legacy: run this as root" >&2; exit 1; }
    take_lock 900
    local work=0
    is_real_dir "$OLD" && work=1
    [ -n "$(old_units)" ] && work=1
    ls /etc/cron.d/hiddify* /etc/sysctl.d/hiddify* /etc/sudoers.d/hiddify /usr/bin/hiddify >/dev/null 2>&1 && work=1
    id "$OLD_USER" >/dev/null 2>&1 && work=1
    getent group "$OLD_COMMON" >/dev/null 2>&1 && work=1
    [ -d /var/lib/mysql/"$OLD_DB" ] && work=1
    if [ -f "$NEW/watashi-panel/src/pyproject.toml" ] && grep -q '^name = "hiddifypanel"$' "$NEW/watashi-panel/src/pyproject.toml"; then
        work=1
    fi
    if [ "$work" = 1 ]; then
        say "moving this server from the old name to the new one"
        local home=$NEW
        is_real_dir "$OLD" && home=$OLD
        step_backup "$home/backup"
        step_stop_panel_side
        step_move_folder
        step_rename_inside
        step_accounts
        step_sudoers
        step_database
        step_app_cfg
        step_systemd
        step_system_files
        step_acme
        step_venv
        step_pyproject
        say "the move is done"
    fi
    drop_lock
    if [ "$install" = 1 ]; then
        [ -f "$NEW/install.sh" ] || fail "$NEW/install.sh is missing"
        say "running install.sh from $NEW"
        cd "$NEW" || exit 1
        bash "$NEW/install.sh" "${args[@]}"
        local rc=$?
        [ "$rc" = 0 ] && cmd_finish
        return $rc
    fi
    return 0
}

panel_is_up() {
    [ -x "$NEW/.venv313/bin/python" ] || return 1
    "$NEW/.venv313/bin/python" -c "import watashipanel" >/dev/null 2>&1 || return 1
    mysql_up || return 1
    db_exists "$NEW_DB" || return 1
    [ "$(db_tables "$NEW_DB")" != "0" ] || return 1
    systemctl is-active --quiet watashi-panel 2>/dev/null
}

cmd_finish() {
    take_lock 600
    if ! panel_is_up; then
        say "the new panel is not up yet, the old database account and the folder link stay for now"
        drop_lock
        return 1
    fi
    if db_user_exists "$OLD_DB_USER"; then
        sql "DROP USER IF EXISTS '$OLD_DB_USER'@'localhost'; FLUSH PRIVILEGES;" >>"$LOG" 2>&1 &&
            say "the old database account $OLD_DB_USER was dropped"
    fi
    if [ -L "$OLD" ]; then
        if command -v systemd-run >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
            systemctl stop watashi-legacy-drop-link.timer >/dev/null 2>&1
            systemd-run --quiet --collect --unit=watashi-legacy-drop-link --on-active=20min \
                /bin/bash "$NEW/common/watashi_legacy.sh" drop-link >/dev/null 2>&1 &&
                say "the link $OLD goes in 20 minutes, once nothing of the old release runs any more"
        else
            say "the link $OLD stays; run 'bash $NEW/common/watashi_legacy.sh drop-link' later"
        fi
    fi
    drop_lock
    return 0
}

# A script of the old release that was running when the update started (the
# old update.sh waits for the installer and then carries on) still uses the
# old folder name. The link stays until no such process is left.
cmd_drop_link() {
    [ -L "$OLD" ] || return 0
    local tries=0
    mkdir -p "$STATE"
    tries=$(cat "$STATE/drop-link-tries" 2>/dev/null || echo 0)
    if pgrep -f "$OLD|hiddify|/update\.sh" >/dev/null 2>&1 && [ "$tries" -lt 12 ]; then
        echo $((tries + 1)) >"$STATE/drop-link-tries"
        systemd-run --quiet --collect --unit="watashi-legacy-drop-link-$((tries + 1))" --on-active=20min \
            /bin/bash "$NEW/common/watashi_legacy.sh" drop-link >/dev/null 2>&1
        say "something of the old release still runs, the link $OLD stays a little longer"
        return 0
    fi
    rm -f "$OLD" && say "removed the link $OLD"
    rm -f "$STATE/drop-link-tries"
    rmdir "$STATE" 2>/dev/null
    return 0
}

cmd_purge() {
    local data=0 u f
    [ "${1:-}" = "--data" ] && data=1
    take_lock 300
    for u in $(old_units); do
        stop_unit "$u"
        remove_unit_files "$u"
    done
    # the link goes below, so the timer that was to take it away later has
    # nothing left to do; once the folder is gone it would only fail
    for u in $(systemctl list-units --all --plain --no-legend 'watashi-legacy-drop-link*' 2>/dev/null | awk '{print $1}'); do
        systemctl stop "$u" >/dev/null 2>&1
    done
    rm -rf "$STATE"
    if wg_old_present; then
        timeout 30 systemctl stop "wg-quick@$OLD_WG" >/dev/null 2>&1
        systemctl disable "wg-quick@$OLD_WG" >/dev/null 2>&1
        ip link del "$OLD_WG" >/dev/null 2>&1
        rm -f "/etc/wireguard/$OLD_WG.conf"
    fi
    if chain_old_present; then
        for b in iptables ip6tables; do
            command -v "$b" >/dev/null 2>&1 || continue
            while "$b" -D INPUT -j "$OLD_CHAIN" >/dev/null 2>&1; do :; done
            "$b" -F "$OLD_CHAIN" >/dev/null 2>&1
            "$b" -X "$OLD_CHAIN" >/dev/null 2>&1
        done
    fi
    rm -f /etc/cron.d/hiddify* /etc/cron.hourly/hiddify* /etc/cron.daily/hiddify*
    rm -f /etc/sysctl.d/hiddify* /etc/sudoers.d/hiddify /etc/logrotate.d/hiddify*
    rm -f /usr/bin/hiddify /usr/local/bin/hiddify*
    for f in "$OLD" /opt/hiddify-config /opt/hiddify-server; do
        [ -L "$f" ] && rm -f "$f"
    done
    for f in /root/.bashrc /root/.profile /root/.bash_profile; do
        [ -f "$f" ] && sed -i -e "\#$OLD#d" -e "\#/opt/hiddify-config#d" -e "\#/opt/hiddify-server#d" "$f"
    done
    [ -f /etc/motd ] && sed -i '/Hiddify! Your server is vulnerable/d' /etc/motd
    if id "$OLD_CLI_USER" >/dev/null 2>&1; then userdel "$OLD_CLI_USER" >/dev/null 2>&1; fi
    if [ "$data" = 1 ]; then
        if mysql_up; then
            sql "DROP DATABASE IF EXISTS \`$OLD_DB\`; DROP USER IF EXISTS '$OLD_DB_USER'@'localhost'; FLUSH PRIVILEGES;" >>"$LOG" 2>&1
        fi
        is_real_dir "$OLD" && rm -rf "${OLD:?}"
        rm -rf /var/log/hiddify* /tmp/hiddify*
        if id "$OLD_USER" >/dev/null 2>&1; then
            pkill -KILL -u "$OLD_USER" >/dev/null 2>&1
            userdel -r "$OLD_USER" >/dev/null 2>&1
        fi
        getent group "$OLD_USER" >/dev/null 2>&1 && groupdel "$OLD_USER" >/dev/null 2>&1
        getent group "$OLD_COMMON" >/dev/null 2>&1 && groupdel "$OLD_COMMON" >/dev/null 2>&1
        timeout 60 pip3 uninstall -y "$OLD_PKG" >/dev/null 2>&1
    fi
    systemctl daemon-reload >/dev/null 2>&1
    systemctl reset-failed >/dev/null 2>&1
    drop_lock
    echo "nothing of the old name is left"
    return 0
}

case "${1:-}" in
migrate) shift; cmd_migrate "$@" ;;
stop-old) cmd_stop_old ;;
finish) cmd_finish ;;
drop-link) cmd_drop_link ;;
purge) shift; cmd_purge "$@" ;;
needed) cmd_needed ;;
status) cmd_status ;;
*)
    sed -n '2,29p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
    ;;
esac
