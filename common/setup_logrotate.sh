#!/bin/bash

# Setup logrotate for Hiddify Manager logs

cat > /etc/logrotate.d/hiddify-manager << 'LOGROTATE'
/opt/hiddify-manager/log/system/*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 0644 root root
    sharedscripts
    postrotate
        systemctl reload hiddify-panel 2>/dev/null || true
    endscript
}

/var/log/hiddify/*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 0644 root root
}
LOGROTATE

chmod 644 /etc/logrotate.d/hiddify-manager
echo "Logrotate configured for Hiddify Manager"
