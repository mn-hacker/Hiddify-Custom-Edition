# watashi v12.3.40dev: the old project name was taken out of this file (names, paths and links only)
# mv /usr/local/etc/xray/config.json /usr/local/etc/xray/config.json.old
# ln -sf $(pwd)/xtls-config.json /usr/local/etc/xray/config.json
# ln -sf $(pwd)/xtls-sni-config.json /usr/local/etc/xray/config.json
#sed -i "s/^User=/#User=/g" /etc/systemd/system/xray.service
chmod -R 600 configs
mkdir -p run
ln -sf $(pwd)/watashi-xray.service /etc/systemd/system/watashi-xray.service
systemctl enable watashi-xray.service

source /opt/watashi-manager/common/utils.sh
activate_python_venv

# Ensure logs are readable by watashi-panel
touch /opt/watashi-manager/log/xray_access.log
chmod 644 /opt/watashi-manager/log/xray_access.log
chown watashi-panel:root /opt/watashi-manager/log/xray_access.log 2>/dev/null || true


# Fix the issue in xray that it can not read multiple inbound from single file
# python <<EOF
# import json,os
# for cfg in os.listdir('configs'):
# 	if cfg.endswith('.json') and 'reality' in cfg:
# 		with open(f'configs/{cfg}') as f:
# 			data=json.load(f)
# 		os.remove(f'configs/{cfg}')
# 		for i,inb in enumerate(data.get('inbounds',[])):
# 			new_data={'inbounds':[inb]}
# 			with open(f'configs/{i}_{cfg}','w') as f:
# 				json.dump(new_data,f,indent=4)
# EOF

# curl -s -x socks://127.0.0.1:3000 http://ip-api.com?fields=message,country,countryCode,city,isp,org,as,query

if [ "$MODE" != "apply_users" ]; then
    
    # watashi v12.3.41dev: the hand built inbounds of the advanced mode are
    # checked before xray restarts and once more after it did (xray/custom_guard.sh).
    # Whatever xray refuses is taken out of their file, so the panel's own
    # inbounds start no matter what was built by hand. Without such inbounds
    # both calls return at once.
    bash /opt/watashi-manager/xray/custom_guard.sh pre
    WS_SINCE=$(date +%s)
    # xray run -test -confdir configs
    echo "Ignoring xray test"
    if [[ $? == 0 ]]; then
        systemctl restart watashi-xray.service
        systemctl start watashi-xray.service
        #systemctl status watashi-xray.service --no-pager
        bash /opt/watashi-manager/xray/custom_guard.sh post "$WS_SINCE"
    else
        echo "Error in Xray Config!!!! do not reload xray service"
        sleep 60
        xray run -test -confdir configs
        if [[ $? == 0 ]]; then
            systemctl restart watashi-xray.service
            systemctl start watashi-xray.service
            #systemctl status watashi-xray.service --no-pager
        else
            echo "Error in Xray Config!!!! do not reload xray service"
            sleep 60
        fi
    fi
    
fi
