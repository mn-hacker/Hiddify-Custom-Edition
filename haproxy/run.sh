# ln -sf $(pwd)/haproxy.cfg /etc/haproxy/haproxy.cfg

# REALITY_SERVER_NAMES_HAPROXY=$(echo "$REALITY_SERVER_NAMES" | sed 's/,/ || /g')
# sed -i "s|REALITY_SERVER_NAMES|server $REALITY_SERVER_NAMES_HAPROXY|g" haproxy.cfg

#
source /opt/hiddify-manager/common/utils.sh

chmod 600 *.cfg*
# systemctl reload hiddify-haproxy
systemctl stop hiddify-haproxy
# Cleanup erroneous certificate file if it exists to prevent startup failure
rm -f /opt/hiddify-manager/ssl/cert_utils.sh.crt /opt/hiddify-manager/ssl/cert_utils.sh.crt.key
systemctl start hiddify-haproxy
