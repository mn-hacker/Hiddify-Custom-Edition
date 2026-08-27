source /opt/hiddify-manager/common/utils.sh
install_package socat
remove_package certbot

mkdir -p /opt/hiddify-manager/acme.sh/lib/
if ! is_installed ./lib/acme.sh; then
    curl -s -L https://get.acme.sh | sh -s -- home /opt/hiddify-manager/acme.sh/lib \
    --config-home /opt/hiddify-manager/acme.sh/lib/data \
    --cert-home /opt/hiddify-manager/acme.sh/lib/certs --nocron
    
    sed -i 's|_sleep_overload_retry_sec=$_retryafter|_sleep_overload_retry_sec=$_retryafter; if [ "$_retryafter" -gt 20 ] 2>/dev/null;then return 10; fi|g' lib/acme.sh
fi

mkdir -p ../ssl/
./lib/acme.sh --uninstall-cronjob
shopt -s expand_aliases
source ./lib/acme.sh.env
# watashi v12.2.49: my@example.com is refused by several CAs. build the
# account email from the first real domain, and register only if we have one.
WS_ROOT=$(jq -r '.domains[0].domain // empty' ../current.json 2>/dev/null | awk -F. '{ if (NF<=2) print $0; else print $(NF-1)"."$NF }')
if [ -n "$WS_ROOT" ]; then
    acme.sh --register-account --server letsencrypt -m "ssl@$WS_ROOT" || true
else
    echo "watashi: no domain in current.json yet, the account is registered with the first certificate."
fi

# watashi v12.2.49: acme.sh's own cron job is uninstalled above and nothing
# replaced it, so certificates simply expired. we own the schedule now.
cp -f watashi-cert-renew.service watashi-cert-renew.timer /etc/systemd/system/ 2>/dev/null
systemctl daemon-reload 2>/dev/null
systemctl enable --now watashi-cert-renew.timer 2>/dev/null
systemctl reload hiddify-haproxy
