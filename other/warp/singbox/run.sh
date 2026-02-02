#!/bin/bash
ln -sf $(pwd)/hiddify-warp.service /etc/systemd/system/hiddify-warp.service
systemctl enable hiddify-warp.service

# Register with WARP if not already registered
if ! [ -f "wgcf-account.toml" ]; then
    echo "WARP: No account found, registering new account..."
    wgcf register --accept-tos
    if [ $? -ne 0 ]; then
        echo "WARP: Registration failed, retrying..."
        sleep 2
        wgcf register --accept-tos
    fi
    
    if [ $? -eq 0 ]; then
        wgcf generate
        echo "WARP: Account registered and profile generated"
    else
        echo "WARP: Registration failed after retry"
    fi
fi

# Update with WARP+ code if provided
if [ -n "$WARP_PLUS_CODE" ]; then
    export WGCF_LICENSE_KEY=$WARP_PLUS_CODE
    wgcf update
    if [ $? != 0 ]; then
        echo "WARP: Update failed, trying to re-register..."
        mv wgcf-account.toml wgcf-account.toml.backup 2>/dev/null
        wgcf register --accept-tos && wgcf generate && wgcf update
    fi
fi

# Generate profile if it doesn't exist
if [ -f "wgcf-account.toml" ] && ! [ -f "wgcf-profile.conf" ]; then
    wgcf generate
fi


#!/bin/bash

# Read the contents of the file
toml_content=$(cat wgcf-account.toml)

# Extract the values using pattern matching
access_token=$(echo "$toml_content" | grep -oP "access_token = '[^']+'" | sed "s/access_token = '\([^']\+\)'/\1/")
device_id=$(echo "$toml_content" | grep -oP "device_id = '[^']+'" | sed "s/device_id = '\([^']\+\)'/\1/")
private_key=$(echo "$toml_content" | grep -oP "private_key = '[^']+'" | sed "s/private_key = '\([^']\+\)'/\1/")

# Prepare the new TOML content
new_toml="[Account]
Device     = $device_id
PrivateKey = $private_key
Token      = $access_token
Type       = plus
Name       = WARP
MTU        = 1420
"

# Write the new TOML content to a file
echo "$new_toml" > warp.conf

# Check if warp-go exists before trying to use it
if [ -f "./warp-go" ] && [ -x "./warp-go" ]; then
    ./warp-go --config=warp.conf --export-singbox=warp-singbox.json
    if [ $? -ne 0 ]; then
        echo "WARP: warp-go export failed"
    fi
else
    echo "WARP: warp-go not found, creating fallback config..."
    
    # Try to generate profile if account exists but profile doesn't
    if [ -f "wgcf-account.toml" ] && ! [ -f "wgcf-profile.conf" ]; then
        echo "WARP: Generating profile from account..."
        wgcf generate 2>/dev/null
    fi
    
    # Create a minimal fallback config using the wgcf profile
    if [ -f "wgcf-profile.conf" ]; then
        # Parse wgcf-profile.conf for wireguard settings
        PrivateKey=$(grep '^PrivateKey' wgcf-profile.conf | cut -d'=' -f2 | tr -d ' ')
        Address=$(grep '^Address' wgcf-profile.conf | cut -d'=' -f2 | tr -d ' ')
        PublicKey=$(grep '^PublicKey' wgcf-profile.conf | cut -d'=' -f2 | tr -d ' ')
        
        # Use default Cloudflare WARP public key if not found
        PublicKey=${PublicKey:-"bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo="}
        
        # Create minimal singbox config
        cat > warp-singbox.json << EOFSINGBOX
{
  "type": "wireguard",
  "tag": "WARP",
  "server": "engage.cloudflareclient.com",
  "server_port": 2408,
  "local_address": ["172.16.0.2/32"],
  "private_key": "$PrivateKey",
  "peer_public_key": "$PublicKey",
  "mtu": 1280
}
EOFSINGBOX
        echo "WARP: Created fallback warp-singbox.json from profile"
    elif [ -f "wgcf-account.toml" ]; then
        # Use account data directly
        PrivateKey=$(grep 'private_key' wgcf-account.toml | grep -oP "'[^']+'" | tr -d "'")
        
        if [ -n "$PrivateKey" ]; then
            cat > warp-singbox.json << EOFSINGBOX
{
  "type": "wireguard",
  "tag": "WARP",
  "server": "engage.cloudflareclient.com",
  "server_port": 2408,
  "local_address": ["172.16.0.2/32"],
  "private_key": "$PrivateKey",
  "peer_public_key": "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
  "mtu": 1280
}
EOFSINGBOX
            echo "WARP: Created fallback warp-singbox.json from account"
        else
            echo "WARP: Could not extract private key, WARP will not be available"
        fi
    else
        echo "WARP: No wgcf-profile.conf or wgcf-account.toml found, WARP will not be available"
    fi
fi

# Only process warp-singbox.json if it exists
if [ -f "warp-singbox.json" ]; then
    sed -i "s|2000|3000|g" warp-singbox.json
    curl --connect-timeout 1 -s http://ipv6.google.com 2>&1 >/dev/null
    if [ $? != 0 ]; then
        sed -i 's/"local_address":\[[^]]*\]/"local_address":["172.16.0.2\/32"]/' warp-singbox.json
    fi
else
    echo "WARP: warp-singbox.json not found, skipping WARP service"
fi


# while read -r line; do
#     if [[ "$line" == \[*] ]]; then
#         section=${line#[}
#         section=${section%]}
#     elif [[ "$line" =~ ^[[:space:]]*([^[:space:]]+)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
#         key=${BASH_REMATCH[1]}
#         value=${BASH_REMATCH[2]}
#         var="${section}_${key}"
#         value=$(echo "$value" | sed -e 's/^"//' -e 's/"$//')
#         export "$var"="$value"
#     fi
# done < "wgcf-profile.conf"


# cat > xray_warp_conf.json << EOM
#     {
#       "tag": "WARP",
#       "protocol": "wireguard",
#       "settings": {
#         "secretKey": "$Interface_PrivateKey",
#         "address": [
#           "172.16.0.2/32",
#           "$Interface_Address"
#         ],
#         "peers": [
#           {
#             "publicKey": "$Peer_PublicKey",
#             "endpoint": "$Peer_Endpoint"
#           }
#         ],
#         "reserved":[0, 0, 0], 
#         "mtu": 1280
#       }
#     }
# EOM


# peer_domain="${Peer_Endpoint%%:*}"
# peer_port="${Peer_Endpoint#*:}"

# cat > singbox_warp_conf.json << EOM
# {
#   "type": "wireguard",
#   "tag": "WARP",
#   "server": "$peer_domain",
#   "server_port": $peer_port,
#   "system_interface": false,

#   "local_address": [
#     "172.16.0.2/32",
#     "$Interface_Address"
#   ],
#   "private_key": "$Interface_PrivateKey",
#   "peer_public_key": "$Peer_PublicKey",
#   "reserved": [0, 0, 0],
#   "mtu": 1280
# }

# EOM
#"interface_name": "wg0",
#"pre_shared_key": "31aIhAPwktDGpH4JDhA8GNvjFXEf/a6+UaQRyOAiyfM=",
#"workers": 8,
# warp_conf=$(cat xray_warp_conf.json)
# warp_conf=$(echo "$warp_conf" | tr '\n' ' ')
# escaped_warp_conf=$(printf '%s\n' "$warp_conf" | sed -e 's/[\/&]/\\&/g')
# sed "s|//hiddify_warp|$escaped_warp_conf|g"  xray_demo.json.template > xray_demo.json

# singbox_warp_conf=$(cat singbox_warp_conf.json)
# singbox_warp_conf=$(echo "$singbox_warp_conf" | tr '\n' ' ')
# escaped_singbox_warp_conf=$(printf '%s\n' "$singbox_warp_conf" | sed -e 's/[\/&]/\\&/g')
# sed "s|//hiddify_warp|$escaped_singbox_warp_conf|g"  singbox_demo.json.template > singbox_demo.json
# sed "s|//hiddify_warp|$escaped_singbox_warp_conf|g"  warp-singbox.json.template > warp-singbox.json



# xray -c xray_demo.json >/dev/null  &
# pid=$!
# sleep 3
# curl -x socks://127.0.0.1:1230 www.ipinfo.io
# curl -x socks://127.0.0.1:1230 http://ip-api.com?fields=message,country,countryCode,city,isp,org,as,query
# if [ $? != 0 ];then
#     rm xray_warp_conf.json
# else
#    echo ""
#    echo "==========WARP is working=============="
# fi
# kill -9 $pid



# echo "Testing singbox warp"

# sing-box run -c singbox_demo.json >/dev/null  &
# pid=$!
# sleep 3
# curl -x socks://127.0.0.1:1231 www.ipinfo.io
# curl -x socks://127.0.0.1:1231 http://ip-api.com?fields=message,country,countryCode,city,isp,org,as,query
# if [ $? != 0 ];then
#     rm singbox_warp_conf.json
# else
#    echo ""
#    echo "==========WARP is working=============="
# fi
# kill -9 $pid



# Only start WARP service if config exists
if [ -f "warp-singbox.json" ]; then
    # Try reload if already running, otherwise just start
    if systemctl is-active --quiet hiddify-warp.service; then
        systemctl reload hiddify-warp.service || systemctl restart hiddify-warp.service
    else
        systemctl start hiddify-warp.service
    fi
    
    sleep 5
    echo "Testing singbox warp"
    
    curl -x socks://127.0.0.1:3000 --connect-timeout 4 www.ipinfo.io
    curl -x socks://127.0.0.1:3000 --connect-timeout 4 http://ip-api.com?fields=message,country,countryCode,city,isp,org,as,query
    if [ $? != 0 ]; then
        echo "WARP is not working"
    else
        echo ""
        echo "==========WARP is working=============="
    fi
else
    echo "WARP: Config not available, skipping WARP service"
    systemctl stop hiddify-warp.service 2>/dev/null || true
fi

# echo "Remaining..."
# bash check-quota.sh
# fi