#!/bin/bash
# watashi v12.2.50: same shape as the sing-box script, with a usage guard so
# an empty argument can no longer pin a version called v.
latest=$1
if [ -z "$latest" ]; then
    echo "usage: $0 <version>   e.g. $0 26.7.28"
    exit 1
fi
cd "$(dirname -- "$0")" || exit 1
source ../common/package_manager.sh
base=https://github.com/XTLS/Xray-core/releases/download/v$latest
add_package xray $latest arm64 $base/Xray-linux-arm64-v8a.zip
add_package xray $latest amd64 $base/Xray-linux-64.zip
