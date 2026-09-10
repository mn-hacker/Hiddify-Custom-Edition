# watashi v12.2.103: mieru off means the daemon stops holding its ports.
source /opt/hiddify-manager/common/utils.sh 2>/dev/null || true

MITA=/opt/hiddify-manager/other/mieru/mita
export MITA_CONFIG_FILE=/opt/hiddify-manager/other/mieru/server.conf.pb
export MITA_UDS_PATH=/opt/hiddify-manager/other/mieru/mita.sock

# The proxy is asked to stop first so the listeners are closed in an orderly
# way; only then is the daemon taken down. A stop on a daemon that is already
# gone is not an error worth printing.
if [ -x "$MITA" ] && [ -S "$MITA_UDS_PATH" ]; then
    $MITA stop >/dev/null 2>&1 || true
fi

systemctl disable --now watashi-mita.service >/dev/null 2>&1 || true
