source ../common/utils.sh

# Try to install nginx 1.26+ but fall back to any available version
NGINX_VERSION="nginx=1.26.*"
if ! is_installed "$NGINX_VERSION" 2>/dev/null; then
    useradd nginx 2>/dev/null || true
    
    # Add nginx official repo
    curl -sS https://nginx.org/keys/nginx_signing.key | gpg --dearmor |
        sudo tee /usr/share/keyrings/nginx-archive-keyring.gpg >/dev/null 2>&1
    
    # Try mainline first, fallback to stable
    CODENAME=$(lsb_release -cs 2>/dev/null || echo "jammy")
    echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] \
    http://nginx.org/packages/mainline/ubuntu $CODENAME nginx" |
        sudo tee /etc/apt/sources.list.d/nginx.list >/dev/null 2>&1
    
    sudo apt update -y >/dev/null 2>&1
fi

# Try specific version first, fallback to any nginx
if ! install_package "$NGINX_VERSION" 2>/dev/null; then
    echo "NOTICE: nginx 1.26 not available, installing latest..."
    install_package nginx
fi

systemctl kill nginx >/dev/null 2>&1
systemctl disable nginx >/dev/null 2>&1
systemctl kill apache2 >/dev/null 2>&1
systemctl disable apache2 >/dev/null 2>&1
# pkill -9 nginx

rm /etc/nginx/conf.d/web.conf >/dev/null 2>&1
rm /etc/nginx/sites-available/default >/dev/null 2>&1
rm /etc/nginx/sites-enabled/default >/dev/null 2>&1
rm /etc/nginx/conf.d/default.conf >/dev/null 2>&1
rm /etc/nginx/conf.d/xray-base.conf >/dev/null 2>&1
rm /etc/nginx/conf.d/speedtest.conf >/dev/null 2>&1

mkdir -p run
ln -sf $(pwd)/hiddify-nginx.service /etc/systemd/system/hiddify-nginx.service
systemctl enable hiddify-nginx.service
