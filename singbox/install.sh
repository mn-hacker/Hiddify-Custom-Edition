source /opt/hiddify-manager/common/utils.sh
source /opt/hiddify-manager/common/package_manager.sh
rm -rf configs/*.template 2>/dev/null || true

# latest= #$(get_release_version hiddify-sing-box)
version="" #use specific version if needed otherwise it will use the latest

download_package singbox sb.tar.gz $version
if [ "$?" == "0"  ] || ! is_installed ./sing-box; then
    # install_package unzip 
    
    # Extract archive
    tar -xzf sb.tar.gz > /dev/null 2>&1 || { echo "ERROR: Failed to extract singbox"; exit 1; }
    
    # Find and copy binary - handle both directory format and flat format
    if [ -d "sing-box-"* ]; then
        # Directory format (e.g., sing-box-1.8.8-linux-amd64/)
        cp -f sing-box-*/sing-box . 2>/dev/null || { echo "ERROR: Failed to copy singbox binary from directory"; exit 2; }
    elif [ -f "sing-box" ]; then
        # Already extracted flat
        echo "Singbox binary already in place"
    else
        echo "ERROR: Cannot find singbox binary in archive"
        exit 2
    fi
    
    rm -rf sb.tar.gz sing-box-* 2>/dev/null || true
    chown root:root sing-box 2>/dev/null || exit 3
    chmod +x sing-box || exit 4
    ln -sf /opt/hiddify-manager/singbox/sing-box /usr/bin/sing-box
    rm geosite.db 2>/dev/null || true
    set_installed_version singbox $version
fi

# Enable service
ln -sf $(pwd)/hiddify-singbox.service /etc/systemd/system/hiddify-singbox.service 2>/dev/null || true
systemctl enable hiddify-singbox.service 2>/dev/null || true
