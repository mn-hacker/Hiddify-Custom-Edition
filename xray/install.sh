source /opt/hiddify-manager/common/utils.sh
source /opt/hiddify-manager/common/package_manager.sh
# latest= #$(get_release_version hiddify-sing-box)
version="" #use specific version if needed otherwise it will use the latest
mkdir -p bin run

download_package xray sb.zip $version
if [ "$?" == "0"  ] || ! is_installed ./bin/xray; then
    install_package unzip
    # watashi v12.2.50: unpack beside the live binary and only take over
    # when the new one really runs. `rm -rf bin/*` used to throw away the
    # working xray and the geo files before anyone knew whether the new
    # archive was usable at all.
    rm -rf bin/.new
    mkdir -p bin/.new
    unzip -o sb.zip -d bin/.new > /dev/null || { echo "ERROR: Failed to extract xray"; exit 1; }
    rm -f sb.zip
    chmod +x bin/.new/xray 2>/dev/null
    if ! bin/.new/xray version >/dev/null 2>&1; then
        echo "ERROR: the new xray binary does not run here, keeping the current one"
        rm -rf bin/.new
        exit 1
    fi
    systemctl stop hiddify-xray.service > /dev/null 2>&1
    if [ -f bin/xray ]; then
        cp -f bin/xray bin/xray.previous 2>/dev/null || true
    fi
    cp -f bin/.new/xray bin/xray.new && mv -f bin/xray.new bin/xray
    cp -f bin/.new/*.dat bin/ 2>/dev/null || true
    rm -rf bin/.new
    chown root:root bin/xray || exit 2
    chmod +x bin/xray || exit 3
    ln -sf /opt/hiddify-manager/xray/bin/xray /usr/bin/xray
    set_installed_version xray "$version" "$(detect_arch)"
fi

# Enable service
ln -sf $(pwd)/hiddify-xray.service /etc/systemd/system/hiddify-xray.service 2>/dev/null
systemctl enable hiddify-xray.service 2>/dev/null

# Download enhanced geo files from Iran-v2ray-rules for full adblock support
# These files include: category-ads-all, phishing, malware, category-gambling, nsfw, social media sites
GEO_URL="https://github.com/Chocolate4U/Iran-v2ray-rules/releases/latest/download"
# watashi v12.2.50: these two files are about 10 MB each and do not change
# during a reinstall. fetch them only when they are missing or a week old,
# and never let a failed download replace a good file.
for geo in geosite.dat geoip.dat; do
    if [ -s "bin/$geo" ] && [ -z "$(find bin/$geo -mtime +7 2>/dev/null)" ]; then
        echo "$geo is recent, keeping it"
        continue
    fi
    if curl -sL --connect-timeout 10 -o "bin/$geo.new" "${GEO_URL}/$geo" && [ -s "bin/$geo.new" ]; then
        mv -f "bin/$geo.new" "bin/$geo"
        echo "$geo updated"
    else
        rm -f "bin/$geo.new"
        echo "Warning: Failed to download $geo, keeping the current file"
    fi
done
