#!/bin/bash
# watashi: warp v12.2.128
#
# A new WARP IP. warp-plus keeps its identity and its generated profile in the
# cache folder, so a new IP means: park the cache, let run.sh build a fresh
# one, and check from the outside whether the address really changed.
#
# The old wgcf version moved its account file aside and never put it back when
# the retry failed, which left the server with no WARP account at all. This
# one restores the previous cache if nothing better was found.

cd "$(dirname -- "$0")" || exit 1
source /opt/hiddify-manager/common/utils.sh

CACHE="cache"
BACKUP="cache.backup"
PORT=3000
PROXY="socks5h://127.0.0.1:$PORT"

function current_ip() {
    curl -s -x "$PROXY" --connect-timeout 5 https://v4.ident.me 2>/dev/null
}

function restore_cache() {
    if [ -d "$BACKUP" ]; then
        rm -rf "$CACHE"
        mv -f "$BACKUP" "$CACHE"
        bash run.sh >/dev/null 2>&1
    fi
}

old=$(current_ip)
echo "- Current WARP IP: ${old:-unknown}"

rm -rf "$BACKUP"
[ -d "$CACHE" ] && cp -a "$CACHE" "$BACKUP"

for try in 1 2 3; do
    rm -rf "$CACHE"
    mkdir -p "$CACHE"
    bash run.sh >/dev/null 2>&1
    new=$(current_ip)
    if [ -n "$new" ] && [ "$new" != "$old" ]; then
        success "- WARP IP changed from ${old:-none} to $new"
        rm -rf "$BACKUP"
        exit 0
    fi
    warning "- Try $try gave ${new:-no answer}, trying again..."
done

error "- Could not change the WARP IP, putting the previous one back."
restore_cache
exit 1
