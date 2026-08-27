#!/bin/bash
# watashi: warp dispatch v12.2.45
# every entry point goes to the same implementation, so install/run/disable
# can never end up managing two different WARP backends again.
cd "$(dirname -- "$0")" || exit 1
cd singbox && exec bash change_ip.sh "$@"
