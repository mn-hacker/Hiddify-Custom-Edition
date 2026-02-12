restricted_tlds=("af" "by" "cu" "er" "gn" "ir" "kp" "lr" "ru" "ss" "su" "sy" "zw" "amazonaws.com","azurewebsites.net","cloudapp.net")
shopt -s expand_aliases

source ./lib/acme.sh.env
source /opt/hiddify-manager/common/utils.sh

# Function to check if a domain is restricted for ZeroSSL
is_ok_domain_zerossl() {
    domain="$1"
    for tld in "${restricted_tlds[@]}"; do
        if [[ $domain == *.$tld ]]; then
            return 1 # Domain is restricted
        fi
    done
    return 0 # Domain is not restricted
}

# List of Certificate Authorities to try (in order of preference)
# Format: "server_name|description|needs_eab"
CA_SERVERS=(
    "letsencrypt|Let's Encrypt|no"
    "zerossl|ZeroSSL|eab"
    "google|Google Trust Services|no"
    "buypass|Buypass Go SSL|no"
)

function try_get_cert_with_ca() {
    local DOMAIN=$1
    local CA_SERVER=$2
    local CA_DESC=$3
    local NEEDS_EAB=$4
    local MAX_RETRIES=2
    local RETRY_DELAY=10
    
    echo "====== Trying $CA_DESC ($CA_SERVER) for $DOMAIN ======"
    
    # Skip ZeroSSL for restricted domains
    if [[ "$CA_SERVER" == "zerossl" ]] && ! is_ok_domain_zerossl "$DOMAIN"; then
        echo "Domain $DOMAIN is restricted for ZeroSSL, skipping..."
        return 1
    fi
    
    for ((i=1; i<=MAX_RETRIES; i++)); do
        echo "Attempt $i of $MAX_RETRIES..."
        
        # Try to issue certificate
        if [[ "$CA_SERVER" == "letsencrypt_test" ]]; then
            acme.sh --issue -w /opt/hiddify-manager/acme.sh/www/ -d $DOMAIN \
                --log $(pwd)/../log/system/acme.log \
                --server letsencrypt_test \
                --pre-hook "systemctl restart hiddify-nginx" \
                --force 2>&1
        else
            acme.sh --issue -w /opt/hiddify-manager/acme.sh/www/ -d $DOMAIN \
                --log $(pwd)/../log/system/acme.log \
                --server $CA_SERVER \
                --pre-hook "systemctl restart hiddify-nginx" \
                --force 2>&1
        fi
        
        local result=$?
        
        if [ $result -eq 0 ]; then
            echo "✓ Success with $CA_DESC!"
            return 0
        elif [ $result -eq 2 ]; then
            # Already issued, try to renew
            echo "Certificate already exists, attempting renewal..."
            acme.sh --renew -d $DOMAIN --force 2>&1
            if [ $? -eq 0 ]; then
                return 0
            fi
        fi
        
        if [ $i -lt $MAX_RETRIES ]; then
            echo "Failed, waiting ${RETRY_DELAY}s before retry..."
            sleep $RETRY_DELAY
        fi
    done
    
    echo "✗ Failed with $CA_DESC after $MAX_RETRIES attempts"
    return 1
}

function get_cert() {
    cd /opt/hiddify-manager/acme.sh/
    source ./lib/acme.sh.env

    DOMAIN=$1
    ssl_cert_path=/opt/hiddify-manager/ssl
    
    echo "=========================================="
    echo "Getting SSL certificate for: $DOMAIN"
    echo "=========================================="

    # Check if we already have a valid certificate (not expiring within 30 days)
    # Skip self-signed certs (they have very long validity or issuer == subject)
    if [ -f "$ssl_cert_path/$DOMAIN.crt" ] && [ -f "$ssl_cert_path/$DOMAIN.crt.key" ]; then
        local issuer=$(openssl x509 -issuer -noout -in "$ssl_cert_path/$DOMAIN.crt" 2>/dev/null | sed 's/issuer=//')
        local subject=$(openssl x509 -subject -noout -in "$ssl_cert_path/$DOMAIN.crt" 2>/dev/null | sed 's/subject=//')
        local expire_date=$(openssl x509 -enddate -noout -in "$ssl_cert_path/$DOMAIN.crt" 2>/dev/null | cut -d= -f2-)
        
        if [ -n "$expire_date" ] && [ "$issuer" != "$subject" ]; then
            local expire_epoch=$(date -d "$expire_date" +%s 2>/dev/null)
            local now_epoch=$(date +%s)
            local days_left=$(( (expire_epoch - now_epoch) / 86400 ))
            
            # Skip only if cert is from a real CA (validity < 400 days) and still valid
            if [ "$days_left" -gt 30 ] && [ "$days_left" -lt 400 ]; then
                echo "✓ Existing certificate is valid for $days_left more days, skipping renewal."
                return 0
            elif [ "$days_left" -le 30 ]; then
                echo "Certificate expires in $days_left days, attempting renewal..."
            else
                echo "Certificate has unusually long validity ($days_left days), likely self-signed. Getting new cert..."
            fi
        else
            echo "Existing certificate is self-signed or invalid, getting new cert..."
        fi
    fi

    # Check domain length (Let's Encrypt limit is 64 chars)
    if [ ${#DOMAIN} -gt 64 ]; then
        echo "ERROR: Domain name too long (${#DOMAIN} > 64 chars)"
        bash generate_self_signed_cert.sh $DOMAIN
        return 1
    fi

    # Setup ACME challenge directory
    mkdir -p /opt/hiddify-manager/acme.sh/www/.well-known/acme-challenge
    echo "location /.well-known/acme-challenge {root /opt/hiddify-manager/acme.sh/www/;}" >/opt/hiddify-manager/nginx/parts/acme.conf
    systemctl reload --now hiddify-nginx

    # Verify DNS resolution
    DOMAIN_IP=$(dig +short -t a $DOMAIN. | head -1)
    DOMAIN_IPv6=$(dig +short -t aaaa $DOMAIN. | head -1)
    echo "DNS Resolution: $DOMAIN -> IPv4=$DOMAIN_IP, IPv6=$DOMAIN_IPv6"
    echo "Server IPs: IPv4=$SERVER_IP, IPv6=$SERVER_IPv6"

    if [[ -z "$DOMAIN_IP" && -z "$DOMAIN_IPv6" ]]; then
        error "ERROR: Domain $DOMAIN does not resolve to any IP!"
        bash generate_self_signed_cert.sh $DOMAIN
        return 1
    fi

    if [[ "$SERVER_IP" != "$DOMAIN_IP" && "$SERVER_IPv6" != "$DOMAIN_IPv6" ]]; then
        echo "WARNING: Domain IP doesn't match server IP. SSL verification may fail."
    fi

    # Backup existing certificates
    if [ -f "$ssl_cert_path/$DOMAIN.crt" ]; then
        cp "$ssl_cert_path/$DOMAIN.crt" "$ssl_cert_path/$DOMAIN.crt.bk"
        cp "$ssl_cert_path/$DOMAIN.crt.key" "$ssl_cert_path/$DOMAIN.crt.key.bk"
    fi

    # Try each CA in order until one succeeds
    local cert_obtained=0
    for ca_info in "${CA_SERVERS[@]}"; do
        IFS='|' read -r ca_server ca_desc needs_eab <<< "$ca_info"
        
        if try_get_cert_with_ca "$DOMAIN" "$ca_server" "$ca_desc" "$needs_eab"; then
            cert_obtained=1
            echo "Successfully obtained certificate from $ca_desc"
            break
        fi
        
        echo "Moving to next CA provider..."
        sleep 5
    done

    if [ $cert_obtained -eq 1 ]; then
        # Install the certificate
        acme.sh --installcert -d $DOMAIN \
            --fullchainpath $ssl_cert_path/$DOMAIN.crt \
            --keypath $ssl_cert_path/$DOMAIN.crt.key \
            --reloadcmd "echo success"
        
        if [ $? -eq 0 ]; then
            echo "✓ Certificate installed successfully!"
            rm -f "$ssl_cert_path/$DOMAIN.crt.bk" "$ssl_cert_path/$DOMAIN.crt.key.bk"
        else
            echo "ERROR: Failed to install certificate, restoring backup..."
            [ -f "$ssl_cert_path/$DOMAIN.crt.bk" ] && mv "$ssl_cert_path/$DOMAIN.crt.bk" "$ssl_cert_path/$DOMAIN.crt"
            [ -f "$ssl_cert_path/$DOMAIN.crt.key.bk" ] && mv "$ssl_cert_path/$DOMAIN.crt.key.bk" "$ssl_cert_path/$DOMAIN.crt.key"
        fi
    else
        echo "ERROR: All CA providers failed! Generating self-signed certificate..."
        [ -f "$ssl_cert_path/$DOMAIN.crt.bk" ] && mv "$ssl_cert_path/$DOMAIN.crt.bk" "$ssl_cert_path/$DOMAIN.crt"
        [ -f "$ssl_cert_path/$DOMAIN.crt.key.bk" ] && mv "$ssl_cert_path/$DOMAIN.crt.key.bk" "$ssl_cert_path/$DOMAIN.crt.key"
        bash generate_self_signed_cert.sh $DOMAIN
    fi

    # Secure permissions
    chmod 600 $ssl_cert_path/$DOMAIN.crt.key 2>/dev/null
    chmod 600 -R $ssl_cert_path 2>/dev/null
    
    # Cleanup
    echo "" >/opt/hiddify-manager/nginx/parts/acme.conf
    systemctl reload --now hiddify-nginx
    systemctl reload hiddify-haproxy
    
    echo "=========================================="
    echo "SSL certificate process completed for $DOMAIN"
    echo "=========================================="
}

function has_valid_cert() {
    certificate="/opt/hiddify-manager/ssl/$1.crt"
}

function get_self_signed_cert() {
    cd /opt/hiddify-manager/acme.sh/
    local d=$1
    if [ ${#d} -gt 64 ]; then
        echo "Domain length exceeds 64 characters. Truncating to the first 64 characters."
        d="${d:0:64}"
    fi
    mkdir -p /opt/hiddify-manager/ssl
    local certificate="/opt/hiddify-manager/ssl/$d.crt"
    local private_key="/opt/hiddify-manager/ssl/$d.crt.key"
    local current_date=$(date +%s)
    local generate_new_cert=0
    # Check if the certificate file exists
    if [ ! -f "$certificate" ]; then
        echo "Certificate $d ($certificate) file not found. Generating a new certificate."
        generate_new_cert=1
    else
        local expire_date=$(openssl x509 -enddate -noout -in "$certificate" | cut -d= -f2-)
        # Convert the expire date to seconds since epoch
        local expire_date_seconds=$(date -d "$expire_date" +%s)

        if [ "$current_date" -ge "$expire_date_seconds" ]; then
            echo "Certificate $d ($certificate) is expired. Generating a new certificate."
            generate_new_cert=1
        fi
    fi

    # Check if the private key file exists
    if [ ! -f "$private_key" ]; then
        echo "Private key file $d ($private_key) not found. Generating a new certificate."
        generate_new_cert=1
    else
        # Check if the private key is valid
        if ! openssl rsa -check -in "$private_key" >/dev/null && ! openssl ec -check -in "$private_key" >/dev/null; then
            echo "Private key $d ($private_key) is invalid. Generating a new certificate."
            generate_new_cert=1
        fi
    fi

    # Generate a new certificate if necessary
    if [ "$generate_new_cert" -eq 1 ]; then
        openssl req -x509 -newkey rsa:2048 -keyout "$private_key" -out "$certificate" -days 3650 -nodes -subj "/C=GB/ST=London/L=London/O=Google Trust Services LLC/CN=$d"
        echo "New certificate and private key generated."
    fi
    chmod 600 -R $private_key

}
