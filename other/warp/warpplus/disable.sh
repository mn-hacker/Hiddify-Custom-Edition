#!/bin/bash
# watashi v12.3.40dev: the old project name was taken out of this file (names, paths and links only)
# watashi: warp v12.2.128
cd "$(dirname -- "$0")" || exit 1
systemctl disable --now watashi-warp.service >/dev/null 2>&1
# older backends: if this server was ever set up in interface mode, its routes
# would fight with the socks mode, so make sure they stay down.
systemctl disable --now wg-quick@warp >/dev/null 2>&1
echo "WARP is off."
