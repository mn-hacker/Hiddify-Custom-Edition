#!/bin/bash
# telemt installer - watashi v12.2.53
source /opt/hiddify-manager/common/package_manager.sh
cd "$(dirname "$0")" || exit 1

TM_FALLBACK="3.4.24"
TM_SEEN="/opt/hiddify-manager/log/system/telemt.downloads.log"

tm_log() { echo "telemt: $*" >&2; }

tm_arch() {
    case "$(uname -m)" in
        x86_64) echo "x86_64" ;;
        aarch64) echo "aarch64" ;;
        *) echo "" ;;
    esac
}

tm_pkg_arch() {
    case "$(uname -m)" in
        x86_64) echo "amd64" ;;
        aarch64) echo "arm64" ;;
        *) echo "" ;;
    esac
}

tm_libc() {
    if ldd --version 2>&1 | grep -iq musl; then echo "musl"; else echo "gnu"; fi
}

ARCH=$(tm_arch)
if [[ -z "$ARCH" ]]; then
    tm_log "$(uname -m) is not a machine telemt ships binaries for"
    exit 2
fi

mkdir -p /opt/hiddify-manager/log/system
mkdir -p /var/lib/telemt/tlsfront
systemctl stop telemt.service 2>/dev/null || true

PKG_ARCH=$(tm_pkg_arch)
TARBALL="telemt.tar.gz"
rm -f "$TARBALL"
PINNED=0
grep -q "^telemt|" /opt/hiddify-manager/common/packages.lock 2>/dev/null && PINNED=1

if [[ "$PINNED" == "1" ]]; then
    VERSION=$(get_latest_version telemt "$PKG_ARCH")
    tm_log "using the pinned build $VERSION for $PKG_ARCH"
    if ! download_package telemt "$TARBALL" "$VERSION" force; then
        tm_log "the pinned download failed"
        exit 3
    fi
else
    VERSION="$TM_FALLBACK"
    ASSET="telemt-${ARCH}-linux-$(tm_libc).tar.gz"
    URL="https://github.com/telemt/telemt/releases/latest/download/${ASSET}"
    tm_log "telemt is not pinned in packages.lock yet, so $ASSET arrives without a sha256 to compare against"
    if ! curl -fsSL -o "$TARBALL" "$URL"; then
        tm_log "could not download $URL"
        exit 4
    fi
    SEEN=$(sha256sum "$TARBALL" | cut -d" " -f1)
    tm_log "sha256 of what arrived: $SEEN"
    echo "$(date -u +%F)|telemt|$PKG_ARCH|$URL|$SEEN" >> "$TM_SEEN"
fi

WORK=$(mktemp -d)
if ! tar -xzf "$TARBALL" -C "$WORK"; then
    tm_log "the archive did not open"
    rm -rf "$WORK"
    exit 5
fi
BIN=$(find "$WORK" -type f -name telemt | head -n 1)
if [[ -z "$BIN" ]]; then
    tm_log "no telemt binary inside the archive"
    ls -lR "$WORK" >&2
    rm -rf "$WORK"
    exit 6
fi
install -m 755 "$BIN" ./telemt
rm -rf "$WORK" "$TARBALL"

if ! ./telemt --version >/dev/null 2>&1; then
    tm_log "the binary does not run on this machine"
    exit 7
fi
tm_log "installed $(./telemt --version 2>&1 | head -n 1)"
if [[ "$PINNED" == "1" ]]; then
    set_installed_version telemt "$VERSION"
fi
exit 0
