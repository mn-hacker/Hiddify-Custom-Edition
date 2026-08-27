#!/bin/bash
# watashi v12.2.51: the version bumper.
#
# packages.lock is the only place that says which release of a core this panel
# trusts, and every line in it carries a sha256. Until now those lines were
# written by hand, which is why the file still pinned Xray 26.3.27 while the
# vendor was on 26.7.28. This script asks each vendor what the newest release
# is, downloads both architectures, hashes them, and writes the pins. It has to
# run on the server, because it needs the network.
#
#   bash common/bump_cores.sh check
#   bash common/bump_cores.sh pin xray
#   bash common/bump_cores.sh pin xray 26.7.28
#   bash common/bump_cores.sh pin-all
#   bash common/bump_cores.sh mark-tested xray 26.7.28

cd "$(dirname -- "$0")" || exit 1
# core_manager.sh only runs its own command line when it is called directly, so
# sourcing it here just brings in the helpers.
# shellcheck source=/dev/null
source ./core_manager.sh

BC_TMP=${BC_TMP:-/tmp/watashi-bump.$$}
mkdir -p "$BC_TMP" 2>/dev/null
trap 'rm -rf "$BC_TMP"' EXIT

bc_pinned() {
    awk -F'|' -v n="$1" '$1==n {print $2}' "$CM_LOCK" 2>/dev/null |
        sort -u | sort -V | tail -n 1
}

bc_sha() {
    sha256sum "$1" 2>/dev/null | cut -d' ' -f1
}

bc_grab() {
    # a release asset that is html, empty or tiny is a 404 page, not a core
    local url=$1 out=$2 size
    if ! curl -fsSL --connect-timeout 15 --retry 2 -o "$out" "$url"; then
        echo "    could not download $url"
        return 1
    fi
    size=$(stat -c %s "$out" 2>/dev/null || echo 0)
    if [ "$size" -lt 65536 ]; then
        echo "    $url gave only $size bytes, that is not a release"
        return 1
    fi
    if head -c 512 "$out" | grep -qi '<!doctype html\|<html'; then
        echo "    $url gave a web page, not a file"
        return 1
    fi
    return 0
}

bc_pin_one() {
    local name=$1 version=$2 arch url file hash old
    if [ -z "$(cm_row "$name")" ]; then
        echo "$name is not in $CM_REGISTRY"
        return 1
    fi
    if [ -z "$version" ]; then
        version=$(cm_latest "$name") || {
            echo "$name: the vendor could not be reached"
            return 1
        }
    fi
    echo "$name -> $version"
    for arch in amd64 arm64; do
        if grep -q "^$name|$version|$arch|" "$CM_LOCK" 2>/dev/null; then
            echo "    $arch is already pinned"
            continue
        fi
        url=$(cm_url "$name" "$version" "$arch") || continue
        file="$BC_TMP/$name-$version-$arch"
        bc_grab "$url" "$file" || return 1
        hash=$(bc_sha "$file")
        if [ -z "$hash" ]; then
            echo "    the hash of $arch could not be taken"
            return 1
        fi
        cm_pin "$name" "$version" "$arch" "$url" "$hash"
        echo "    $arch pinned with $hash"
    done
    old=$(bc_pinned "$name")
    echo "    newest pinned version is now $old"
}

bc_mark_tested() {
    local name=$1 version=$2 tmp
    if [ -z "$name" ] || [ -z "$version" ]; then
        echo "usage: $0 mark-tested <core> <version>"
        return 1
    fi
    if ! grep -q "^$name|$version|" "$CM_LOCK" 2>/dev/null; then
        echo "$name $version is not pinned yet, pin it first"
        return 1
    fi
    tmp="$BC_TMP/registry"
    awk -F'|' -v OFS='|' -v n="$name" -v v="$version" \
        '$1==n && NF>=10 {$10=v} {print}' "$CM_REGISTRY" >"$tmp" || return 1
    cat "$tmp" >"$CM_REGISTRY"
    echo "$name is now marked as tested up to $version"
}

bc_check() {
    local name
    printf '%-20s %-14s %-14s %-14s\n' CORE PINNED INSTALLED NEWEST
    for name in $(cm_cores); do
        printf '%-20s %-14s %-14s %-14s\n' \
            "$name" "$(bc_pinned "$name")" \
            "$(cm_installed "$name")" "$(cm_latest "$name" 2>/dev/null)"
    done
}

case "$1" in
check) bc_check ;;
pin) bc_pin_one "$2" "$3" ;;
pin-all)
    for c in $(cm_cores); do bc_pin_one "$c" ""; done
    ;;
mark-tested) bc_mark_tested "$2" "$3" ;;
*)
    echo "usage: $0 {check|pin <core> [version]|pin-all|mark-tested <core> <version>}"
    exit 1
    ;;
esac
