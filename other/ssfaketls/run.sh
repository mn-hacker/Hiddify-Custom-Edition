# watashi v12.3.40dev: the old project name was taken out of this file (names, paths and links only)
# watashi v12.3.36dev: without obfs-server the unit can only fail and be
# restarted by systemd every 5 seconds, forever. Say it once and stop instead.
# A unit that an older run.sh already enabled keeps looping on its own, so it
# is stopped and disabled here as well. apply_configs never runs install.sh
# (DO_NOT_INSTALL=true), so only a complete install brings obfs-server back.
if ! command -v obfs-server >/dev/null 2>&1; then
    echo "watashi-ss-faketls: obfs-server is not installed, the service is stopped. Run a complete install to install it." >&2
    systemctl disable --now watashi-ss-faketls.service >/dev/null 2>&1 || true
    exit 0
fi

# Only enable/restart if service file exists
if [ -f "/etc/systemd/system/watashi-ss-faketls.service" ]; then
    systemctl daemon-reload
    systemctl enable watashi-ss-faketls.service
    systemctl restart watashi-ss-faketls.service
fi
