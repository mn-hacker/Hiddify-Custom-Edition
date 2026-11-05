#!/bin/bash
# watashi v12.3.40dev: the old project name was taken out of this file (names, paths and links only)
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

cd $( dirname -- "$0"; )

# Clean up old log files (older than 7 days)
find /opt/watashi-manager/log -name "*.log" -type f -mtime +7 -delete 2>/dev/null
find /opt/watashi-manager/log -name "*.log.*" -type f -mtime +7 -delete 2>/dev/null

# Truncate large log files (> 100MB)
find /opt/watashi-manager/log -name "*.log" -type f -size +100M -exec truncate -s 0 {} \; 2>/dev/null

# Clean up systemd journal (keep only 3 days)
journalctl --vacuum-time=3d 2>/dev/null

# Run logrotate
/usr/sbin/logrotate -f /etc/logrotate.d/watashi-manager 2>/dev/null

# Free up memory cache
sync; echo 3 > /proc/sys/vm/drop_caches 2>/dev/null