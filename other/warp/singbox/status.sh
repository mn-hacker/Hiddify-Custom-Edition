cd $( dirname -- "$0"; )
function main(){
curl https://cloudflare.com/cdn-cgi/status --connect-timeout 1 -x socks://127.0.0.1:3000

if command -v wgcf &> /dev/null; then
    wgcf status
elif [ -f "./wgcf" ]; then
    ./wgcf status
else
    echo "wgcf not found"
fi

if systemctl is-active --quiet hiddify-warp.service; then
    echo "Hiddify WARP Service is running."
else
    echo "Hiddify WARP Service is NOT running."
    systemctl status hiddify-warp.service --no-pager
fi

curl -s -x socks://127.0.0.1:3000 --connect-timeout 2 http://ip-api.com?fields=message,country,countryCode,city,isp,org,as,query || echo "Failed to connect to WARP proxy"
ps aux | grep -v grep | grep warp
}
mkdir -p log/system/
main |& tee log/system/warp.log
