source /opt/hiddify-manager/common/utils.sh

# watashi v12.2.130aa: the simple-obfs package draws a password in its postinst with
# pwgen, which ubuntu does not install on its own; without it the install log
# ends with 'simple-obfs.postinst: 31: pwgen: not found'. It is asked for
# first so the postinst finds it.
install_package pwgen
install_package shadowsocks-libev simple-obfs
chmod 600 *.service* 2>/dev/null || true

# Only link service file if it exists (generated from jinja template)
if [ -f "$(pwd)/hiddify-ss-faketls.service" ]; then
    ln -sf $(pwd)/hiddify-ss-faketls.service /etc/systemd/system/hiddify-ss-faketls.service
fi

systemctl disable --now ss-faketls.service > /dev/null 2>&1 || true
rm ss-faketls.service* > /dev/null 2>&1 || true