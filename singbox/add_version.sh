#!/bin/bash
# watashi v12.2.50: the asset names here were wrong. the releases carry
# sing-box-<version>-linux-<arch>.tar.gz, not sing-box-linux-<arch>.zip, so
# every attempt to pin a new version downloaded a 404 page and stored its
# hash as if it were a core.
latest=$1
if [ -z "$latest" ]; then
    echo "usage: $0 <version>   e.g. $0 1.14.0.w1"
    exit 1
fi
cd "$(dirname -- "$0")" || exit 1
source ../common/package_manager.sh
# watashi v12.2.98: the repository is no longer written down in two places.
# It is read out of common/core_registry.conf, the same line the installer
# and the cores page already read, so moving the core to another repository
# is one edit in one file.
reg=../common/core_registry.conf
repo=$(awk -F'|' '$1 == "singbox" {print $2; exit}' "$reg")
if [ -z "$repo" ]; then
    echo "could not read the singbox repository out of $reg"
    exit 1
fi
base=https://github.com/$repo/releases/download/v$latest
add_package singbox $latest arm64 $base/sing-box-$latest-linux-arm64.tar.gz
add_package singbox $latest amd64 $base/sing-box-$latest-linux-amd64.tar.gz
