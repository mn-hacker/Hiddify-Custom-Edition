#!/bin/bash
# watashi: warp v12.2.127
cd "$(dirname -- "$0")" || exit 1
systemctl disable --now hiddify-warp.service >/dev/null 2>&1
# older backends: if this server was ever set up in interface mode, its routes
# would fight with the socks mode, so make sure they stay down.
systemctl disable --now wg-quick@warp >/dev/null 2>&1
echo "WARP is off."
