
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



latest=$(curl --connect-timeout 10 -q https://gitlab.com/api/v4/projects/ProjectWARP%2Fwarp-go/releases | awk -F '"' '{for (i=0; i<NF; i++) if ($i=="tag_name") {print $(i+2); exit}}' | sed "s/v//")
latest=${latest:-'1.0.8'}
# Try to download from GitLab releases directly as fallback or primary
# But fscarmen is a common mirror. The issue might be the filename format.
# Let's use a explicit check or a better source. For now, I will fix the URL pattern if I see it's obviously wrong, OR 
# I will use a reliable hardcoded fallback if dynamic fails. 
# Actually, the fscarmen URL pattern looks correct for his repo: https://raw.githubusercontent.com/fscarmen/warp/main/warp-go/warp-go_1.0.8_linux_amd64.tar.gz
# If it failed, maybe network. I'll add a check.
URL="https://raw.githubusercontent.com/fscarmen/warp/main/warp-go/warp-go_${latest}_linux_${ARCHITECTURE}.tar.gz"
curl --connect-timeout 10 -L -o /tmp/warp-go.tar.gz "$URL"

if file /tmp/warp-go.tar.gz | grep -q "gzip compressed data"; then
    tar xzf /tmp/warp-go.tar.gz -C /tmp/ warp-go
    chmod +x /tmp/warp-go
    mv /tmp/warp-go .
else
    echo "Error: warp-go download failed or not a gzip file."
    rm -f /tmp/warp-go.tar.gz
fi

cp hiddify-warp.service /etc/systemd/system/hiddify-warp.service
systemctl enable hiddify-warp.service
systemctl daemon-reload