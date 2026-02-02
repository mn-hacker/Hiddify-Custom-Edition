#!/bin/bash
# Singbox test script - updated for 1.12+

systemctl restart hiddify-singbox

for CONFIG_FILE in $(find tests/ -name "*.json"); do
    echo ""
    echo ""
    echo "==================================="
    echo "Running test on $CONFIG_FILE"
    sing-box run -c $CONFIG_FILE &
    pid=$!
    sleep 3
    curl -x socks://127.0.0.1:10000 http://ip-api.com?fields=message,country,countryCode,city,isp,org,as,query
    if [ $? != 0 ];then
        echo "ERROR: $CONFIG_FILE "
        kill -9 $pid
        exit 1
    else
        echo "SUCCESS: $CONFIG_FILE "
    fi
    kill -9 $pid
done

systemctl restart hiddify-singbox