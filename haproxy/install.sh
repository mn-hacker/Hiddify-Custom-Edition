# watashi v12.3.40dev: the old project name was taken out of this file (names, paths and links only)
source /opt/watashi-manager/common/utils.sh
rm -rf *.template
# watashi v12.3.40dev: the lines that stopped the sniproxy unit of the oldest
# upstream releases were dropped. That unit only ever existed under the old
# name, and common/watashi_legacy.sh removes every unit of that name. A stray
# sniproxy daemon would still sit on the ports haproxy needs, so it goes.
if is_installed sniproxy; then
    pkill -9 sniproxy >/dev/null 2>&1
fi

HAPROXY_VERSION=3.2
if grep -q '^VERSION_CODENAME=jammy' /etc/os-release; then \
    warning "Deprecated Warning: OS is Jammy (Ubuntu 22.04). haproxy max version is 3.0"; \
    HAPROXY_VERSION=3.0
    echo "OS version is 22, checking for haproxy=${HAPROXY_VERSION}"
fi
if ! is_installed_package "haproxy=${HAPROXY_VERSION}"; then
    echo "Adding PPA for haproxy-${HAPROXY_VERSION}"
    add-apt-repository -y ppa:vbernat/haproxy-${HAPROXY_VERSION}
    if [ $? -ne 0 ]; then
        echo "PPA add failed, retrying after apt update..."
        sleep 3
        apt update -y
        add-apt-repository -y ppa:vbernat/haproxy-${HAPROXY_VERSION} || {
            warning "Could not add haproxy PPA, trying system version"
        }
    fi
    echo "Installing haproxy ${HAPROXY_VERSION}"
    install_package "haproxy=${HAPROXY_VERSION}.*" || install_package haproxy
else
    echo "haproxy ${HAPROXY_VERSION} is already installed"
fi
systemctl kill haproxy >/dev/null 2>&1
systemctl stop haproxy >/dev/null 2>&1
systemctl disable haproxy >/dev/null 2>&1

ln -sf $(pwd)/watashi-haproxy.service /etc/systemd/system/watashi-haproxy.service
systemctl enable watashi-haproxy.service
