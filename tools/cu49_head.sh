# watashi: the certificate engine was rebuilt in v12.2.49
#
# what was wrong before:
#  - the CA ladder looked real but ZeroSSL, Buypass and Google can not issue
#    anything until an ACME account is registered with them, and nothing ever
#    registered one, so every provider after Let's Encrypt failed instantly
#  - acme.sh 3.x issues ec-256 by default and keeps it in <domain>_ecc, so the
#    old install step without --ecc could not find a certificate it had just
#    obtained, and the panel fell back to a self signed one
#  - --force on every attempt burned the Let's Encrypt duplicate limit
#  - a CDN domain could never get a real certificate at all
#  - a domain like "cert_utils.sh" could reach the issuer and create junk files

restricted_tlds=("af" "by" "cu" "er" "gn" "ir" "kp" "lr" "ru" "ss" "su" "sy" "zw" "amazonaws.com" "azurewebsites.net" "cloudapp.net")
shopt -s expand_aliases

source ./lib/acme.sh.env
source /opt/hiddify-manager/common/utils.sh

WS_ACME_HOME="${WS_ACME_HOME:-/opt/hiddify-manager/acme.sh}"
WS_SSL_DIR="${WS_SSL_DIR:-/opt/hiddify-manager/ssl}"
WS_ACME_LOG="${WS_ACME_LOG:-/opt/hiddify-manager/log/system/acme.log}"
WS_STATE_DIR="${WS_STATE_DIR:-$WS_ACME_HOME/lib/data/watashi}"
WS_RETRY_HOURS="${WS_RETRY_HOURS:-6}"
WS_KEYLENGTH="${WS_KEYLENGTH:-2048}"
# watashi: how patient we are with one CA, and how long we wait before the next
# one. the defaults are the production values; a test run can set them to 0.
WS_MAX_RETRIES="${WS_MAX_RETRIES:-2}"
WS_RETRY_DELAY="${WS_RETRY_DELAY:-10}"
WS_CA_GAP="${WS_CA_GAP:-5}"

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
# Format: "server_name|description"
CA_SERVERS=(
    "letsencrypt|Let's Encrypt"
    "zerossl|ZeroSSL"
    "buypass|Buypass"
    "google|Google Trust Services"
)

# watashi: a name we are willing to hand to a certificate authority
function ws_valid_domain() {
    local d="$1"
    [ -z "$d" ] && return 1
    [[ "$d" == *" "* ]] && return 1
    [[ "$d" == *"*"* ]] && return 1
    [[ "$d" == *".sh" ]] && return 1
    [[ "$d" != *.* ]] && return 1
    [[ "$d" =~ ^[A-Za-z0-9._-]+$ ]] || return 1
    return 0
}

function ws_root_domain() {
    echo "$1" | awk -F. '{ if (NF<=2) print $0; else print $(NF-1)"."$NF }'
}

# watashi: my@example.com is refused by several CAs, so we build a plausible one
function ws_acme_email() {
    local root
    root=$(ws_root_domain "$1")
    if [ -z "$root" ]; then
        echo ""
    else
        echo "ssl@$root"
    fi
}

# watashi: the cloudflare api token the admin already saved in the panel
function ws_cf_token() {
    local t
    t=$(hconfig cloudflare 2>/dev/null)
    echo "$t" | tr -d '[:space:]'
}

function ws_google_eab_file() {
    echo "$WS_ACME_HOME/google_eab.conf"
}

# watashi: no CA issues anything before an account exists. this is the whole
# reason the old ladder never reached its second step.
function ws_ca_account_ready() {
    local ca="$1"
    local email="$2"
    local marker="$WS_STATE_DIR/account-$ca"
    mkdir -p "$WS_STATE_DIR" 2>/dev/null
    if [ -f "$marker" ]; then
        return 0
    fi
    if [ -z "$email" ]; then
        echo "No usable account email for $ca, skipping..."
        return 1
    fi
    local eab_args=()
    if [ "$ca" = "google" ]; then
        local eabf
        eabf=$(ws_google_eab_file)
        if [ ! -s "$eabf" ]; then
            echo "Google Trust Services needs EAB credentials in $eabf, skipping..."
            return 1
        fi
        EAB_KID=""
        EAB_HMAC_KEY=""
        source "$eabf"
        if [ -z "$EAB_KID" ] || [ -z "$EAB_HMAC_KEY" ]; then
            echo "$eabf has no EAB_KID and EAB_HMAC_KEY, skipping Google..."
            return 1
        fi
        eab_args=(--eab-kid "$EAB_KID" --eab-hmac-key "$EAB_HMAC_KEY")
    fi
    echo "Registering an ACME account with $ca as $email..."
    if acme.sh --register-account --server "$ca" -m "$email" "${eab_args[@]}" --log "$WS_ACME_LOG" >/dev/null 2>&1; then
        date >"$marker"
        return 0
    fi
    echo "Could not register an account with $ca."
    return 1
}

function ws_http_challenge_prepare() {
    mkdir -p "$WS_ACME_HOME/www/.well-known/acme-challenge"
    echo "location /.well-known/acme-challenge {root $WS_ACME_HOME/www/;}" >/opt/hiddify-manager/nginx/parts/acme.conf
    systemctl reload hiddify-nginx 2>/dev/null || true
}

function ws_http_challenge_cleanup() {
    echo "" >/opt/hiddify-manager/nginx/parts/acme.conf
    systemctl reload hiddify-nginx 2>/dev/null || true
}

# watashi: apply_configs runs this script every time. without a cooldown a
# broken domain asks four CAs on every apply and gets the whole account rate
# limited. a deliberate request from the panel sets WS_SSL_FORCE=1 and skips it.
function ws_cooldown_active() {
    local marker="$WS_STATE_DIR/lasttry-$1"
    [ "$WS_SSL_FORCE" = "1" ] && return 1
    [ ! -f "$marker" ] && return 1
    local last now
    last=$(cat "$marker" 2>/dev/null)
    case "$last" in
    '' | *[!0-9]*) return 1 ;;
    esac
    now=$(date +%s)
    if [ $((now - last)) -lt $((WS_RETRY_HOURS * 3600)) ]; then
        return 0
    fi
    return 1
}

function ws_cooldown_mark() {
    mkdir -p "$WS_STATE_DIR" 2>/dev/null
    date +%s >"$WS_STATE_DIR/lasttry-$1"
}

function ws_cooldown_clear() {
    rm -f "$WS_STATE_DIR/lasttry-$1" 2>/dev/null
}

function try_get_cert_with_ca() {
    local DOMAIN=$1
    local CA_SERVER=$2
    local CA_DESC=$3
    local CHALLENGE=$4
    local MAX_RETRIES="${WS_MAX_RETRIES:-2}"
    local RETRY_DELAY="${WS_RETRY_DELAY:-10}"
    local i result

    echo "====== Trying $CA_DESC with the $CHALLENGE challenge for $DOMAIN ======"

    # Skip ZeroSSL for restricted domains
    if [[ "$CA_SERVER" == "zerossl" ]] && ! is_ok_domain_zerossl "$DOMAIN"; then
        echo "Domain $DOMAIN is restricted for ZeroSSL, skipping..."
        return 1
    fi

    if ! ws_ca_account_ready "$CA_SERVER" "$(ws_acme_email "$DOMAIN")"; then
        return 1
    fi

    local args=(--issue -d "$DOMAIN" --server "$CA_SERVER" --keylength "$WS_KEYLENGTH" --log "$WS_ACME_LOG")
    if [ "$CHALLENGE" = "cloudflare-dns" ]; then
        local token
        token=$(ws_cf_token)
        if [ -z "$token" ]; then
            echo "No Cloudflare token is saved in the panel, skipping the dns challenge..."
            return 1
        fi
        export CF_Token="$token"
        args+=(--dns dns_cf)
    else
        ws_http_challenge_prepare
        args+=(-w "$WS_ACME_HOME/www/")
    fi

    for ((i = 1; i <= MAX_RETRIES; i++)); do
        echo "Attempt $i of $MAX_RETRIES..."
        acme.sh "${args[@]}" 2>&1
        result=$?

        if [ $result -eq 0 ]; then
            echo "✓ Success with $CA_DESC!"
            return 0
        elif [ $result -eq 2 ]; then
            # Already issued, renew it with the same CA this time
            echo "Certificate already exists, attempting renewal with $CA_DESC..."
            if acme.sh --renew -d "$DOMAIN" --server "$CA_SERVER" --force --log "$WS_ACME_LOG" 2>&1; then
                return 0
            fi
            if acme.sh --renew -d "$DOMAIN" --server "$CA_SERVER" --force --ecc --log "$WS_ACME_LOG" 2>&1; then
                return 0
            fi
        fi

        if [ $i -lt $MAX_RETRIES ] && [ "$RETRY_DELAY" -gt 0 ] 2>/dev/null; then
            echo "Failed, waiting ${RETRY_DELAY}s before retry..."
            sleep "$RETRY_DELAY"
        fi
    done

    echo "✗ Failed with $CA_DESC after $MAX_RETRIES attempts"
    return 1
}

# watashi: acme.sh keeps an ec-256 certificate in <domain>_ecc, and the install
# step only looks there when it is given --ecc. we ask for rsa but still accept
# a store left behind by an older run.
function ws_install_cert() {
    local DOMAIN=$1
    local reload="systemctl reload hiddify-haproxy 2>/dev/null || true; systemctl reload hiddify-singbox 2>/dev/null || true"
    if acme.sh --install-cert -d "$DOMAIN" \
        --fullchainpath "$WS_SSL_DIR/$DOMAIN.crt" \
        --keypath "$WS_SSL_DIR/$DOMAIN.crt.key" \
        --reloadcmd "$reload"; then
        return 0
    fi
    echo "The rsa store did not have it, trying the ecc store..."
    acme.sh --install-cert -d "$DOMAIN" --ecc \
        --fullchainpath "$WS_SSL_DIR/$DOMAIN.crt" \
        --keypath "$WS_SSL_DIR/$DOMAIN.crt.key" \
        --reloadcmd "$reload"
}

function get_cert() {
    cd /opt/hiddify-manager/acme.sh/
    source ./lib/acme.sh.env

    DOMAIN=$1
    ssl_cert_path="$WS_SSL_DIR"
    local days_left=0

    echo "=========================================="
    echo "Getting SSL certificate for: $DOMAIN"
    echo "=========================================="

    # watashi: never hand a script name or a wildcard to a certificate authority
    if ! ws_valid_domain "$DOMAIN"; then
        echo "ERROR: '$DOMAIN' is not a domain name, nothing to do."
        return 1
    fi

    # Check if we already have a valid certificate (not expiring within 30 days)
    if [ -f "$ssl_cert_path/$DOMAIN.crt" ] && [ -f "$ssl_cert_path/$DOMAIN.crt.key" ]; then
        local issuer=$(openssl x509 -issuer -noout -in "$ssl_cert_path/$DOMAIN.crt" 2>/dev/null | sed 's/issuer=//')
        local subject=$(openssl x509 -subject -noout -in "$ssl_cert_path/$DOMAIN.crt" 2>/dev/null | sed 's/subject=//')
        local expire_date=$(openssl x509 -enddate -noout -in "$ssl_cert_path/$DOMAIN.crt" 2>/dev/null | cut -d= -f2-)

        if [ -n "$expire_date" ] && [ "$issuer" != "$subject" ]; then
            local expire_epoch=$(date -d "$expire_date" +%s 2>/dev/null)
            local now_epoch=$(date +%s)
            days_left=$(((expire_epoch - now_epoch) / 86400))

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

    # watashi: do not ask the same failing domain again on every apply_configs
    if ws_cooldown_active "$DOMAIN" && [ -f "$ssl_cert_path/$DOMAIN.crt" ]; then
        echo "The last attempt for $DOMAIN failed less than $WS_RETRY_HOURS hours ago, keeping the current certificate."
        echo "Use the button in the panel, or WS_SSL_FORCE=1, to try again right now."
        return 0
    fi

    local cf_token
    cf_token=$(ws_cf_token)

    # Verify DNS resolution
    DOMAIN_IP=$(dig +short -t a $DOMAIN. | head -1)
    DOMAIN_IPv6=$(dig +short -t aaaa $DOMAIN. | head -1)
    echo "DNS Resolution: $DOMAIN -> IPv4=$DOMAIN_IP, IPv6=$DOMAIN_IPv6"
    echo "Server IPs: IPv4=$SERVER_IP, IPv6=$SERVER_IPv6"

    if [[ -z "$DOMAIN_IP" && -z "$DOMAIN_IPv6" ]]; then
        # watashi: the dns challenge does not need the domain to point anywhere
        if [ -z "$cf_token" ]; then
            error "ERROR: Domain $DOMAIN does not resolve to any IP!"
            bash generate_self_signed_cert.sh $DOMAIN
            return 1
        fi
        echo "WARNING: $DOMAIN does not resolve yet, trying the Cloudflare dns challenge anyway."
    fi

    if [[ -n "$DOMAIN_IP$DOMAIN_IPv6" && "$SERVER_IP" != "$DOMAIN_IP" && "$SERVER_IPv6" != "$DOMAIN_IPv6" ]]; then
        echo "WARNING: Domain IP doesn't match server IP. The http challenge may fail."
    fi

    # Backup existing certificates
    if [ -f "$ssl_cert_path/$DOMAIN.crt" ]; then
        cp "$ssl_cert_path/$DOMAIN.crt" "$ssl_cert_path/$DOMAIN.crt.bk"
        cp "$ssl_cert_path/$DOMAIN.crt.key" "$ssl_cert_path/$DOMAIN.crt.key.bk"
    fi

    # watashi: cloudflare first when a token is saved, then the classic webroot
    local challenges=()
    if [ -n "$cf_token" ]; then
        challenges+=("cloudflare-dns")
    fi
    challenges+=("http")

    local cert_obtained=0
    local winner=""
    local challenge ca_info ca_server ca_desc
    for challenge in "${challenges[@]}"; do
        for ca_info in "${CA_SERVERS[@]}"; do
            IFS='|' read -r ca_server ca_desc <<<"$ca_info"

            if try_get_cert_with_ca "$DOMAIN" "$ca_server" "$ca_desc" "$challenge"; then
                cert_obtained=1
                winner="$ca_desc over $challenge"
                echo "Successfully obtained certificate from $ca_desc"
                break
            fi

            echo "Moving to next CA provider..."
            [ "${WS_CA_GAP:-5}" -gt 0 ] 2>/dev/null && sleep "${WS_CA_GAP:-5}"
        done
        [ $cert_obtained -eq 1 ] && break
        echo "Moving to the next challenge type..."
    done

    if [ $cert_obtained -eq 1 ]; then
        if ws_install_cert "$DOMAIN"; then
            echo "✓ Certificate installed successfully!"
            rm -f "$ssl_cert_path/$DOMAIN.crt.bk" "$ssl_cert_path/$DOMAIN.crt.key.bk"
            ws_cooldown_clear "$DOMAIN"
        else
            echo "ERROR: Failed to install certificate, restoring backup..."
            [ -f "$ssl_cert_path/$DOMAIN.crt.bk" ] && mv "$ssl_cert_path/$DOMAIN.crt.bk" "$ssl_cert_path/$DOMAIN.crt"
            [ -f "$ssl_cert_path/$DOMAIN.crt.key.bk" ] && mv "$ssl_cert_path/$DOMAIN.crt.key.bk" "$ssl_cert_path/$DOMAIN.crt.key"
            cert_obtained=0
            winner=""
        fi
    fi

    if [ $cert_obtained -eq 0 ]; then
        echo "ERROR: All CA providers failed! Generating self-signed certificate..."
        [ -f "$ssl_cert_path/$DOMAIN.crt.bk" ] && mv "$ssl_cert_path/$DOMAIN.crt.bk" "$ssl_cert_path/$DOMAIN.crt"
        [ -f "$ssl_cert_path/$DOMAIN.crt.key.bk" ] && mv "$ssl_cert_path/$DOMAIN.crt.key.bk" "$ssl_cert_path/$DOMAIN.crt.key"
        bash generate_self_signed_cert.sh $DOMAIN
        ws_cooldown_mark "$DOMAIN"
    fi

    # Secure permissions
    chmod 600 $ssl_cert_path/$DOMAIN.crt.key 2>/dev/null
    chmod 600 -R $ssl_cert_path 2>/dev/null

    # Cleanup
    ws_http_challenge_cleanup
    systemctl reload hiddify-haproxy 2>/dev/null || true

    echo "watashi: $DOMAIN got its certificate from ${winner:-a self signed fallback} (previous certificate had $days_left days left)"
    echo "=========================================="
    echo "SSL certificate process completed for $DOMAIN"
    echo "=========================================="
}

