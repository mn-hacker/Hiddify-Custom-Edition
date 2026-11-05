# watashi v12.3.40dev: the old project name was taken out of this file (names, paths and links only)
source /opt/watashi-manager/common/utils.sh
activate_python_venv
install_package wireguard libev-dev libevdev2 default-libmysqlclient-dev build-essential pkg-config ssh

useradd -m watashi-panel -s /bin/bash >/dev/null 2>&1
# watashi v12.2.130cr: useradd -m creates the home only for a new account. An
# account that already existed without one left /home/watashi-panel missing,
# and the venv lines written into its .bashrc further down failed.
if [ ! -d /home/watashi-panel ]; then
    mkdir -p /home/watashi-panel
    cp -n /etc/skel/. /home/watashi-panel/ -r 2>/dev/null || true
fi
touch /home/watashi-panel/.bashrc
chown -R watashi-panel:watashi-panel /home/watashi-panel 2>/dev/null || true
usermod -aG watashi-common watashi-panel

# watashi v12.2.123: the panel writes panel.log through loguru with rotation and gz
# compression, so the service user must be able to create and rename files inside
# log/system, not only append to panel.log. common/utils.sh log_dir() only does a
# mkdir -p as root, which left the directory root:root and the rotation failed with
# PermissionError. Same pattern as singbox/run.sh:5-8 for the files themselves.
mkdir -p ../log/system
chgrp watashi-common ../log/system 2>/dev/null || true
chmod 2775 ../log/system 2>/dev/null || true
for ws_log in panel.log watashi_panel.out.log watashi_panel.err.log watashi_panel_background_tasks.out.log watashi_panel_background_tasks.err.log; do
    touch ../log/system/$ws_log 2>/dev/null || true
    chmod 644 ../log/system/$ws_log 2>/dev/null || true
    chown watashi-panel:root ../log/system/$ws_log 2>/dev/null || true
done

# watashi v12.2.130n: the panel runs as watashi-panel while /opt/watashi-manager
# belongs to root at 755, so the panel could not create the backup folder and
# the backup taken before every update died with PermissionError. Created here
# as root and handed over, exactly like log/system above.
mkdir -p ../backup
chown watashi-panel:watashi-common ../backup 2>/dev/null || true
chmod 2775 ../backup 2>/dev/null || true

# watashi v12.2.124: the pictures of the account page live here, outside the installed
# package, so an upgrade of the panel never takes them away.
mkdir -p uploads/avatars
chown -R watashi-panel:watashi-panel uploads 2>/dev/null || true
chmod 755 uploads uploads/avatars 2>/dev/null || true
chsh watashi-panel -s /bin/bash

chown -R watashi-panel:watashi-panel /home/watashi-panel/ >/dev/null 2>&1
localectl set-locale LANG=C.UTF-8 >/dev/null 2>&1
su watashi-panel -c update-locale LANG=C.UTF-8 >/dev/null 2>&1
chown -R watashi-panel:watashi-panel . >/dev/null 2>&1
# activate venv for watashi-panel user
if ! grep -Fxq "source /opt/watashi-manager/.venv313/bin/activate" "/home/watashi-panel/.bashrc" && ! grep -Fxq "export PATH=/opt/watashi-manager/.venv313/bin:\$PATH" "/home/watashi-panel/.bashrc"; then
    echo "source /opt/watashi-manager/.venv313/bin/activate" >> "/home/watashi-panel/.bashrc"
    echo "export PATH=/opt/watashi-manager/.venv313/bin:\$PATH" >> "/home/watashi-panel/.bashrc"
fi

# Configure MySQL password in app.cfg BEFORE installing panel
# Wait for mysql_pass file to be created (max 30 seconds)
for i in {1..30}; do
    if [ -f "../other/mysql/mysql_pass" ]; then
        break
    fi
    echo "Waiting for mysql_pass... ($i/30)"
    sleep 1
done

if [ -f "../other/mysql/mysql_pass" ]; then
    MYSQL_PASS=$(cat ../other/mysql/mysql_pass)
    echo "MySQL password loaded (length: ${#MYSQL_PASS})"
    # Update SQLALCHEMY_DATABASE_URI
    sed -i '/^SQLALCHEMY_DATABASE_URI/d' app.cfg
    echo "SQLALCHEMY_DATABASE_URI ='mysql+mysqldb://watashipanel:$MYSQL_PASS@localhost/watashipanel?charset=utf8mb4'" >> app.cfg
    echo "MySQL URI configured in app.cfg"
else
    echo "WARNING: mysql_pass file not found! Panel DB connection will fail."
fi

# Configure Redis password in app.cfg
if [ -f "../other/redis/redis.conf" ]; then
    REDIS_PASS=$(grep '^requirepass' "../other/redis/redis.conf" | awk '{print $2}')
    if [ -n "$REDIS_PASS" ]; then
        sed -i '/^REDIS_URI/d' app.cfg
        echo "REDIS_URI_MAIN = 'redis://:${REDIS_PASS}@127.0.0.1:6379/0'" >> app.cfg
        echo "REDIS_URI_SSH = 'redis://:${REDIS_PASS}@127.0.0.1:6379/1'" >> app.cfg
        echo "Redis URI configured in app.cfg"
    fi
fi

chmod 600 app.cfg

ln -sf $(pwd)/watashi-panel.service /etc/systemd/system/watashi-panel.service
systemctl enable watashi-panel.service

ln -sf $(pwd)/watashi-panel-background-tasks.service /etc/systemd/system/watashi-panel-background-tasks.service
systemctl enable watashi-panel-background-tasks.service

if [ -n "$WATASHI_PANEL_SOURCE_DIR" ]; then
    echo "NOTICE: building watashipanel package from source dir..."
    echo "NOTICE: the source dir $WATASHI_PANEL_SOURCE_DIR"
    uv pip install -e "$WATASHI_PANEL_SOURCE_DIR"
elif [ -d "src" ] && [ -f "src/pyproject.toml" ]; then
    echo "NOTICE: installing watashipanel from bundled src/..."
    uv pip install ./src/
else
    # watashi v12.3.40dev: there was a fallback here that installed the panel
    # package from PyPI by name. The package under that name on PyPI is not
    # this project's, so it would have put someone else's code in the panel's
    # place; without the source that comes with the release the install stops.
    echo "ERROR: the panel source (src/pyproject.toml) is missing, the release files are incomplete" >&2
    exit 1
fi

rm -rf /etc/cron.d/{watashi_usage_update,watashi_auto_backup}
# echo "*/1 * * * * root $(pwd)/update_usage.sh" >/etc/cron.d/watashi_usage_update
# watashi v12.2.130d: this line was commented out, which is why no automatic backup
# ever ran on any panel: the only backups that existed were the ones update.sh
# takes before an update. The cron runs every hour and the panel setting
# decides whether it is time yet (backup_interval, 0 switches it off), so the
# owner keeps control without editing cron. Old files are pruned by the same
# task, so the folder cannot grow without end.
cat >/etc/cron.d/watashi_auto_backup <<'WSCRON'
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
# watashi: hourly check, the panel decides if a backup is due
17 * * * * root /opt/watashi-manager/watashi-panel/backup.sh --if-due >/dev/null 2>&1
WSCRON
chmod 644 /etc/cron.d/watashi_auto_backup
systemctl restart cron 2>/dev/null || systemctl restart crond 2>/dev/null || true
service cron reload >/dev/null 2>&1


##### download videos

if [[ ! -e "GeoLite2-ASN.mmdb" || $(find "GeoLite2-ASN.mmdb" -mtime +1) ]]; then
    curl --connect-timeout 10 -sL -o GeoLite2-ASN.mmdb1 https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-ASN.mmdb && mv GeoLite2-ASN.mmdb1 GeoLite2-ASN.mmdb
fi
if [[ ! -e "GeoLite2-Country.mmdb" || $(find "GeoLite2-Country.mmdb" -mtime +1) ]]; then
    curl --connect-timeout 10 -sL -o GeoLite2-Country.mmdb1 https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-Country.mmdb && mv GeoLite2-Country.mmdb1 GeoLite2-Country.mmdb
fi

# bash download_yt.sh &
