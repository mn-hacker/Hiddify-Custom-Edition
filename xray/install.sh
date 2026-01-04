source ../common/utils.sh
source ../common/package_manager.sh
# latest= #$(get_release_version hiddify-sing-box)
version="" #use specific version if needed otherwise it will use the latest
mkdir -p bin run

download_package xray sb.zip $version
if [ "$?" == "0"  ] || ! is_installed ./bin/xray; then
    systemctl stop hiddify-xray.service > /dev/null 2>&1 
    rm -rf bin/*
    install_package unzip 
    unzip -o sb.zip -d bin/ > /dev/null || { echo "ERROR: Failed to extract xray"; exit 1; }
    rm -f sb.zip 
    chown root:root bin/xray || exit 2
    chmod +x bin/xray || exit 3
    ln -sf /opt/hiddify-manager/xray/bin/xray /usr/bin/xray
    set_installed_version xray $version
fi

# Enable service
ln -sf $(pwd)/hiddify-xray.service /etc/systemd/system/hiddify-xray.service 2>/dev/null
systemctl enable hiddify-xray.service 2>/dev/null

# Download enhanced geo files from Iran-v2ray-rules for full adblock support
# These files include: category-ads-all, phishing, malware, category-gambling, nsfw, social media sites
GEO_URL="https://github.com/Chocolate4U/Iran-v2ray-rules/releases/latest/download"
echo "Downloading enhanced geo files for adblock..."
curl -sL --connect-timeout 10 "${GEO_URL}/geosite.dat" -o bin/geosite.dat || echo "Warning: Failed to download geosite.dat"
curl -sL --connect-timeout 10 "${GEO_URL}/geoip.dat" -o bin/geoip.dat || echo "Warning: Failed to download geoip.dat"
