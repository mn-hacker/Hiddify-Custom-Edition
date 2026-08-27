#!/bin/bash
# watashi: warp v12.2.45
#
# The old version downloaded a stranger's api.sh from a GitHub raw URL and ran
# it as root on every IP change. It is gone. A new IP is now obtained the plain
# way: retire the current WARP account, register a fresh one, restart.

cd "$(dirname -- "$0")" || exit 1
source /opt/hiddify-manager/common/utils.sh

ACCOUNT="wgcf-account.toml"
PORT=3000
PROXY="socks5h://127.0.0.1:$PORT"

function current_ip() {
    curl -s -x "$PROXY" --connect-timeout 4 https://v4.ident.me 2>/dev/null
}

old=$(current_ip)
echo "- Current WARP IP: ${old:-unknown}"

for try in 1 2 3; do
    # run.sh registers a new account whenever the account file is missing
    [ -f "$ACCOUNT" ] && mv -f "$ACCOUNT" "$ACCOUNT.backup"
    bash run.sh >/dev/null 2>&1
    new=$(current_ip)
    if [ -n "$new" ] && [ "$new" != "$old" ]; then
        success "- WARP IP changed from ${old:-none} to $new"
        exit 0
    fi
    warning "- Try $try gave the same IP (${new:-none}), trying again..."
done

error "- Could not change the WARP IP."
exit 1
