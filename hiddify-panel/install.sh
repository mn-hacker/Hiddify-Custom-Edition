source /opt/hiddify-manager/common/utils.sh
activate_python_venv
install_package wireguard libev-dev libevdev2 default-libmysqlclient-dev build-essential pkg-config ssh

useradd -m hiddify-panel -s /bin/bash >/dev/null 2>&1
usermod -aG hiddify-common hiddify-panel

# watashi v12.2.123: the panel writes panel.log through loguru with rotation and gz
# compression, so the service user must be able to create and rename files inside
# log/system, not only append to panel.log. common/utils.sh log_dir() only does a
# mkdir -p as root, which left the directory root:root and the rotation failed with
# PermissionError. Same pattern as singbox/run.sh:5-8 for the files themselves.
mkdir -p ../log/system
chgrp hiddify-common ../log/system 2>/dev/null || true
chmod 2775 ../log/system 2>/dev/null || true
for ws_log in panel.log hiddify_panel.out.log hiddify_panel.err.log hiddify_panel_background_tasks.out.log hiddify_panel_background_tasks.err.log; do
    touch ../log/system/$ws_log 2>/dev/null || true
    chmod 644 ../log/system/$ws_log 2>/dev/null || true
    chown hiddify-panel:root ../log/system/$ws_log 2>/dev/null || true
done

# watashi v12.2.124: the pictures of the account page live here, outside the installed
# package, so an upgrade of the panel never takes them away.
mkdir -p uploads/avatars
chown -R hiddify-panel:hiddify-panel uploads 2>/dev/null || true
chmod 755 uploads uploads/avatars 2>/dev/null || true
chsh hiddify-panel -s /bin/bash

chown -R hiddify-panel:hiddify-panel /home/hiddify-panel/ >/dev/null 2>&1
localectl set-locale LANG=C.UTF-8 >/dev/null 2>&1
su hiddify-panel -c update-locale LANG=C.UTF-8 >/dev/null 2>&1
chown -R hiddify-panel:hiddify-panel . >/dev/null 2>&1
# activate venv for hiddify-panel user
if ! grep -Fxq "source /opt/hiddify-manager/.venv313/bin/activate" "/home/hiddify-panel/.bashrc" && ! grep -Fxq "export PATH=/opt/hiddify-manager/.venv313/bin:\$PATH" "/home/hiddify-panel/.bashrc"; then
    echo "source /opt/hiddify-manager/.venv313/bin/activate" >> "/home/hiddify-panel/.bashrc"
    echo "export PATH=/opt/hiddify-manager/.venv313/bin:\$PATH" >> "/home/hiddify-panel/.bashrc"
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
    echo "SQLALCHEMY_DATABASE_URI ='mysql+mysqldb://hiddifypanel:$MYSQL_PASS@localhost/hiddifypanel?charset=utf8mb4'" >> app.cfg
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

ln -sf $(pwd)/hiddify-panel.service /etc/systemd/system/hiddify-panel.service
systemctl enable hiddify-panel.service

ln -sf $(pwd)/hiddify-panel-background-tasks.service /etc/systemd/system/hiddify-panel-background-tasks.service
systemctl enable hiddify-panel-background-tasks.service

if [ -n "$HIDDIFY_PANLE_SOURCE_DIR" ]; then
    echo "NOTICE: building hiddifypanel package from source dir..."
    echo "NOTICE: the source dir $HIDDIFY_PANLE_SOURCE_DIR"
    uv pip install -e "$HIDDIFY_PANLE_SOURCE_DIR"
elif [ -d "src" ] && [ -f "src/pyproject.toml" ]; then
    echo "NOTICE: installing hiddifypanel from bundled src/..."
    uv pip install ./src/
else
    echo "NOTICE: installing hiddifypanel from PyPI..."
    uv pip install hiddifypanel
fi

rm -rf /etc/cron.d/{hiddify_usage_update,hiddify_auto_backup}
# echo "*/1 * * * * root $(pwd)/update_usage.sh" >/etc/cron.d/hiddify_usage_update
# echo "0 */6 * * * hiddify-panel $(pwd)/backup.sh" >/etc/cron.d/hiddify_auto_backup
service cron reload >/dev/null 2>&1


##### download videos

if [[ ! -e "GeoLite2-ASN.mmdb" || $(find "GeoLite2-ASN.mmdb" -mtime +1) ]]; then
    curl --connect-timeout 10 -sL -o GeoLite2-ASN.mmdb1 https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-ASN.mmdb && mv GeoLite2-ASN.mmdb1 GeoLite2-ASN.mmdb
fi
if [[ ! -e "GeoLite2-Country.mmdb" || $(find "GeoLite2-Country.mmdb" -mtime +1) ]]; then
    curl --connect-timeout 10 -sL -o GeoLite2-Country.mmdb1 https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-Country.mmdb && mv GeoLite2-Country.mmdb1 GeoLite2-Country.mmdb
fi

# bash download_yt.sh &
