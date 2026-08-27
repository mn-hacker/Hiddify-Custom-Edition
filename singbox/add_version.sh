#!/bin/bash
# watashi v12.2.50: the asset names here were wrong. the releases carry
# sing-box-<version>-linux-<arch>.tar.gz, not sing-box-linux-<arch>.zip, so
# every attempt to pin a new version downloaded a 404 page and stored its
# hash as if it were a core.
latest=$1
if [ -z "$latest" ]; then
    echo "usage: $0 <version>   e.g. $0 1.13.0.h10"
    exit 1
fi
cd "$(dirname -- "$0")" || exit 1
source ../common/package_manager.sh
base=https://github.com/mn-hacker/Hiddify-Custom-SingBox/releases/download/v$latest
add_package singbox $latest arm64 $base/sing-box-$latest-linux-arm64.tar.gz
add_package singbox $latest amd64 $base/sing-box-$latest-linux-amd64.tar.gz
