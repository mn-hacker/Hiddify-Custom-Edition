source /opt/hiddify-manager/common/utils.sh
activate_python_venv

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

chown -R hiddify-panel:hiddify-panel . >/dev/null 2>&1
chmod 600 app.cfg


# set mysql password to flask app config
sed -i '/^SQLALCHEMY_DATABASE_URI/d' app.cfg
if [ -z "${SQLALCHEMY_DATABASE_URI}" ]; then
    if [ -z "${MYSQL_PASS}" ];then
        if [ -f "../other/mysql/mysql_pass" ]; then
            MYSQL_PASS=$(cat ../other/mysql/mysql_pass)
            echo "run.sh: MySQL password loaded (length: ${#MYSQL_PASS})"
        else
            echo "run.sh: ERROR - mysql_pass file not found!"
        fi
    fi
    SQLALCHEMY_DATABASE_URI="mysql+mysqldb://hiddifypanel:$MYSQL_PASS@localhost/hiddifypanel?charset=utf8mb4"
fi
echo "SQLALCHEMY_DATABASE_URI ='$SQLALCHEMY_DATABASE_URI'" >>app.cfg

sed -i '/^REDIS_URI/d' app.cfg
if [ -z "${REDIS_URI_MAIN}" ]; then
    if [ -z "${REDIS_PASS}" ];then
        REDIS_PASS=$(grep '^requirepass' "../other/redis/redis.conf" 2>/dev/null | awk '{print $2}')
    fi
    REDIS_URI_MAIN="redis://:${REDIS_PASS}@127.0.0.1:6379/0"
    REDIS_URI_SSH="redis://:${REDIS_PASS}@127.0.0.1:6379/1"
fi

echo "REDIS_URI_MAIN = '$REDIS_URI_MAIN'">>app.cfg
echo "REDIS_URI_SSH = '$REDIS_URI_SSH'">>app.cfg



if [ -f "../config.env" ]; then
    # systemctl restart --now mariadb
    # sleep 4
    
    hiddify-panel-cli import-config -c $(pwd)/../config.env
    
    # doesn't load virtual env
    #su hiddify-panel -c "hiddifypanel import-config -c $(pwd)/../config.env"
    
    if [ "$?" == 0 ]; then
        mv ../config.env ../config.env.old
        # echo "temporary disable removing config.env"
    fi
fi
hiddify-panel-cli init-db

systemctl start hiddify-panel.service
systemctl restart hiddify-panel-background-tasks.service

