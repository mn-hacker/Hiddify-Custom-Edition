#!/bin/bash
# mtg installer - repaired in watashi v12.2.53
source /opt/hiddify-manager/common/package_manager.sh
cd "$(dirname "$0")" || exit 1

tg_log() { echo "mtg: $*" >&2; }

tg_pkg_arch() {
    case "$(uname -m)" in
        x86_64) echo "amd64" ;;
        aarch64) echo "arm64" ;;
        *) echo "" ;;
    esac
}

ARCH=$(tg_pkg_arch)
if [[ -z "$ARCH" ]]; then
    tg_log "$(uname -m) is not an architecture mtg ships for"
    exit 2
fi

systemctl stop mtproxy.service 2>/dev/null || true
systemctl disable mtproxy.service 2>/dev/null || true
mkdir -p /opt/hiddify-manager/log/system

VERSION=$(get_latest_version mtproxygo "$ARCH")
if [[ -z "$VERSION" ]]; then
    tg_log "mtproxygo is not pinned in common/packages.lock for $ARCH"
    exit 3
fi

# The old version of this file removed the extracted folder *after* extracting,
# and asked for the download without a version - which quietly returns 1 on the
# second apply and left tar to fail on a file that was never written.
rm -rf mtg-*/ mtg-linux.tar.gz
if ! download_package mtproxygo mtg-linux.tar.gz "$VERSION" force; then
    tg_log "could not download the pinned build $VERSION"
    exit 4
fi

WORK=$(mktemp -d)
if ! tar -xzf mtg-linux.tar.gz -C "$WORK"; then
    tg_log "the archive did not open"
    rm -rf "$WORK"
    exit 5
fi
BIN=$(find "$WORK" -type f -name mtg | head -n 1)
if [[ -z "$BIN" ]]; then
    tg_log "no mtg binary inside the archive"
    ls -lR "$WORK" >&2
    rm -rf "$WORK"
    exit 6
fi
install -m 755 "$BIN" ./mtg
rm -rf "$WORK" mtg-linux.tar.gz

if ! ./mtg --version >/dev/null 2>&1; then
    tg_log "the binary does not run on this machine"
    exit 7
fi
set_installed_version mtproxygo "$VERSION"
tg_log "installed $(./mtg --version 2>&1 | head -n 1)"
exit 0
