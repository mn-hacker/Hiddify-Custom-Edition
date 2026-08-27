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
    
    # watashi v12.2.50: find the binary by name. `[ -d "sing-box-"* ]` is a
    # bash error the moment that glob matches more than one directory, and
    # the old copy landed on the live binary with no check that it runs.
    SB_NEW=$(find . -maxdepth 3 -type f -name sing-box ! -path ./sing-box -print -quit 2>/dev/null)
    if [ -n "$SB_NEW" ]; then
        cp -f "$SB_NEW" ./sing-box.new || { echo "ERROR: Failed to copy singbox binary"; exit 2; }
        chmod +x ./sing-box.new
        if ! ./sing-box.new version >/dev/null 2>&1; then
            echo "ERROR: the new sing-box binary does not run here, keeping the current one"
            rm -f ./sing-box.new
            exit 5
        fi
        if [ -f ./sing-box ]; then
            cp -f ./sing-box ./sing-box.previous 2>/dev/null || true
        fi
        mv -f ./sing-box.new ./sing-box
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
    set_installed_version singbox "$version" "$(detect_arch)"
fi

# Enable service
ln -sf $(pwd)/hiddify-singbox.service /etc/systemd/system/hiddify-singbox.service 2>/dev/null || true
systemctl enable hiddify-singbox.service 2>/dev/null || true
