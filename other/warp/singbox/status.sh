cd $( dirname -- "$0"; )
function main(){
curl -s https://cloudflare.com/cdn-cgi/status --connect-timeout 1 -x socks://127.0.0.1:3000 > /dev/null 2>&1

if systemctl is-active --quiet hiddify-warp.service; then
    echo "Hiddify WARP Service is running."
else
    echo "Hiddify WARP Service is NOT running."
    systemctl status hiddify-warp.service --no-pager
fi

if command -v wgcf &> /dev/null; then
    wgcf status 2>/dev/null | grep -A 20 "Account" | sed '/^$/d'
elif [ -f "./wgcf" ]; then
    ./wgcf status 2>/dev/null | grep -A 20 "Account" | sed '/^$/d'
fi

curl -s -x socks://127.0.0.1:3000 --connect-timeout 2 http://ip-api.com?fields=message,country,countryCode,city,isp,org,as,query || echo "Failed to connect to WARP proxy"
}
mkdir -p log/system/
main |& tee log/system/warp.log
