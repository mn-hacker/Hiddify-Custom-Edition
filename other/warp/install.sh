#!/bin/bash
# watashi: warp dispatch v12.2.126
# every entry point goes to the same implementation, so install/run/disable
# can never end up managing two different WARP backends again.
# v12.2.126: the implementation moved from singbox/ (wgcf + a sing-box
# wireguard endpoint) to warpplus/ (the warp-plus engine).
cd "$(dirname -- "$0")" || exit 1
cd warpplus && exec bash install.sh "$@"
