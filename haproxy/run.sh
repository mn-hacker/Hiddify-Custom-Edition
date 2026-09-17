# ln -sf $(pwd)/haproxy.cfg /etc/haproxy/haproxy.cfg

# REALITY_SERVER_NAMES_HAPROXY=$(echo "$REALITY_SERVER_NAMES" | sed 's/,/ || /g')
# sed -i "s|REALITY_SERVER_NAMES|server $REALITY_SERVER_NAMES_HAPROXY|g" haproxy.cfg

#
source /opt/hiddify-manager/common/utils.sh

chmod 600 *.cfg*
# systemctl reload hiddify-haproxy
systemctl stop hiddify-haproxy
# watashi v12.2.130: this used to name one wrong file, cert_utils.sh.crt, because
# that is the one that broke a panel once. haproxy reads the whole folder,
# so every other shape of leftover did the same thing later: .crt.bk pairs,
# a .crt written from a script name, a certificate whose key is gone. The
# sweep below is general, and then every remaining pair is checked before
# haproxy is asked to start. This is the ssl repair script we used to run by
# hand, now part of the start itself.
ws_ssl_dir=/opt/hiddify-manager/ssl
ws_ssl_bk=/opt/hiddify-manager/log/ssl-backup
mkdir -p "$ws_ssl_bk" 2>/dev/null || true
shopt -s nullglob
# anything that is not a plain <domain>.crt or <domain>.crt.key is not for haproxy
for f in "$ws_ssl_dir"/*; do
    name=$(basename "$f")
    case "$name" in
        *.crt | *.crt.key | *.pem | ca.crt | dhparam*) ;;
        *) echo "watashi: $name does not belong in the ssl folder, moving it aside"
           mv -f "$f" "$ws_ssl_bk/" 2>/dev/null || rm -f "$f" ;;
    esac
done
# a script name is not a domain
for f in "$ws_ssl_dir"/*.sh.crt "$ws_ssl_dir"/*.sh.crt.key; do
    echo "watashi: removing $(basename "$f"), a script name is not a domain"
    rm -f "$f"
done
# a certificate with no key, or a key with no certificate, stops every bind
for f in "$ws_ssl_dir"/*.crt; do
    d=${f%.crt}
    if [ ! -s "$d.crt.key" ]; then
        echo "watashi: $(basename "$f") has no private key, moving it aside"
        mv -f "$f" "$ws_ssl_bk/" 2>/dev/null || rm -f "$f"
        continue
    fi
    if ! openssl x509 -in "$f" -noout >/dev/null 2>&1; then
        echo "watashi: $(basename "$f") is not a readable certificate, moving it aside"
        mv -f "$f" "$ws_ssl_bk/" 2>/dev/null || rm -f "$f"
        mv -f "$d.crt.key" "$ws_ssl_bk/" 2>/dev/null || rm -f "$d.crt.key"
    fi
done
for f in "$ws_ssl_dir"/*.crt.key; do
    [ -s "${f%.key}" ] || { echo "watashi: $(basename "$f") has no certificate, moving it aside"
                            mv -f "$f" "$ws_ssl_bk/" 2>/dev/null || rm -f "$f"; }
done
shopt -u nullglob
systemctl start hiddify-haproxy
