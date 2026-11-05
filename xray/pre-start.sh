#!/bin/bash
# watashi v12.3.40dev: the old project name was taken out of this file (names, paths and links only)
cd $( dirname -- "$0"; )
rm -rf run/*
rm -rf /dev/shm/watashi-xtls-main.sock
# watashi v12.3.41dev: a hand built inbound whose certificate is gone or whose
# port another program took is taken out before xray starts, at every start
# (a reboot, a crash, an apply), so it cannot keep xray down.
bash /opt/watashi-manager/xray/custom_guard.sh boot >/dev/null 2>&1 || true
exit 0
