source /opt/hiddify-manager/common/utils.sh

# Create nginx user if not exists
useradd nginx 2>/dev/null || true

# Add nginx official repo if needed
if [ ! -f "/etc/apt/sources.list.d/nginx.list" ]; then
    curl -sS https://nginx.org/keys/nginx_signing.key | gpg --dearmor |
        sudo tee /usr/share/keyrings/nginx-archive-keyring.gpg >/dev/null 2>&1
    
    CODENAME=$(lsb_release -cs 2>/dev/null || echo "jammy")
    echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] \
    http://nginx.org/packages/mainline/ubuntu $CODENAME nginx" |
        sudo tee /etc/apt/sources.list.d/nginx.list >/dev/null 2>&1
    
    sudo apt update -y >/dev/null 2>&1
fi

# Check if nginx is already installed
if command -v nginx &>/dev/null; then
    echo "nginx is already installed"
else
    # Install nginx from official repo
    install_package nginx || {
        # If official repo fails, try ubuntu repo
        rm -f /etc/apt/sources.list.d/nginx.list
        apt update -y >/dev/null 2>&1
        install_package nginx-full || install_package nginx-light || install_package nginx
    }
fi

systemctl kill nginx >/dev/null 2>&1 || true
systemctl disable nginx >/dev/null 2>&1 || true
systemctl kill apache2 >/dev/null 2>&1 || true
systemctl disable apache2 >/dev/null 2>&1 || true

rm -f /etc/nginx/conf.d/web.conf 2>/dev/null
rm -f /etc/nginx/sites-available/default 2>/dev/null
rm -f /etc/nginx/sites-enabled/default 2>/dev/null
rm -f /etc/nginx/conf.d/default.conf 2>/dev/null
rm -f /etc/nginx/conf.d/xray-base.conf 2>/dev/null
rm -f /etc/nginx/conf.d/speedtest.conf 2>/dev/null

mkdir -p run
ln -sf $(pwd)/hiddify-nginx.service /etc/systemd/system/hiddify-nginx.service
systemctl enable hiddify-nginx.service 2>/dev/null || true
