#!/bin/bash
# WARP run dispatcher - uses singbox WARP implementation
cd /opt/hiddify-manager/other/warp/singbox 2>/dev/null && bash run.sh || echo "WARP singbox not available"