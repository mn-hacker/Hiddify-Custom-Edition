# watashi v12.3.40dev: the old project name was taken out of this file (names, paths and links only)
# watashi v12.3.40dev: the shadowsocks-over-v2ray unit of the old releases is
# not touched here any more; it only existed under the old name and goes with
# every other unit of that name (common/watashi_legacy.sh).
systemctl stop watashi-ss-faketls.service > /dev/null 2>&1

systemctl disable --now ss-v2ray.service > /dev/null 2>&1
systemctl disable --now ss-faketls.service > /dev/null 2>&1

systemctl disable --now watashi-ss-faketls.service > /dev/null 2>&1
rm ss-faketls.service* > /dev/null 2>&1