#!/bin/bash
# watashi v12.3.40dev: the old project name was taken out of this file (names, paths and links only)
# watashi: warp v12.2.128
#
# Installs the WARP engine (warp-plus) and registers the watashi-warp unit.
#
# Why this replaced the wgcf installer: the old script probed the binary with
# "wgcf --version", a flag wgcf does not have. The probe always failed, the
# script exited 1 before installing the unit, and that is why journalctl had
# no entries at all for watashi-warp while the panel kept saying WARP is not
# working. warp-plus reports its version with a subcommand, which is the
# command stored in the registry, and it is checked here the same way.
#
# This script never creates an account: the engine makes its own identity at
# start time, inside its cache directory, so installing is safe to re-run.

cd "$(dirname -- "$0")" || exit 1
source /opt/watashi-manager/common/utils.sh
source /opt/watashi-manager/common/package_manager.sh

BIN="./warp-plus"
UNIT_SRC="watashi-warp.service"
UNIT_DST="${WS_UNIT_DIR:-/etc/systemd/system}/watashi-warp.service"
LOGDIR="${WS_LOG_DIR:-/opt/watashi-manager/log/system}"
mkdir -p "$LOGDIR" cache

if [[ "$(hconfig warp_mode disable)" == "disable" ]]; then
    warning "- WARP is disabled in the panel, skipping its installation."
    bash disable.sh
    exit 0
fi

# warp-plus writes its version to stderr, not stdout. Reading stdout only
# returns an empty string from a binary that is in perfect health, which is
# exactly how v12.2.126 talked itself out of a working install. Both streams
# are read here.
function engine_version() {
    [ -x "$BIN" ] || return 1
    "$BIN" version 2>&1 | tr -d ' ' | head -n 1
}

# A binary counts as working if it runs and says anything at all. If it runs
# but stays silent (a future build could move the version elsewhere again),
# fall back to asking whether this machine can execute the file, so a silent
# version banner can never again block the whole feature.
function engine_works() {
    local v rc magic
    [ -x "$BIN" ] || return 1
    # First: is this a program for this machine at all? A file of the
    # wrong type still answers on stderr, so text alone proves nothing.
    magic=$(head -c4 "$BIN" 2>/dev/null | od -An -tx1 | tr -dc 'a-f0-9')
    if [ "$magic" != "7f454c46" ]; then
        echo "- WARP: $BIN is not a Linux program (bad file signature)." >&2
        return 1
    fi
    # Second: the exit code, taken without a pipeline. PIPESTATUS was
    # measured returning 0 here for a binary that really failed with 126.
    v=$("$BIN" version 2>&1)
    rc=$?
    v=$(printf %s "$v" | tr -d ' ' | head -n 1)
    if [ "$rc" -eq 0 ]; then
        [ -n "$v" ] && return 0
        # Runs but says nothing: keep it usable rather than block the
        # whole feature over a missing version banner.
        "$BIN" --help >/dev/null 2>&1 && return 0
    fi
    if [ -n "$v" ]; then
        echo "- WARP: the engine answered with: $v" >&2
    fi
    return 1
}

# The pinned copy from common/packages.lock. Its sha256 is verified by
# download_package before anything is written next to the live binary.
function install_pinned() {
    local ver tmp code found
    ver=$(get_latest_version warp-plus "$(detect_arch)")
    if [ -z "$ver" ]; then
        error "- WARP: warp-plus is not listed in common/packages.lock."
        return 1
    fi
    tmp=$(mktemp -d) || return 1
    download_package warp-plus "$tmp/warp-plus.zip" "$ver" force
    code=$?
    if [[ $code != 0 && $code != 1 ]]; then
        rm -rf "$tmp"
        return 1
    fi
    if ! unzip -o -q "$tmp/warp-plus.zip" -d "$tmp/work"; then
        error "- WARP: could not unpack the warp-plus package."
        rm -rf "$tmp"
        return 1
    fi
    found=$(find "$tmp/work" -type f -name warp-plus -print -quit 2>/dev/null)
    if [ -z "$found" ]; then
        error "- WARP: no warp-plus binary inside the package."
        rm -rf "$tmp"
        return 1
    fi
    # keep whatever worked before, so there is always something to go back to
    [ -f "$BIN" ] && cp -f "$BIN" "$BIN.previous" 2>/dev/null
    install -m 755 "$found" "$BIN"
    rm -rf "$tmp"
    if ! engine_works; then
        error "- WARP: the installed warp-plus binary does not run on this machine."
        [ -f "$BIN.previous" ] && cp -f "$BIN.previous" "$BIN"
        return 1
    fi
    set_installed_version warp-plus "$ver" >/dev/null 2>&1
    return 0
}


# watashi v12.2.130: custom warp source.
# If WATASHI_WARP_URL is set in the environment OR a warp-source.conf file
# exists next to this script, the engine is downloaded from there first.
# This is how a Watashi-Warp fork replaces the upstream binary without
# touching packages.lock or core_registry.conf.
#
# warp-source.conf format (one value per line):
#   URL_AARCH64=https://github.com/mn-hacker/Watashi-Warp/releases/download/v1.0.0/warp-plus_linux-arm64.zip
#   URL_AMD64=https://github.com/mn-hacker/Watashi-Warp/releases/download/v1.0.0/warp-plus_linux-amd64.zip
#   SHA256_AARCH64=<hash>  (optional; skip verification if absent)
#   SHA256_AMD64=<hash>    (optional)

function ws_custom_url() {
    local arch
    arch=$(detect_arch)
    local key="URL_${arch^^}"
    # env var takes priority
    local env_var="WATASHI_WARP_URL_${arch^^}"
    local via_env="${!env_var}"
    if [ -n "$via_env" ]; then
        printf '%s' "$via_env"
        return 0
    fi
    # fall back to the config file
    local conf="$(dirname -- "$0")/warp-source.conf"
    [ -f "$conf" ] || return 1
    local url
    url=$(grep -E "^${key}=" "$conf" | tail -1 | cut -d= -f2- | tr -d '[:space:]')
    [ -n "$url" ] && printf '%s' "$url" && return 0
    return 1
}

function ws_custom_sha256() {
    local arch
    arch=$(detect_arch)
    local key="SHA256_${arch^^}"
    local conf="$(dirname -- "$0")/warp-source.conf"
    [ -f "$conf" ] || return 1
    local h
    h=$(grep -E "^${key}=" "$conf" | tail -1 | cut -d= -f2- | tr -d '[:space:]')
    [ -n "$h" ] && printf '%s' "$h" && return 0
    return 1
}

function install_custom() {
    local url sha256 tmp dl_hash
    url=$(ws_custom_url) || return 1
    echo "- WARP: custom source configured: $url"
    tmp=$(mktemp -d) || return 1
    local archive="$tmp/warp-plus.zip"
    if ! curl -fsSL -o "$archive" "$url"; then
        error "- WARP: download from custom source failed."
        rm -rf "$tmp"
        return 1
    fi
    # hash check is optional for custom builds
    sha256=$(ws_custom_sha256) || true
    if [ -n "$sha256" ]; then
        dl_hash=$(sha256sum "$archive" | awk '{print $1}')
        if [ "$dl_hash" != "$sha256" ]; then
            error "- WARP: custom source hash mismatch ($dl_hash vs $sha256)."
            rm -rf "$tmp"
            return 1
        fi
        echo "- WARP: custom source hash verified."
    else
        warning "- WARP: no SHA256 in warp-source.conf, skipping hash check."
    fi
    if ! unzip -o -q "$archive" -d "$tmp/work"; then
        error "- WARP: could not unpack the custom warp package."
        rm -rf "$tmp"
        return 1
    fi
    local found
    found=$(find "$tmp/work" -type f \( -name 'warp-plus' -o -name 'watashi-warp' \) -print -quit 2>/dev/null)
    if [ -z "$found" ]; then
        error "- WARP: no warp-plus/watashi-warp binary inside the custom package."
        rm -rf "$tmp"
        return 1
    fi
    [ -f "$BIN" ] && cp -f "$BIN" "$BIN.previous" 2>/dev/null
    install -m 755 "$found" "$BIN"
    rm -rf "$tmp"
    if ! engine_works; then
        error "- WARP: the custom binary does not run on this machine."
        [ -f "$BIN.previous" ] && cp -f "$BIN.previous" "$BIN"
        return 1
    fi
    success "- WARP: custom engine installed: $(engine_version)"
    return 0
}

# 1) the engine
# watashi v12.2.130: try the custom Watashi-Warp source first, then packages.lock.
if engine_works; then
    echo "- WARP engine is already installed: $(engine_version)"
elif install_custom; then
    success "- Installed the Watashi-Warp engine: $(engine_version)"
elif install_pinned; then
    success "- Installed the WARP engine: $(engine_version)"
else
    error "- WARP: no working engine could be installed."
    exit 1
fi

# 2) the unit. daemon-reload comes BEFORE enable, otherwise systemd enables
# the copy of the unit it had cached from the previous version.
if ! cmp -s "$UNIT_SRC" "$UNIT_DST"; then
    install -m 644 "$UNIT_SRC" "$UNIT_DST" || exit 1
fi
systemctl daemon-reload
systemctl enable watashi-warp.service >/dev/null 2>&1

# 3) anything from the older backends would fight over the same port or the
# default route, and that is exactly what used to make WARP look broken.
if systemctl is-enabled wg-quick@warp >/dev/null 2>&1; then
    warning "- Disabling the old wg-quick@warp mode."
    systemctl disable --now wg-quick@warp >/dev/null 2>&1
fi

success "- WARP installed. run.sh will configure and start it."
