# watashi v12.3.40dev: the old project name was taken out of this file (names, paths and links only)
source /opt/watashi-manager/common/utils.sh
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

# watashi v12.3.39dev: the addresses of this server are looked up once, here, and
# every request below inherits them. The timer starts this file without the
# SERVER_IP that install.sh exports, which made every domain look foreign.
ws_server_addrs >/dev/null

for d in $domains; do
    get_cert $d &
done
wait
# watashi v12.3.39dev: every request closes the challenge path only when it is the last
# one using it. This closes it for good once all of them are done.
ws_http_challenge_cleanup

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
    # watashi v12.3.39dev: a pair whose key does not match counts as missing, haproxy
    # would not start with it.
    if [ -f "../ssl/$d.crt" ] && openssl x509 -checkend 0 -noout -in "../ssl/$d.crt" >/dev/null 2>&1 &&
        ws_cert_key_match "../ssl/$d.crt" "../ssl/$d.crt.key"; then
        continue
    fi
    get_self_signed_cert $d &
done
wait
# watashi v12.2.130ax: every certificate issued between v12.2.49 and now is RSA 2048,
# and nothing on a running server would ever replace it, because get_cert
# returns early while a certificate is still valid. So the fix has to come
# and collect them once.
#
# Serially on purpose. Twenty two domains asking an authority at the same
# moment is how a rate limit is met, and there is no hurry: the server keeps
# serving its rsa certificates until each one is replaced.
#
# A self signed certificate needs no authority at all, so it is simply
# rewritten. Only a certificate from a real authority is reissued.
ws_ec_marker=/opt/watashi-manager/log/system/.watashi-ec-migrated
if [ ! -f "$ws_ec_marker" ] && [ "${WS_SKIP_EC_MIGRATION:-0}" != "1" ]; then
    echo "watashi: looking for rsa certificates left by an older build..."
    ws_ec_done=0
    for d in $(cat ../current.json | jq -r '.domains[] | .domain'); do
        crt="../ssl/$d.crt"
        ws_cert_is_rsa "$crt" || continue
        issuer=$(openssl x509 -issuer -noout -in "$crt" 2>/dev/null | sed 's/issuer=//')
        subject=$(openssl x509 -subject -noout -in "$crt" 2>/dev/null | sed 's/subject=//')
        if [ "$issuer" = "$subject" ]; then
            echo "watashi: $d has a self signed rsa certificate, rewriting it as ec-256"
            rm -f "$crt" "$crt.key"
            get_self_signed_cert "$d"
        else
            echo "watashi: $d has an rsa certificate from an authority, asking for ec-256"
            WS_SSL_FORCE=1 WS_CERT_REKEY=1 get_cert "$d" || echo "watashi: $d could not be reissued now, it keeps its rsa certificate"
        fi
        ws_ec_done=$((ws_ec_done + 1))
    done
    echo "watashi: $ws_ec_done certificate(s) looked at, the migration will not run again"
    mkdir -p "$(dirname "$ws_ec_marker")" 2>/dev/null || true
    date -u +%FT%TZ >"$ws_ec_marker"
fi

systemctl reload watashi-haproxy 2>/dev/null || true
systemctl reload watashi-singbox 2>/dev/null || true
# systemctl reload watashi-xray