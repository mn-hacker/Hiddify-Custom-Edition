source /opt/hiddify-manager/common/utils.sh
source ./cert_utils.sh

# domains=$(cat ../current.json | jq -r '.domains[] | select(.mode | IN("direct", "cdn", "worker", "relay", "auto_cdn_ip", "old_xtls_direct", "sub_link_only")) | .domain')
shopt -s nullglob

# watashi v12.2.49: with a cloudflare token saved in the panel the dns
# challenge also works behind the cdn, so those modes are no longer stuck
# with a self signed certificate forever.
WS_MODES='"direct","relay","old_xtls_direct","sub_link_only"'
if [ -n "$(ws_cf_token)" ]; then
    WS_MODES="$WS_MODES,\"cdn\",\"worker\",\"auto_cdn_ip\""
    echo "watashi: a cloudflare token is present, cdn domains are included."
fi
domains=$(cat ../current.json | jq -r --argjson m "[$WS_MODES]" '.domains[] | select(.mode | IN($m[])) | .domain')

# Cleanup erroneous certificate file if it exists
rm -f ../ssl/cert_utils.sh.crt ../ssl/cert_utils.sh.crt.key

for d in $domains; do
    get_cert $d &
done
wait

domains=$(cat ../current.json | jq -r '.domains[] | select(.mode | IN("fake")) | .domain')
for d in $domains; do
    get_self_signed_cert $d &
done
wait

# watashi v12.2.49: haproxy needs at least one certificate to start, so every
# domain must have a file. the old loop walked ../ssl/*.crt, which with an
# empty folder passes the literal glob and creates junk, and which replaced a
# real expired certificate with a fake one without saying so.
for d in $(cat ../current.json | jq -r '.domains[] | .domain'); do
    if [ -f "../ssl/$d.crt" ] && openssl x509 -checkend 0 -noout -in "../ssl/$d.crt" >/dev/null 2>&1; then
        continue
    fi
    get_self_signed_cert $d &
done
wait
systemctl reload hiddify-haproxy 2>/dev/null || true
systemctl reload hiddify-singbox 2>/dev/null || true
# systemctl reload hiddify-xray