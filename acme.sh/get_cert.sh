#!/bin/bash
# watashi v12.3.40dev: the old project name was taken out of this file (names, paths and links only)
cd $(dirname -- "$0")
source cert_utils.sh
# watashi v12.2.49: this path is a deliberate request from the panel, so it
# ignores the cooldown that protects the scheduled runs.
export WS_SSL_FORCE="${WS_SSL_FORCE:-1}"
# watashi v12.3.39dev: --force is the button on the domain card. It asks for a new
# certificate even while the current one looks valid, which is the only way
# out once a server has been told, wrongly, that it already has one.
if [ "$2" = "--force" ]; then
    export WS_SSL_REISSUE=1
fi
#./lib/acme.sh --register-account -m my@example.com
get_cert "$1"
rc=$?
# watashi v12.3.39dev: haproxy and sing-box are reloaded by the install step, xray is
# not: it reads the certificate files again on its own, once an hour. After
# the button replaced a certificate the clients could not use, an hour of
# "still broken" is not acceptable, so xray is restarted, and only then.
if [ "${WS_SSL_REISSUE:-0}" = "1" ] && [ "$WS_CERT_RESULT" = "ok" ] && [ "${WS_CERT_WAS_REAL:-0}" != "1" ]; then
    if grep -rqsF "/opt/watashi-manager/ssl/$1.crt" /opt/watashi-manager/xray/configs/ 2>/dev/null &&
        systemctl is-active --quiet watashi-xray 2>/dev/null; then
        echo "watashi: restarting xray so it serves the new certificate of $1 now"
        systemctl restart watashi-xray 2>/dev/null || echo "watashi: xray did not restart, it picks the certificate up within the hour"
    fi
fi
exit $rc
