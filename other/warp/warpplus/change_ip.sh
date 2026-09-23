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
# watashi v12.2.130v: run.sh remembers the address the node left through, so a
# deliberate change of IP has to forget it first. It is exported as well,
# so the run.sh started below cannot write the old one straight back.
PIN="$CACHE/.watashi-endpoint"
export WS_WARP_NEW_IP=1
PORT=3000
PROXY="socks5h://127.0.0.1:$PORT"

function current_ip() {
    curl -s -x "$PROXY" --connect-timeout 5 https://v4.ident.me 2>/dev/null
}

function restore_cache() {
    if [ -d "$BACKUP" ]; then
        rm -rf "$CACHE"
        mv -f "$BACKUP" "$CACHE"
        # watashi v12.2.130v: putting the old identity back means the old
        # address may be reachable again, so run.sh is allowed to use and
        # remember it instead of hunting for yet another one.
        # watashi v12.2.130bd: the flag is dropped so the restored identity may keep
        # its address, but the engine is still running on the identity that
        # has just been thrown away, and the argument list did not change.
        # Without a door that says "restart anyway", run.sh looked at a
        # healthy tunnel and left it exactly where it was, so putting the
        # old cache back did nothing at all.
        unset WS_WARP_NEW_IP
        WS_WARP_RESTART=1 bash run.sh >/dev/null 2>&1
    fi
}

old=$(current_ip)
echo "- Current WARP IP: ${old:-unknown}"

rm -rf "$BACKUP"
[ -d "$CACHE" ] && cp -a "$CACHE" "$BACKUP"

for try in 1 2 3; do
    # watashi v12.2.130bd: the account is made once, not once per try. Wiping the
    # cache registers a brand new account with cloudflare, and doing that
    # three times in a row from the same server IP is how a rate limit turns
    # into a permanent one - the header of run.sh names it as the mistake of
    # the version this replaced, and this loop was making it anyway. The
    # retries keep the identity and only ask for another edge, which is what
    # actually decides the exit IP.
    if [ "$try" = 1 ]; then
        rm -rf "$CACHE"
        mkdir -p "$CACHE"
    else
        echo "- Keeping the new account, looking for another cloudflare edge."
    fi
    rm -f "$PIN"
    bash run.sh >/dev/null 2>&1
    new=$(current_ip)
    if [ -n "$new" ] && [ "$new" != "$old" ]; then
        success "- WARP IP changed from ${old:-none} to $new"
        rm -rf "$BACKUP"
        # watashi v12.2.130bd: run.sh has already written the address down on its
        # way out. The second run that used to stand here restarted the
        # engine onto the pinned address right after the operator had been
        # shown the new IP, so the IP they were told was often not the one
        # they were left with - and when that address did not answer, the
        # whole thing ended up back on the scan, a minute later.
        exit 0
    fi
    warning "- Try $try gave ${new:-no answer}, trying again..."
done

error "- Could not change the WARP IP, putting the previous one back."
restore_cache
exit 1
