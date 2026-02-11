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

curl -s -x socks://127.0.0.1:3000 --connect-timeout 1 http://ip-api.com?fields=message,country,countryCode,city,isp,org,as,query

}
mkdir -p log/system/
main |& tee log/system/warp.log
