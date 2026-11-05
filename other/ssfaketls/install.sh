# watashi v12.3.40dev: the old project name was taken out of this file (names, paths and links only)
source /opt/watashi-manager/common/utils.sh
source /opt/watashi-manager/common/package_manager.sh

# watashi v12.2.130aa: the simple-obfs package draws a password in its postinst with
# pwgen, which ubuntu does not install on its own; without it the install log
# ends with 'simple-obfs.postinst: 31: pwgen: not found'. It is asked for
# first so the postinst finds it.
install_package pwgen
install_package shadowsocks-libev

# watashi v12.3.36dev: simple-obfs, the package that carries obfs-server, was
# dropped from Ubuntu after 24.04 (Launchpad publishes it up to noble only).
# On 26.04 "apt install shadowsocks-libev simple-obfs" failed as a whole, so
# obfs-server never existed and watashi-ss-faketls stayed dead in the panel.
# apt is still asked first, on any release that has the package; otherwise
# the noble build pinned in common/packages.lock is fetched, its sha256 is
# checked, and apt installs it so its dependencies (libcork16, libev4t64,
# libcap2-bin - all still shipped by 26.04) are pulled in the normal way.
function ws_install_simple_obfs() {
    local ver tmp
    command -v obfs-server >/dev/null 2>&1 && return 0
    if apt-cache policy simple-obfs 2>/dev/null | grep -q 'Candidate: [0-9]'; then
        install_package simple-obfs
        command -v obfs-server >/dev/null 2>&1 && return 0
    fi
    ver=$(get_latest_version simple-obfs)
    if [ -z "$ver" ]; then
        error "simple-obfs is not in apt and not listed in common/packages.lock"
        return 1
    fi
    echo "simple-obfs is not available from apt on this release, installing the pinned $ver build"
    tmp=$(mktemp -d) || return 1
    chmod 755 "$tmp"
    if ! download_package simple-obfs "$tmp/simple-obfs.deb" "$ver" force; then
        rm -rf "$tmp"
        return 1
    fi
    chmod 644 "$tmp/simple-obfs.deb"
    wait_for_apt_lock || { rm -rf "$tmp"; return 1; }
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$tmp/simple-obfs.deb"
    rm -rf "$tmp"
    if ! command -v obfs-server >/dev/null 2>&1; then
        error "obfs-server is still missing after installing simple-obfs $ver"
        return 1
    fi
    set_installed_version simple-obfs "$ver" >/dev/null 2>&1
    return 0
}
ws_install_simple_obfs

chmod 600 *.service* 2>/dev/null || true

# Only link service file if it exists (generated from jinja template)
if [ -f "$(pwd)/watashi-ss-faketls.service" ]; then
    ln -sf $(pwd)/watashi-ss-faketls.service /etc/systemd/system/watashi-ss-faketls.service
fi

systemctl disable --now ss-faketls.service > /dev/null 2>&1 || true
rm ss-faketls.service* > /dev/null 2>&1 || true
