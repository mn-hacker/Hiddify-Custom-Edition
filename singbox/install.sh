source ../common/utils.sh
source ../common/package_manager.sh
rm -rf configs/*.template

# latest= #$(get_release_version hiddify-sing-box)
version="" #use specific version if needed otherwise it will use the latest

download_package singbox sb.zip $version
if [ "$?" == "0"  ] || ! is_installed ./sing-box; then
    install_package unzip 
    unzip -o sb.zip > /dev/null || { echo "ERROR: Failed to extract singbox"; exit 1; }
    cp -f sing-box-*/sing-box . 2>/dev/null || { echo "ERROR: Failed to copy singbox binary"; exit 2; }
    rm -rf sb.zip sing-box-* 2>/dev/null
    chown root:root sing-box || exit 3
    chmod +x sing-box || exit 4
    ln -sf /opt/hiddify-manager/singbox/sing-box /usr/bin/sing-box
    rm geosite.db 2>/dev/null 
    set_installed_version singbox $version
fi

# Enable service
ln -sf $(pwd)/hiddify-singbox.service /etc/systemd/system/hiddify-singbox.service 2>/dev/null
systemctl enable hiddify-singbox.service 2>/dev/null
