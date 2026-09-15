#!/bin/bash
# watashi: warp v12.2.126
# The wgcf backend that used to live here is gone. It probed itself with
# "wgcf --version", a flag wgcf does not have, so the installer exited
# before it ever created the systemd unit. Everything now goes to the
# warp-plus engine in ../warpplus.
cd "$(dirname -- "$0")/../warpplus" || exit 1
exec bash status.sh "$@"
