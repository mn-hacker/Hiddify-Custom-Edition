#!/bin/bash

# Setup logrotate for Hiddify Manager logs
# watashi v12.2.68: the logs are written by many different programs. Some of them
# hold the file open for days, so renaming the file alone left them writing into a
# file nobody could see any more while the disk kept filling. copytruncate keeps every
# writer pointing at the same file. maxsize lets a single loud day rotate before the
# daily turn arrives, and the hourly runner is what actually looks at that size.

cat > /etc/logrotate.d/hiddify-manager << 'LOGROTATE'
/opt/hiddify-manager/log/system/*.log {
    daily
    maxsize 20M
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    copytruncate
}

/var/log/hiddify/*.log {
    daily
    maxsize 20M
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    copytruncate
}
LOGROTATE

chmod 644 /etc/logrotate.d/hiddify-manager

cat > /etc/cron.hourly/hiddify-logrotate << 'HOURLY'
#!/bin/bash
# watashi v12.2.68: maxsize is only noticed when logrotate runs, and the system runs it
# once a day. One hour is short enough that a loud log cannot fill the disk.
/usr/sbin/logrotate /etc/logrotate.d/hiddify-manager 2>/dev/null || true
HOURLY

chmod 755 /etc/cron.hourly/hiddify-logrotate

echo "Logrotate configured for Hiddify Manager"
