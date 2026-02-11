cd $( dirname -- "$0"; )
source /opt/hiddify-manager/common/utils.sh
source /opt/hiddify-manager/common/package_manager.sh

function main(){

# Check if wgcf exists, if not try to install it
if [ ! -f "./wgcf" ]; then
    warning "wgcf binary not found, attempting to download..."
    download_package wgcf wgcf
    if [ $? -eq 0 ]; then
        chmod +x wgcf
        set_installed_version wgcf
    else
        error "Failed to download wgcf. Please run WARP installation first."
        exit 1
    fi
fi

# curl -s --interface warp https://cloudflare.com/cdn-cgi/status --connect-timeout 1
warning "- Warp Status:"
warning "  - Profile:"
status=$(./wgcf status 2>&1)
if [ $? -eq 0 ]; then
    echo "$status" | sed 's|^|\t|'
else
    echo -e "$status" | head -n 2 | sed 's|^|\t|'
fi

warning "  - Network:"
curl -s --interface warp --connect-timeout 1 http://ip-api.com?fields=country,city,org,query | sed 's|^|      | ; /[{}]/d'
# warning "  - Warp Trace:"
# curl -s --interface warp https://cloudflare.com/cdn-cgi/trace --connect-timeout 1 | sed 's|^|\t|'
}

mkdir -p log/system/
main |& tee log/system/warp.log
