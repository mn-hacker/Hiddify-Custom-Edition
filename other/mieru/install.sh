# watashi v12.2.103: the mieru server, installed like every other core.
#
# The binary is not shipped in this package. core_manager.sh downloads the
# version core_registry.conf blesses and verifies it against packages.lock,
# exactly as it does for xray, sing-box and mtg, so mieru cannot drift onto an
# untested build behind our back.
source /opt/hiddify-manager/common/utils.sh

CM_SH=/opt/hiddify-manager/common/core_manager.sh
if [ -f "$CM_SH" ]; then
    bash $CM_SH default mita || echo "watashi: mita could not be installed, mieru stays off"
fi

if [ ! -x /opt/hiddify-manager/other/mieru/mita ]; then
    echo "watashi: the mita binary is not on the disk, nothing was enabled"
    exit 0
fi

chmod 600 *.service* 2>/dev/null || true
ln -sf $(pwd)/watashi-mita.service /etc/systemd/system/watashi-mita.service
systemctl daemon-reload 2>/dev/null || true
