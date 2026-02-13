source /opt/hiddify-manager/common/utils.sh
source ./cert_utils.sh

# domains=$(cat ../current.json | jq -r '.domains[] | select(.mode | IN("direct", "cdn", "worker", "relay", "auto_cdn_ip", "old_xtls_direct", "sub_link_only")) | .domain')
domains=$(cat ../current.json | jq -r '.domains[] | select(.mode | IN("direct",   "relay", "old_xtls_direct", "sub_link_only")) | .domain')

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

for f in ../ssl/*.crt; do
    d=$(basename "$f" .crt)
    get_self_signed_cert $d &
done
wait
systemctl reload hiddify-haproxy 2>/dev/null || true
systemctl reload hiddify-singbox 2>/dev/null || true
# systemctl reload hiddify-xray