#!/bin/bash
# watashi: warp v12.2.45
cd "$(dirname -- "$0")" || exit 1
systemctl disable --now hiddify-warp.service >/dev/null 2>&1
# the old interface mode: if this server was ever set up that way, its routes
# would fight with the socks mode, so make sure it stays down.
systemctl disable --now wg-quick@warp >/dev/null 2>&1
echo "WARP is off."
