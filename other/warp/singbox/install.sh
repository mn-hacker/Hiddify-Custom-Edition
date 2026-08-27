#!/bin/bash
# watashi: warp v12.2.45
#
# Installs the wgcf CLI and registers the hiddify-warp unit. It does NOT create
# the WARP account: run.sh owns that, so this script stays safe to re-run and
# never burns a registration on every install pass.
#
# Order matters here: daemon-reload comes BEFORE enable, otherwise systemd
# enables the copy of the unit it had cached from the previous version.

cd "$(dirname -- "$0")" || exit 1
source /opt/hiddify-manager/common/utils.sh
source /opt/hiddify-manager/common/package_manager.sh

WGCF="./wgcf"
UNIT_SRC="hiddify-warp.service"
UNIT_DST="${WS_UNIT_DIR:-/etc/systemd/system}/hiddify-warp.service"
WGCF_API="https://api.github.com/repos/ViRb3/wgcf/releases/latest"

if [[ "$(hconfig warp_mode disable)" == "disable" ]]; then
    warning "- WARP is disabled in the panel, skipping its installation."
    bash disable.sh
    exit 0
fi

function wgcf_works() {
    [ -x "$WGCF" ] && "$WGCF" --version >/dev/null 2>&1
}

function arch_name() {
    local a
    a=$(dpkg --print-architecture 2>/dev/null || uname -m)
    case "$a" in
    x86_64 | amd64) echo "amd64" ;;
    aarch64 | arm64) echo "arm64" ;;
    *) echo "$a" ;;
    esac
}

# Newest release straight from the vendor. Downloaded to a temp file and only
# moved into place after it proves it can actually run on this machine.
function install_latest_wgcf() {
    local arch=$1 tmp url
    url=$(curl --connect-timeout 10 -fsSL "$WGCF_API" 2>/dev/null | grep 'browser_download_url' | cut -d'"' -f4 | grep linux | grep -- "$arch" | head -n 1)
    if [ -z "$url" ]; then
        return 1
    fi
    tmp=$(mktemp)
    if ! curl --connect-timeout 10 -fsSL "$url" -o "$tmp"; then
        rm -f "$tmp"
        return 1
    fi
    chmod +x "$tmp"
    if ! "$tmp" --version >/dev/null 2>&1; then
        rm -f "$tmp"
        return 1
    fi
    mv -f "$tmp" "$WGCF"
    echo "  wgcf from $url"
    return 0
}

# Fallback: the pinned copy in common/packages.lock, which is sha256 verified.
function install_pinned_wgcf() {
    download_package wgcf "$WGCF"
    local code=$?
    # 1 means "already at the pinned version", which is not a failure
    if [[ $code == 0 || $code == 1 ]]; then
        chmod +x "$WGCF" 2>/dev/null
        if wgcf_works; then
            set_installed_version wgcf >/dev/null 2>&1
            return 0
        fi
    fi
    return 1
}

# 1) the binary
if wgcf_works; then
    echo "- wgcf is already installed: $("$WGCF" --version 2>/dev/null | head -n 1)"
else
    ARCH=$(arch_name)
    if install_latest_wgcf "$ARCH"; then
        success "- Installed the latest wgcf release."
    elif install_pinned_wgcf; then
        warning "- Could not reach GitHub, used the pinned wgcf package instead."
    else
        error "- WARP: no working wgcf binary could be installed."
        exit 1
    fi
fi

# a copy on PATH so status.sh and the operator can call wgcf directly
install -m 755 "$WGCF" "${WS_BIN_DIR:-/usr/bin}/wgcf" 2>/dev/null

# 2) the unit
if ! cmp -s "$UNIT_SRC" "$UNIT_DST"; then
    install -m 644 "$UNIT_SRC" "$UNIT_DST" || exit 1
fi
systemctl daemon-reload
systemctl enable hiddify-warp.service >/dev/null 2>&1

# 3) a leftover wg-quick@warp from the old interface mode would fight over the
# default route, and that is exactly what used to make WARP look broken.
if systemctl is-enabled wg-quick@warp >/dev/null 2>&1; then
    warning "- Disabling the old wg-quick@warp mode."
    systemctl disable --now wg-quick@warp >/dev/null 2>&1
fi

success "- WARP installed. run.sh will create the account and start it."
