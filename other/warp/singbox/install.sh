
if ! [ -f "wgcf-account.toml" ];then
    # mv wgcf-account.toml wgcf-account.toml.backup
    TAR="https://api.github.com/repos/ViRb3/wgcf/releases/latest"
    ARCH=$(dpkg --print-architecture)
    URL=$(curl --connect-timeout 10 -fsSL ${TAR} | grep 'browser_download_url' | cut -d'"' -f4 | grep linux | grep "${ARCH}")
    curl --connect-timeout 10 -fsSL "${URL}" -o ./wgcf && chmod +x ./wgcf && mv ./wgcf /usr/bin
fi

if ! [ -f "wgcf-account.toml" ];then
    wgcf register --accept-tos
    wgcf generate
fi



ARCHITECTURE=$(dpkg --print-architecture)





cp hiddify-warp.service /etc/systemd/system/hiddify-warp.service
systemctl enable hiddify-warp.service
systemctl daemon-reload