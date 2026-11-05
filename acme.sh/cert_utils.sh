# watashi v12.3.40dev: the old project name was taken out of this file (names, paths and links only)
# watashi: the certificate engine was rebuilt in v12.2.49
#
# what was wrong before:
#  - the CA ladder looked real but ZeroSSL, Buypass and Google can not issue
#    anything until an ACME account is registered with them, and nothing ever
#    registered one, so every provider after Let's Encrypt failed instantly
#  - acme.sh 3.x issues ec-256 by default and keeps it in <domain>_ecc, so the
#    old "--installcert" without --ecc could not find a certificate it had just
#    obtained, and the panel fell back to a self signed one
#  - --force on every attempt burned the Let's Encrypt duplicate limit
#  - a CDN domain could never get a real certificate at all
#  - a domain like "cert_utils.sh" could reach the issuer and create junk files

restricted_tlds=("af" "by" "cu" "er" "gn" "ir" "kp" "lr" "ru" "ss" "su" "sy" "zw" "amazonaws.com" "azurewebsites.net" "cloudapp.net")
shopt -s expand_aliases

source ./lib/acme.sh.env
source /opt/watashi-manager/common/utils.sh

WS_ACME_HOME="${WS_ACME_HOME:-/opt/watashi-manager/acme.sh}"
WS_SSL_DIR="${WS_SSL_DIR:-/opt/watashi-manager/ssl}"
WS_ACME_LOG="${WS_ACME_LOG:-/opt/watashi-manager/log/system/acme.log}"
WS_STATE_DIR="${WS_STATE_DIR:-$WS_ACME_HOME/lib/data/watashi}"
WS_RETRY_HOURS="${WS_RETRY_HOURS:-6}"
# watashi v12.3.39dev: one number for "time to renew". A certificate is kept while it
# has at least this many days left and is asked for again below that, so a
# 90 day certificate is renewed on its 29th last day. The foreign check below
# uses the same number, so both sides agree on what "still good" means.
WS_RENEW_DAYS="${WS_RENEW_DAYS:-30}"
# watashi v12.3.39dev: the nginx part that opens the challenge path.
WS_CHALLENGE_CONF="${WS_CHALLENGE_CONF:-/opt/watashi-manager/nginx/parts/acme.conf}"
# watashi v12.2.130ax: this said 2048, so every certificate on every watashi server was
# RSA. An RSA 2048 signature costs the cpu ten to twenty times what an
# ecdsa P-256 signature costs, and haproxy signs once per tls handshake.
# On a busy box that is the whole cpu bill: a customer server showed four
# haproxy threads at 35% each, all of them inside RSA_private_encrypt,
# with one thread blocked 179 ms while 4647 streams waited behind it.
# ec-256 is what acme.sh issues by default and what every client already
# prefers. Set WS_KEYLENGTH=2048 in the environment to go back.
WS_KEYLENGTH="${WS_KEYLENGTH:-ec-256}"

# watashi v12.2.130ax: an ec key lives in the <domain>_ecc store, an rsa key does not.
# Everything that reaches into an acme.sh store has to say which one, so
# the answer is computed once here instead of being guessed at each call.
case "$WS_KEYLENGTH" in
    ec-*) WS_ACME_ECC=(--ecc) ;;
    *) WS_ACME_ECC=() ;;
esac

# watashi v12.2.130ax: true when the certificate on disk carries an RSA public key.
# Used by the one time migration in run.sh, and harmless anywhere else.
function ws_cert_is_rsa() {
    local crt="$1"
    [ -s "$crt" ] || return 1
    openssl x509 -in "$crt" -noout -text 2>/dev/null |
        grep -qE "Public Key Algorithm: rsaEncryption"
}

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
# watashi v12.3.40dev: Buypass is off the list. Its free ACME service (Buypass
# Go SSL) was shut down, so every try against it only failed and added to the
# time a domain without a certificate waits for the next authority.
CA_SERVERS=(
    "letsencrypt|Let's Encrypt"
    "zerossl|ZeroSSL"
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
    # watashi v12.3.39dev: run.sh asks for every domain at once, so on a fresh server
    # (a restore) every domain registered the same account at the same moment,
    # one shared key and nonce, and one of them lost and fell down the whole
    # ladder to a self signed certificate. One registration at a time; the
    # ones that waited find the marker and go on.
    local lockfd rc=1
    exec {lockfd}>"$WS_STATE_DIR/account.lock"
    flock -w 300 "$lockfd" 2>/dev/null
    if [ -f "$marker" ]; then
        exec {lockfd}>&-
        return 0
    fi
    echo "Registering an ACME account with $ca as $email..."
    if acme.sh --register-account --server "$ca" -m "$email" "${eab_args[@]}" --log "$WS_ACME_LOG" >/dev/null 2>&1; then
        date >"$marker"
        rc=0
    else
        echo "Could not register an account with $ca."
    fi
    exec {lockfd}>&-
    return $rc
}

# watashi v12.3.39dev: run.sh asks for every domain at the same time, and every one of
# those requests emptied acme.conf when it ended. The first domain to finish
# took the challenge path away from every domain still waiting for its
# authority, and those then failed on a 404 that had nothing to do with
# them: a second domain on the same server could lose its certificate to the
# first one. Each request that needs the path now leaves its pid in
# challenge-holders, and the path is only closed by the last one to leave.
# nginx is reloaded only when the file really changes.
function ws_http_challenge_prepare() {
    local me="${BASHPID:-$$}"
    local holders="$WS_STATE_DIR/challenge-holders"
    local want="location /.well-known/acme-challenge {root $WS_ACME_HOME/www/;}"
    mkdir -p "$WS_ACME_HOME/www/.well-known/acme-challenge" "$holders" 2>/dev/null
    (
        flock -w 60 9 || true
        echo "$me" >"$holders/$me"
        if [ "$(cat "$WS_CHALLENGE_CONF" 2>/dev/null)" != "$want" ]; then
            echo "$want" >"$WS_CHALLENGE_CONF"
            systemctl reload watashi-nginx 2>/dev/null || systemctl restart watashi-nginx 2>/dev/null || true
        fi
    ) 9>"$WS_STATE_DIR/challenge.lock"
}

# watashi v12.2.130h: asking a CA to fetch a file from us while no web server is
# running wastes minutes and eats the account quota. This fetches the file
# ourselves first; if we cannot read it, neither can the CA.
function ws_challenge_reachable() {
    # watashi v12.2.130j: the old probe asked 127.0.0.1 with no Host header, so it
    # landed on whatever default server nginx had and reported a failure for a
    # server that was serving the file perfectly well. The real name is used now,
    # locally and then over the public address.
    local domain="$1"
    # watashi v12.3.39dev: $$ is the same number in every request run.sh starts at once,
    # so one request deleted the probe file of another and called a healthy
    # port 80 dead, and then restarted nginx under everybody's feet.
    local probe="watashi-check-${BASHPID:-$$}-$RANDOM"
    local dir="$WS_ACME_HOME/www/.well-known/acme-challenge"
    local url="/.well-known/acme-challenge/$probe"
    mkdir -p "$dir" 2>/dev/null || true
    echo "watashi" >"$dir/$probe" 2>/dev/null || return 1
    local code=""
    if [ -n "$domain" ]; then
        code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 \
            -H "Host: $domain" "http://127.0.0.1$url" 2>/dev/null)
    fi
    if [ "$code" != "200" ] && [ -n "$domain" ]; then
        code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 \
            "http://$domain$url" 2>/dev/null)
    fi
    if [ "$code" != "200" ]; then
        code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 \
            "http://127.0.0.1$url" 2>/dev/null)
    fi
    rm -f "$dir/$probe" 2>/dev/null
    [ "$code" = "200" ]
}

# watashi v12.2.130j: what the next log needs in order to explain a dead port 80.
function ws_port80_report() {
    echo "  watashi-nginx: $(systemctl is-active watashi-nginx 2>/dev/null)"
    echo "  listening on 80: $(ss -ltnp 2>/dev/null | grep -c ':80 ')"
}

# watashi v12.3.39dev: leaves the challenge path open while any other request still
# holds it. A holder whose process is gone (killed, crashed) does not count.
function ws_http_challenge_cleanup() {
    local me="${BASHPID:-$$}"
    local holders="$WS_STATE_DIR/challenge-holders"
    mkdir -p "$holders" 2>/dev/null
    (
        flock -w 60 9 || true
        rm -f "$holders/$me" 2>/dev/null
        local f pid
        for f in "$holders"/*; do
            [ -e "$f" ] || continue
            pid=$(basename "$f")
            if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
                exit 0
            fi
            rm -f "$f" 2>/dev/null
        done
        if [ -n "$(tr -d '[:space:]' <"$WS_CHALLENGE_CONF" 2>/dev/null)" ]; then
            echo "" >"$WS_CHALLENGE_CONF"
            systemctl reload watashi-nginx 2>/dev/null || true
        fi
    ) 9>"$WS_STATE_DIR/challenge.lock"
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

# watashi v12.2.130j: acme.sh here is a shell alias from lib/acme.sh.env, not a
# program, so `timeout acme.sh ...` failed with "No such file or directory" and no
# request was ever sent. The alias is called normally and a watchdog keeps the
# time limit, so every --home of the alias stays untouched.
function ws_acme_run() {
    local limit="$1"
    shift
    local pid waited=0
    acme.sh "$@" 2>&1 &
    pid=$!
    while kill -0 "$pid" 2>/dev/null; do
        sleep 2
        waited=$((waited + 2))
        if [ "$limit" -gt 0 ] 2>/dev/null && [ "$waited" -ge "$limit" ]; then
            kill -TERM "$pid" 2>/dev/null
            sleep 2
            kill -KILL "$pid" 2>/dev/null
            wait "$pid" 2>/dev/null
            return 124
        fi
    done
    wait "$pid"
    return $?
}

function try_get_cert_with_ca() {
    local DOMAIN=$1
    local CA_SERVER=$2
    local CA_DESC=$3
    local CHALLENGE=$4
    # watashi v12.2.130h: two tries per authority, and each try is time limited.
    # The "1/30" counting in the log was acme.sh waiting for the authority to
    # finish; with no web server that wait ran to the end four times over.
    local MAX_RETRIES=${WS_ACME_TRIES:-2}
    local RETRY_DELAY=${WS_ACME_RETRY_DELAY:-8}
    local ATTEMPT_TIMEOUT=${WS_ACME_ATTEMPT_TIMEOUT:-90}
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
    # watashi v12.3.39dev: asked for by hand from the domain card. acme.sh keeps its own
    # idea of when a certificate is due, and without --force it answers "not
    # yet" for a certificate this server may not even be serving.
    if [ "${WS_SSL_REISSUE:-0}" = "1" ]; then
        args+=(--force)
    fi
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
        # watashi v12.2.130j: a warning, never a refusal. A panel without a certificate
        # cannot be used at all, so a failed probe must not be what stops the request.
        if ! ws_challenge_reachable "$DOMAIN"; then
            echo "The challenge file could not be read over port 80 yet, restarting the web server..."
            systemctl restart watashi-nginx 2>/dev/null || true
            sleep 3
            if ! ws_challenge_reachable "$DOMAIN"; then
                echo "WARNING: the challenge file still cannot be read here."
                ws_port80_report
                echo "Asking $CA_DESC anyway, in case only this local check is wrong."
            fi
        fi
        args+=(-w "$WS_ACME_HOME/www/")
    fi

    for ((i = 1; i <= MAX_RETRIES; i++)); do
        echo "Attempt $i of $MAX_RETRIES..."
        ws_acme_run "$ATTEMPT_TIMEOUT" "${args[@]}"
        result=$?
        if [ $result -eq 124 ]; then
            echo "The authority did not answer within ${ATTEMPT_TIMEOUT}s, giving up on this attempt"
        fi

        if [ $result -eq 0 ]; then
            echo "✓ Success with $CA_DESC!"
            return 0
        elif [ $result -eq 2 ]; then
            # watashi v12.3.39dev: "not due yet" means the store already holds a certificate
            # that is still good, while ssl/ does not have it (the folder was
            # emptied, or an install step failed). That one is installed as it
            # is, instead of spending one of the five duplicates a week the
            # authority allows on a copy of it.
            if ws_store_cert_good "$DOMAIN"; then
                echo "The acme.sh store already holds a good certificate for $DOMAIN, installing that one."
                return 0
            fi
            # Already issued, renew it with the same CA this time
            echo "Certificate already exists, attempting renewal with $CA_DESC..."
            # watashi v12.2.130ax: the store that matches WS_KEYLENGTH is tried first now.
            # With an ec key the plain store is empty, so the old order spent a
            # whole attempt, and one authority round trip, on a store that could
            # not hold the certificate.
            if ws_acme_run "$ATTEMPT_TIMEOUT" --renew -d "$DOMAIN" --server "$CA_SERVER" --force "${WS_ACME_ECC[@]}" --log "$WS_ACME_LOG"; then
                return 0
            fi
            if [ ${#WS_ACME_ECC[@]} -eq 0 ]; then
                ws_acme_run "$ATTEMPT_TIMEOUT" --renew -d "$DOMAIN" --server "$CA_SERVER" --force --ecc --log "$WS_ACME_LOG" && return 0
            else
                ws_acme_run "$ATTEMPT_TIMEOUT" --renew -d "$DOMAIN" --server "$CA_SERVER" --force --log "$WS_ACME_LOG" && return 0
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

# watashi: acme.sh keeps an ec-256 certificate in <domain>_ecc and an rsa one
# in <domain>, and --install-cert only looks in the ecc store when it is given
# --ecc.
# watashi v12.2.130ax: the store we are issuing into is asked first, and the other one
# is still accepted so a server that has been issuing rsa for months keeps
# working on the very first run after the update, before the migration has
# had a chance to reissue anything.
function ws_install_cert() {
    local DOMAIN=$1
    local reload="systemctl reload watashi-haproxy 2>/dev/null || true; systemctl reload watashi-singbox 2>/dev/null || true"
    if acme.sh --install-cert -d "$DOMAIN" "${WS_ACME_ECC[@]}" \
        --fullchainpath "$WS_SSL_DIR/$DOMAIN.crt" \
        --keypath "$WS_SSL_DIR/$DOMAIN.crt.key" \
        --reloadcmd "$reload"; then
        return 0
    fi
    echo "That store did not have it, trying the other one..."
    local other=(--ecc)
    [ ${#WS_ACME_ECC[@]} -eq 0 ] || other=()
    acme.sh --install-cert -d "$DOMAIN" "${other[@]}" \
        --fullchainpath "$WS_SSL_DIR/$DOMAIN.crt" \
        --keypath "$WS_SSL_DIR/$DOMAIN.crt.key" \
        --reloadcmd "$reload"
}

# watashi v12.2.130bk: hostnames handed out by a cdn, where the provider
# terminates tls with its own certificate and owns the dns zone. Both acme
# challenges are impossible on these names: http-01 would have to be served
# by the cdn, and dns-01 would need a record in a zone we will never hold.
# sacred3636.global.ssl.fastly.net is the example that started this: it
# already serves a GlobalSign certificate for *.global.ssl.fastly.net, and
# port 80 on it answers 400.
ws_cdn_tls_suffixes=(
    "global.ssl.fastly.net"
    "freetls.fastly.net"
    "fastly.net"
    "cloudfront.net"
    "workers.dev"
    "pages.dev"
    "b-cdn.net"
    "azureedge.net"
    "akamaized.net"
    "cdn77.org"
    "gcdn.co"
)

function ws_cdn_shared_host() {
    local d
    d=$(echo "$1" | tr 'A-Z' 'a-z')
    local s
    for s in "${ws_cdn_tls_suffixes[@]}"; do
        [[ "$d" == *".$s" ]] && return 0
        [ "$d" = "$s" ] && return 0
    done
    return 1
}

# watashi v12.3.39dev: small facts about a certificate file, used by every decision
# below instead of each place guessing on its own.
#
# "from an authority": the issuer is not the certificate itself and it has
# not expired. The chain is deliberately not verified against the local CA
# bundle: an old server with an old bundle would call a perfectly good
# certificate untrusted and ask for a new one every single day.
function ws_cert_real() {
    local crt="$1" issuer subject
    [ -s "$crt" ] || return 1
    issuer=$(openssl x509 -issuer -noout -in "$crt" 2>/dev/null | sed 's/issuer=//')
    subject=$(openssl x509 -subject -noout -in "$crt" 2>/dev/null | sed 's/subject=//')
    [ -n "$issuer" ] && [ "$issuer" != "$subject" ] || return 1
    openssl x509 -checkend 0 -noout -in "$crt" >/dev/null 2>&1
}

# the certificate is written for this name (or a wildcard that covers it)
function ws_cert_covers() {
    openssl x509 -in "$1" -noout -checkhost "$2" 2>/dev/null | grep -q "does match"
}

# the key file belongs to the certificate. haproxy refuses to start with a
# pair that does not match, and with it every bind of the server goes down.
function ws_cert_key_match() {
    local a b
    a=$(openssl x509 -in "$1" -noout -pubkey 2>/dev/null)
    b=$(openssl pkey -in "$2" -pubout 2>/dev/null)
    [ -n "$a" ] && [ "$a" = "$b" ]
}

# whole days left, negative once expired, empty when the file is unreadable
function ws_cert_days() {
    local end e
    end=$(openssl x509 -enddate -noout -in "$1" 2>/dev/null | cut -d= -f2-)
    [ -n "$end" ] || return 1
    e=$(date -d "$end" +%s 2>/dev/null) || return 1
    echo $(((e - $(date +%s)) / 86400))
}

# the store acme.sh would install from holds a certificate that needs nothing
function ws_store_cert_good() {
    local d="$1" dir days
    [ "${WS_CERT_REKEY:-0}" = "1" ] && return 1
    if [ ${#WS_ACME_ECC[@]} -gt 0 ]; then
        dir="$WS_ACME_HOME/lib/certs/${d}_ecc"
    else
        dir="$WS_ACME_HOME/lib/certs/$d"
    fi
    [ -s "$dir/fullchain.cer" ] && [ -s "$dir/$d.key" ] || return 1
    ws_cert_real "$dir/fullchain.cer" || return 1
    ws_cert_covers "$dir/fullchain.cer" "$d" || return 1
    ws_cert_key_match "$dir/fullchain.cer" "$dir/$d.key" || return 1
    days=$(ws_cert_days "$dir/fullchain.cer")
    [ -n "$days" ] && [ "$days" -ge "$WS_RENEW_DAYS" ] 2>/dev/null
}

# watashi v12.3.39dev: the line a program reads back. The domain card reads it to tell
# the admin how the request ended: ok, kept, failed, busy, foreign, cdn,
# cooldown, nodns, toolong or invalid, with an optional reason after it.
function ws_cert_result() {
    WS_CERT_RESULT="$2"
    echo "watashi-cert: $1 $2${3:+ $3}"
}

# watashi v12.3.39dev: SERVER_IP and SERVER_IPv6 come from install.sh and from nowhere
# else. The daily timer (run.sh) and the panel (get_cert.sh) start without
# them, so ws_points_here compared every dns answer with an empty string and
# every domain of the server looked foreign. That is how a server restored
# from a backup, whose domains still pointed at the old machine for a while,
# kept its self signed certificates after the records were fixed: nothing
# outside install.sh could see that the domain pointed here now.
#
# This collects every address the server answers on: what install.sh
# exported, every global address of an interface, and the public address
# as the outside sees it (behind a nat that one is on no interface). The
# public lookup asks an outside service, so it is kept for six hours, and
# for ten minutes when it found nothing.
function ws_server_addrs() {
    if [ -n "${WS_SERVER_ADDRS:-}" ]; then
        echo "$WS_SERVER_ADDRS"
        return 0
    fi
    local list cache="$WS_STATE_DIR/public-ips" age ttl
    list="${SERVER_IP:-} ${SERVER_IPv6:-}"
    if command -v ip >/dev/null 2>&1; then
        list="$list $(ip -o addr show scope global 2>/dev/null | awk '{sub(/\/.*/, "", $4); print $4}' | tr '\n' ' ')"
    fi
    mkdir -p "$WS_STATE_DIR" 2>/dev/null
    ttl="${WS_PUBLIC_IP_TTL:-21600}"
    [ -s "$cache" ] || ttl=600
    age=$(($(date +%s) - $(stat -c %Y "$cache" 2>/dev/null || echo 0)))
    if [ ! -f "$cache" ] || [ "$age" -ge "$ttl" ]; then
        # a subshell: both helpers in utils.sh leave $ip and $services behind
        (get_public_ip; get_public_ipv6) 2>/dev/null >"$cache.new"
        mv -f "$cache.new" "$cache" 2>/dev/null
    fi
    list="$list $(tr '\n' ' ' <"$cache" 2>/dev/null)"
    WS_SERVER_ADDRS=$(echo "$list" | tr ' ' '\n' | tr 'A-Z' 'a-z' | grep -E '^[0-9a-f.:]+$' | grep -E '[.:]' | sort -u | tr '\n' ' ')
    export WS_SERVER_ADDRS
    echo "$WS_SERVER_ADDRS"
}

# every A and AAAA answer of the name, one per line, cname lines dropped
function ws_domain_addrs() {
    { dig +short -t a "$1." 2>/dev/null; dig +short -t aaaa "$1." 2>/dev/null; } |
        tr 'A-Z' 'a-z' | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$|^[0-9a-f]*:[0-9a-f:.]*$' | sort -u
}

# watashi v12.2.130bk: true when the name resolves to this very server, which
# is the only case where we are the one who answers the tls handshake.
# watashi v12.3.39dev: every answer counts now, against every address of this server.
# The old test read the last line of each answer only, so a cname, or a
# second record, decided alone.
function ws_points_here() {
    local d="$1" mine ip
    mine=" $(ws_server_addrs) "
    for ip in $(ws_domain_addrs "$d"); do
        [[ "$mine" == *" $ip "* ]] && return 0
    done
    return 1
}

# watashi v12.3.39dev: the certificate the name answers with out there is the very one
# in ssl/. Then it is this server answering, reached through a relay, or on
# an address no lookup above could see (a floating ip), and never foreign.
function ws_served_is_ours() {
    local d="$1" crt="$WS_SSL_DIR/$1.crt" here there
    [ -s "$crt" ] || return 1
    here=$(openssl x509 -in "$crt" -noout -fingerprint -sha256 2>/dev/null)
    there=$(echo | timeout 10 openssl s_client -servername "$d" -connect "$d:443" 2>/dev/null |
        openssl x509 -noout -fingerprint -sha256 2>/dev/null)
    [ -n "$here" ] && [ "$here" = "$there" ]
}

# watashi v12.2.130bk: days left on the certificate the remote endpoint really
# serves, and only when a normal client would trust it. curl verifies the
# chain and the hostname, so a self signed answer fails here as it should.
function ws_trusted_tls_days() {
    local d="$1" end e n
    curl -s -o /dev/null --max-time "${WS_TLS_PROBE_TIMEOUT:-6}" "https://$d/" || return 1
    # watashi v12.3.39dev: time limited, a host that answers curl can still stall here
    end=$(echo | timeout 10 openssl s_client -servername "$d" -connect "$d:443" 2>/dev/null |
        openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2-)
    [ -n "$end" ] || return 1
    e=$(date -d "$end" +%s 2>/dev/null)
    [ -n "$e" ] || return 1
    n=$(date +%s)
    echo $(((e - n) / 86400))
}

# watashi v12.2.130bk: one line of log, and at most one probe a day per name.
# A known cdn hostname is answered from the suffix list with no network at
# all. Anything that points at this server is ours and is never skipped.
function ws_foreign_tls() {
    local d="$1" cache verdict age days
    [ "${WS_SKIP_FOREIGN_TLS:-1}" = "1" ] || return 1
    if ws_cdn_shared_host "$d"; then
        echo "watashi: $d is a shared cdn hostname, the provider owns its certificate, not asking an authority"
        ws_cert_result "$d" cdn
        return 0
    fi
    # watashi v12.3.39dev: the button on the domain card means "ask now", whatever an
    # earlier probe concluded.
    [ "${WS_SSL_REISSUE:-0}" = "1" ] && return 1
    mkdir -p "$WS_STATE_DIR" 2>/dev/null
    cache="$WS_STATE_DIR/foreigntls-$d"
    if ws_points_here "$d"; then
        rm -f "$cache" 2>/dev/null
        return 1
    fi
    # watashi v12.3.39dev: a "yes" was kept for a whole day, and the timer runs once a
    # day, so a record fixed in the morning could wait two days. Saving the
    # domain in the panel (WS_SSL_FORCE) always probes again now, and a kept
    # answer lasts six hours.
    if [ "${WS_SSL_FORCE:-0}" != "1" ] && [ -f "$cache" ]; then
        age=$(($(date +%s) - $(stat -c %Y "$cache" 2>/dev/null || echo 0)))
        if [ "$age" -lt "${WS_FOREIGN_TLS_TTL:-21600}" ]; then
            verdict=$(cat "$cache" 2>/dev/null)
            [ "$verdict" = "yes" ] || return 1
            echo "watashi: $d is served elsewhere with a trusted certificate, not asking an authority"
            ws_cert_result "$d" foreign
            return 0
        fi
    fi
    days=$(ws_trusted_tls_days "$d")
    if [ -n "$days" ] && [ "$days" -ge "$WS_RENEW_DAYS" ] 2>/dev/null; then
        if ws_served_is_ours "$d"; then
            echo no >"$cache"
            return 1
        fi
        echo yes >"$cache"
        echo "watashi: $d is served elsewhere ($(ws_domain_addrs "$d" | xargs)) with a trusted certificate, $days days left, not asking an authority"
        ws_cert_result "$d" foreign
        return 0
    fi
    echo no >"$cache"
    return 1
}

# watashi v12.3.39dev: one request per domain at a time. The daily timer, a save in the
# panel and the button on the domain card can all reach the same domain at
# once, and two acme.sh runs on one domain fight over its store and its
# challenge files. A deliberate request (WS_SSL_FORCE, or the button) waits
# for the one already running; a scheduled one leaves the domain to it.
function get_cert() {
    local d="$1" fd="" rc
    ws_server_addrs >/dev/null
    if ws_valid_domain "$d"; then
        mkdir -p "$WS_STATE_DIR/locks" 2>/dev/null
        if exec {fd}>"$WS_STATE_DIR/locks/$d.lock"; then
            if ! flock -n "$fd"; then
                if [ "${WS_SSL_FORCE:-0}" = "1" ] || [ "${WS_SSL_REISSUE:-0}" = "1" ]; then
                    echo "Another certificate request for $d is running, waiting for it to finish..."
                    if ! flock -w "${WS_LOCK_WAIT:-1800}" "$fd"; then
                        echo "The other request for $d is still running, giving up."
                        ws_cert_result "$d" busy
                        exec {fd}>&-
                        return 3
                    fi
                else
                    echo "watashi: another certificate request for $d is running, leaving $d to it"
                    ws_cert_result "$d" busy
                    exec {fd}>&-
                    return 0
                fi
            fi
        else
            fd=""
        fi
    fi
    ws_get_cert_now "$@"
    rc=$?
    [ -n "$fd" ] && exec {fd}>&-
    return $rc
}

# watashi v12.3.39dev: what an authority would see. The challenge path is asked for
# over the public name only, never through 127.0.0.1, so the answer comes
# from whatever machine the domain points at.
function ws_challenge_public() {
    local domain="$1" code
    local probe="watashi-check-${BASHPID:-$$}-$RANDOM"
    local dir="$WS_ACME_HOME/www/.well-known/acme-challenge"
    mkdir -p "$dir" 2>/dev/null || true
    echo "watashi" >"$dir/$probe" 2>/dev/null || return 1
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 \
        "http://$domain/.well-known/acme-challenge/$probe" 2>/dev/null)
    rm -f "$dir/$probe" 2>/dev/null
    [ "$code" = "200" ]
}

function ws_get_cert_now() {
    cd /opt/watashi-manager/acme.sh/
    source ./lib/acme.sh.env

    DOMAIN=$1
    ssl_cert_path="$WS_SSL_DIR"
    local days_left=0
    local crt="$ssl_cert_path/$DOMAIN.crt"
    local key="$ssl_cert_path/$DOMAIN.crt.key"
    # watashi v12.3.39dev: read back by get_cert.sh once this returns
    WS_CERT_WAS_REAL=0
    WS_CERT_RESULT=""

    # watashi v12.2.130bk: a name whose tls belongs to someone else is skipped
    # here, before the banner and before the ladder, so the install log gets
    # one line instead of four authorities timing out twice each. The local
    # self signed file is still kept, because haproxy loads a file per
    # domain and would not start without one.
    if ws_valid_domain "$DOMAIN" && ws_foreign_tls "$DOMAIN"; then
        get_self_signed_cert "$DOMAIN" >/dev/null
        return 0
    fi

    echo "=========================================="
    echo "Getting SSL certificate for: $DOMAIN"
    if [ "${WS_SSL_REISSUE:-0}" = "1" ]; then
        echo "Asked for by hand: a new certificate is requested even if the current one is still valid."
    fi
    echo "=========================================="

    # watashi: never hand a script name or a wildcard to a certificate authority
    if ! ws_valid_domain "$DOMAIN"; then
        echo "ERROR: '$DOMAIN' is not a domain name, nothing to do."
        ws_cert_result "$DOMAIN" invalid
        return 1
    fi

    # Check if we already have a valid certificate (not expiring within WS_RENEW_DAYS days)
    # watashi v12.3.39dev: kept only while it comes from an authority, has not expired,
    # is written for this name and its key file belongs to it. Only the first
    # of those was ever tested: a pair that does not match takes haproxy down,
    # and a certificate for another name is refused by every client, and both
    # were kept here as "valid".
    if [ -f "$crt" ] && [ -f "$key" ]; then
        local why=""
        if ! ws_cert_real "$crt"; then
            why="self-signed or expired"
        elif ! ws_cert_covers "$crt" "$DOMAIN"; then
            why="written for another name"
        elif ! ws_cert_key_match "$crt" "$key"; then
            why="not the pair of its key file"
        fi
        if [ -z "$why" ]; then
            WS_CERT_WAS_REAL=1
            days_left=$(ws_cert_days "$crt")
            days_left=${days_left:-0}

            # Skip only if cert is from a real CA (validity < 400 days) and still valid
            # watashi v12.2.130ax: WS_CERT_REKEY=1 says the key itself is wrong, not the
            # expiry date, so a certificate that is still valid for months has
            # to be asked for again anyway. Only the one time rsa to ec
            # migration sets it.
            # watashi v12.3.39dev: WS_SSL_REISSUE=1 is the button on the domain card. It is
            # there for the case this test cannot see: a certificate that looks
            # fine on disk while the clients still cannot use the domain. The
            # renewal starts below WS_RENEW_DAYS (30) now, so on the 29th day.
            if [ "$days_left" -ge "$WS_RENEW_DAYS" ] && [ "$days_left" -lt 400 ] &&
                [ "${WS_CERT_REKEY:-0}" != "1" ] && [ "${WS_SSL_REISSUE:-0}" != "1" ]; then
                echo "✓ Existing certificate is valid for $days_left more days, skipping renewal."
                ws_cert_result "$DOMAIN" kept "$days_left"
                return 0
            elif [ "${WS_SSL_REISSUE:-0}" = "1" ] || [ "${WS_CERT_REKEY:-0}" = "1" ]; then
                echo "The current certificate still has $days_left days, it is replaced anyway."
            elif [ "$days_left" -lt "$WS_RENEW_DAYS" ]; then
                echo "Certificate expires in $days_left days, attempting renewal..."
            else
                echo "The certificate on disk claims $days_left more days than any authority issues, asking for a real one."
            fi
        else
            echo "The certificate on disk is $why, asking an authority for a real one."
        fi
    else
        echo "There is no certificate for $DOMAIN yet, asking for one now."
    fi

    # Check domain length (Let's Encrypt limit is 64 chars)
    if [ ${#DOMAIN} -gt 64 ]; then
        echo "ERROR: Domain name too long (${#DOMAIN} > 64 chars)"
        bash generate_self_signed_cert.sh $DOMAIN
        ws_cert_result "$DOMAIN" toolong
        return 1
    fi

    # watashi: do not ask the same failing domain again on every apply_configs
    if ws_cooldown_active "$DOMAIN" && [ -f "$crt" ]; then
        echo "The last attempt for $DOMAIN failed less than $WS_RETRY_HOURS hours ago, keeping the current certificate."
        echo "Use the button in the panel, or WS_SSL_FORCE=1, to try again right now."
        ws_cert_result "$DOMAIN" cooldown
        return 0
    fi

    local cf_token
    cf_token=$(ws_cf_token)

    # Verify DNS resolution
    # watashi v12.3.39dev: every record of the domain and every address of this server,
    # where the old lines showed one of each and called them "the" address.
    local found dns_note="" skip_http=0
    found=$(ws_domain_addrs "$DOMAIN" | xargs)
    echo "DNS Resolution: $DOMAIN -> ${found:-nothing}"
    echo "Server IPs: $(ws_server_addrs | xargs)"

    if [ -z "$found" ]; then
        # watashi: the dns challenge does not need the domain to point anywhere
        if [ -z "$cf_token" ]; then
            error "ERROR: Domain $DOMAIN does not resolve to any IP!"
            bash generate_self_signed_cert.sh $DOMAIN
            ws_cert_result "$DOMAIN" nodns
            return 1
        fi
        echo "WARNING: $DOMAIN does not resolve yet, trying the Cloudflare dns challenge anyway."
        dns_note="dns-none"
        skip_http=1
    elif ! ws_points_here "$DOMAIN"; then
        echo "WARNING: none of these addresses belongs to this server."
        dns_note="dns-elsewhere"
        # watashi v12.3.39dev: a relay passes port 80 on to this server, and then the
        # authority can still read the challenge. When the machine at that
        # address does not hand out our files (a server restored from a
        # backup while the records still point at the old one), every
        # authority would fail the same way, one after the other, minutes
        # each, and spend the failed validation quota of the account too.
        ws_http_challenge_prepare
        if ws_challenge_public "$DOMAIN"; then
            echo "The machine at that address passes the challenge path on to this server, so the http challenge can work."
        else
            echo "The machine at that address does not serve the challenge files of this server, so no authority can check the domain over http."
            echo "Point the domain at this server (or let the relay pass port 80 on), then ask again."
            skip_http=1
        fi
    else
        local stray="" one mine
        mine=" $(ws_server_addrs) "
        for one in $found; do
            [[ "$mine" == *" $one "* ]] || stray="$stray $one"
        done
        if [ -n "$stray" ]; then
            echo "WARNING: these addresses of $DOMAIN are not on this server:$stray. An authority that picks one of them fails the http challenge."
            dns_note="dns-mixed"
        fi
    fi

    # watashi v12.2.130: these copies used to be written inside ssl/ as .crt.bk and
    # .crt.key.bk. haproxy loads every file it finds in that folder, so a left
    # over copy became a certificate with no private key and took every bind
    # down at once. The copies live outside the folder haproxy reads now.
    ws_ssl_bk="/opt/watashi-manager/log/ssl-backup"
    mkdir -p "$ws_ssl_bk" 2>/dev/null || true
    # any copy left in ssl/ by an older build goes to the same place
    for stray in "$ssl_cert_path"/*.bk "$ssl_cert_path"/*.bk.key "$ssl_cert_path"/*.crt.bk.key; do
        [ -e "$stray" ] && mv -f "$stray" "$ws_ssl_bk/" 2>/dev/null || true
    done
    if [ -f "$ssl_cert_path/$DOMAIN.crt" ]; then
        cp "$ssl_cert_path/$DOMAIN.crt" "$ws_ssl_bk/$DOMAIN.crt.bk"
        cp "$ssl_cert_path/$DOMAIN.crt.key" "$ws_ssl_bk/$DOMAIN.crt.key.bk"
    fi

    # watashi: cloudflare first when a token is saved, then the classic webroot
    local challenges=()
    if [ -n "$cf_token" ]; then
        challenges+=("cloudflare-dns")
    fi
    # watashi v12.3.39dev: left out when nobody out there can hand our files to the authority
    if [ "$skip_http" != "1" ]; then
        challenges+=("http")
    fi

    local cert_obtained=0
    local winner=""
    # watashi v12.3.39dev: counts the requests really sent; with none (no challenge
    # could work) there is no limit to protect, so no cooldown either.
    local asked=0
    local challenge ca_info ca_server ca_desc
    for challenge in "${challenges[@]}"; do
        for ca_info in "${CA_SERVERS[@]}"; do
            IFS='|' read -r ca_server ca_desc <<<"$ca_info"

            asked=$((asked + 1))
            if try_get_cert_with_ca "$DOMAIN" "$ca_server" "$ca_desc" "$challenge"; then
                cert_obtained=1
                winner="$ca_desc over $challenge"
                echo "Successfully obtained certificate from $ca_desc"
                break
            fi

            echo "Moving to next CA provider..."
            sleep 5
        done
        [ $cert_obtained -eq 1 ] && break
        echo "Moving to the next challenge type..."
    done

    if [ $cert_obtained -eq 1 ]; then
        # watashi v12.3.39dev: checked before it counts. A pair that does not match would
        # take haproxy down, so it is put back exactly like a failed install.
        if ws_install_cert "$DOMAIN" && ws_cert_key_match "$crt" "$key" && ws_cert_covers "$crt" "$DOMAIN"; then
            echo "✓ Certificate installed successfully!"
            rm -f "$ws_ssl_bk/$DOMAIN.crt.bk" "$ws_ssl_bk/$DOMAIN.crt.key.bk"
            ws_cooldown_clear "$DOMAIN"
            rm -f "$WS_STATE_DIR/foreigntls-$DOMAIN" 2>/dev/null
        else
            echo "ERROR: Failed to install certificate, restoring backup..."
            [ -f "$ws_ssl_bk/$DOMAIN.crt.bk" ] && mv "$ws_ssl_bk/$DOMAIN.crt.bk" "$ssl_cert_path/$DOMAIN.crt"
            [ -f "$ws_ssl_bk/$DOMAIN.crt.key.bk" ] && mv "$ws_ssl_bk/$DOMAIN.crt.key.bk" "$ssl_cert_path/$DOMAIN.crt.key"
            cert_obtained=0
            winner=""
            dns_note="install"
        fi
    fi

    if [ $cert_obtained -eq 0 ]; then
        # watashi v12.3.39dev: with nothing sent, "all failed" pointed at the wrong culprit
        if [ "$asked" -gt 0 ]; then
            echo "ERROR: All CA providers failed! Generating self-signed certificate..."
        else
            echo "ERROR: no authority could be asked (see above), the domain keeps its current or a self-signed certificate."
        fi
        [ -f "$ws_ssl_bk/$DOMAIN.crt.bk" ] && mv "$ws_ssl_bk/$DOMAIN.crt.bk" "$ssl_cert_path/$DOMAIN.crt"
        [ -f "$ws_ssl_bk/$DOMAIN.crt.key.bk" ] && mv "$ws_ssl_bk/$DOMAIN.crt.key.bk" "$ssl_cert_path/$DOMAIN.crt.key"
        bash generate_self_signed_cert.sh $DOMAIN
        # watashi v12.3.39dev: the cooldown is kept for the times an authority was asked.
        # A request that was never sent must not hold the next run back for
        # hours once the records are fixed.
        if [ "$asked" -gt 0 ]; then
            ws_cooldown_mark "$DOMAIN"
        else
            echo "No authority was asked, so the next run tries again without waiting."
        fi
    fi

    # Secure permissions
    chmod 600 $ssl_cert_path/$DOMAIN.crt.key 2>/dev/null
    chmod 600 -R $ssl_cert_path 2>/dev/null

    # Cleanup
    ws_http_challenge_cleanup
    systemctl reload watashi-haproxy 2>/dev/null || true

    echo "watashi: $DOMAIN got its certificate from ${winner:-a self signed fallback} (previous certificate had $days_left days left)"
    if [ $cert_obtained -eq 1 ]; then
        ws_cert_result "$DOMAIN" ok "$(ws_cert_days "$crt")"
    else
        # dns-elsewhere, dns-none, dns-mixed, install, or ca when nothing else explains it
        case "$dns_note" in
        dns-mixed | '') dns_note="ca" ;;
        esac
        ws_cert_result "$DOMAIN" failed "$dns_note"
    fi
    echo "=========================================="
    echo "SSL certificate process completed for $DOMAIN"
    echo "=========================================="
    # watashi v12.3.39dev: a failure says so now. run.sh ignores it, its rsa migration
    # was already written to expect it, and the panel job reads it.
    [ $cert_obtained -eq 1 ]
}

function get_self_signed_cert() {
    cd /opt/watashi-manager/acme.sh/
    local d=$1
    # watashi v12.2.49: replace_variables.sh and old callers can pass junk
    if ! ws_valid_domain "$d"; then
        echo "'$d' is not a domain name, no self signed certificate for it."
        return 1
    fi
    if [ ${#d} -gt 64 ]; then
        echo "Domain length exceeds 64 characters. Truncating to the first 64 characters."
        d="${d:0:64}"
    fi
    mkdir -p /opt/watashi-manager/ssl
    local certificate="/opt/watashi-manager/ssl/$d.crt"
    local private_key="/opt/watashi-manager/ssl/$d.crt.key"
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
        if ! openssl rsa -check -in "$private_key" >/dev/null 2>&1 && ! openssl ec -check -in "$private_key" >/dev/null 2>&1; then
            echo "Private key $d ($private_key) is invalid. Generating a new certificate."
            generate_new_cert=1
        # watashi v12.3.39dev: a valid key that belongs to another certificate is just as
        # fatal: haproxy reads the pair together and refuses to start on it.
        elif [ -f "$certificate" ] && ! ws_cert_key_match "$certificate" "$private_key"; then
            echo "Private key $d ($private_key) does not belong to its certificate. Generating a new certificate."
            generate_new_cert=1
        fi
    fi

    # Generate a new certificate if necessary
    if [ "$generate_new_cert" -eq 1 ]; then
        # watashi v12.2.130ax: a fake certificate is handed to the same haproxy that signs
        # every handshake, so it pays the same RSA bill as a real one. ec-256
        # here too. rsa:2048 stays as the fallback for an openssl too old to
        # know prime256v1, which no supported release is.
        if ! openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
            -keyout "$private_key" -out "$certificate" -days 3650 -nodes \
            -subj "/C=GB/ST=London/L=London/O=Google Trust Services LLC/CN=$d" 2>/dev/null; then
            echo "This openssl cannot make an ec key, falling back to rsa:2048."
            openssl req -x509 -newkey rsa:2048 -keyout "$private_key" -out "$certificate" -days 3650 -nodes -subj "/C=GB/ST=London/L=London/O=Google Trust Services LLC/CN=$d"
        fi
        echo "New certificate and private key generated."
    fi
    chmod 600 -R $private_key

}
