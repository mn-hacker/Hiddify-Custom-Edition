#!/bin/bash
# WARP installation dispatcher
cd /opt/hiddify-manager/other/warp/singbox 2>/dev/null && bash install.sh || echo "WARP singbox install skipped"