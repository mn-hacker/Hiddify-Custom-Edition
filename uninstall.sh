#!/bin/bash
# Hiddify Panel Uninstaller
# Usage:
#   ./uninstall.sh         - Basic uninstall (keeps database and backups)
#   ./uninstall.sh purge   - Complete removal including database

cd $(dirname -- "$0")
source ./common/utils.sh 2>/dev/null || true

PURGE_MODE=false
if [[ "$1" == "purge" ]]; then
    PURGE_MODE=true
fi

echo "=============================================="
echo "   Hiddify Panel Uninstaller"
echo "=============================================="
if [[ "$PURGE_MODE" == "true" ]]; then
    echo "Mode: PURGE (Complete removal)"
else
    echo "Mode: UNINSTALL (Keep database and backups)"
fi
echo ""

# Confirmation
if [[ "$PURGE_MODE" == "true" ]]; then
    echo "WARNING: This will COMPLETELY remove Hiddify and ALL data including database!"
    read -p "Are you sure? Type 'yes' to confirm: " confirm
    if [[ "$confirm" != "yes" ]]; then
        echo "Cancelled."
        exit 0
    fi
fi

mkdir -p /opt/hiddify-manager/log/system/ 2>/dev/null || true

function log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

function main() {
    log "Starting uninstallation..."

    # ========================================
    # PHASE 1: Stop all services
    # ========================================
    log "Stopping all Hiddify services..."
    
    # List of all Hiddify services
    SERVICES=(
        hiddify-panel
        hiddify-panel-background-tasks
        hiddify-singbox
        hiddify-xray
        hiddify-nginx
        hiddify-haproxy
        hiddify-redis
        hiddify-warp
        hiddify-cli
        hiddify-ssh-liberty-bridge
        hiddify-mtproxy
        hiddify-telegram
        hiddify-ssfaketls
        hiddify-speedtest
        wg-quick@warp
        rathole
    )
    
    for service in "${SERVICES[@]}"; do
        systemctl stop "$service" 2>/dev/null || true
        systemctl disable "$service" 2>/dev/null || true
        log "  Stopped: $service"
    done

    # ========================================
    # PHASE 2: Remove systemd service files
    # ========================================
    log "Removing systemd service files..."
    
    rm -f /etc/systemd/system/hiddify-*.service 2>/dev/null
    rm -f /etc/systemd/system/rathole.service 2>/dev/null
    rm -f /etc/systemd/system/wg-quick@warp.service 2>/dev/null
    rm -f /etc/systemd/system/multi-user.target.wants/hiddify-*.service 2>/dev/null
    systemctl daemon-reload

    # ========================================
    # PHASE 3: Remove cron jobs
    # ========================================
    log "Removing cron jobs..."
    
    rm -f /etc/cron.d/hiddify* 2>/dev/null
    rm -f /etc/cron.daily/hiddify* 2>/dev/null
    service cron reload 2>/dev/null || true

    # ========================================
    # PHASE 4: Remove WARP
    # ========================================
    log "Removing WARP configuration..."
    
    # Remove WARP interface
    ip link del warp 2>/dev/null || true
    rm -f /etc/wireguard/warp.conf 2>/dev/null
    rm -rf /opt/hiddify-manager/other/warp/wgcf* 2>/dev/null

    # ========================================
    # PHASE 5: Clean nginx and haproxy
    # ========================================
    log "Removing nginx and haproxy configs..."
    
    rm -f /etc/nginx/sites-enabled/hiddify* 2>/dev/null
    rm -f /etc/nginx/sites-available/hiddify* 2>/dev/null
    rm -f /etc/nginx/conf.d/hiddify* 2>/dev/null
    rm -f /etc/haproxy/haproxy.cfg.hiddify* 2>/dev/null
    
    # Restart nginx/haproxy to use default configs
    systemctl restart nginx 2>/dev/null || true
    systemctl restart haproxy 2>/dev/null || true

    # ========================================
    # PHASE 6: Remove SSL certificates
    # ========================================
    log "Removing SSL certificates..."
    
    rm -rf /opt/hiddify-manager/acme.sh/certs 2>/dev/null
    rm -rf /root/.acme.sh 2>/dev/null
    
    # ========================================
    # PHASE 7: Remove Python virtual environment
    # ========================================
    log "Removing Python virtual environment..."
    
    rm -rf /opt/hiddify-manager/.venv* 2>/dev/null

    # ========================================
    # PHASE 8: Remove symlinks
    # ========================================
    log "Removing symlinks..."
    
    rm -f /usr/local/bin/hiddify* 2>/dev/null
    rm -f /usr/bin/hiddify* 2>/dev/null
    rm -f /opt/hiddify-config 2>/dev/null
    rm -f /opt/hiddify-server 2>/dev/null

    # ========================================
    # PHASE 9: Remove menu from bashrc
    # ========================================
    log "Removing menu from bashrc..."
    
    sed -i '/hiddify-manager/d' ~/.bashrc 2>/dev/null || true
    sed -i '/hiddify-config/d' ~/.bashrc 2>/dev/null || true

    # ========================================
    # PHASE 10: Remove firewall rules (optional, keep for security)
    # ========================================
    # We don't remove firewall rules as they may be needed for security

    if [[ "$PURGE_MODE" == "true" ]]; then
        # ========================================
        # PURGE: Remove database
        # ========================================
        log "Removing database..."
        
        # Drop hiddify database
        mysql -u root -e "DROP DATABASE IF EXISTS hiddify_panel;" 2>/dev/null || true
        mysql -u root -e "DROP USER IF EXISTS 'hiddify'@'localhost';" 2>/dev/null || true
        
        # ========================================
        # PURGE: Remove backup files
        # ========================================
        log "Removing backups..."
        rm -rf /opt/hiddify-manager/backup* 2>/dev/null

        # ========================================
        # PURGE: Remove all panel files
        # ========================================
        log "Removing all Hiddify files..."
        
        # Remove entire directory
        cd /
        rm -rf /opt/hiddify-manager 2>/dev/null
        
        # ========================================
        # PURGE: Uninstall packages (optional - may break other services)
        # ========================================
        log "Removing installed packages..."
        
        # Only remove hiddify-specific packages, keep common ones
        pip3 uninstall -y hiddifypanel 2>/dev/null || true
        
        # Ask before removing mariadb as it might be used by other services
        read -p "Remove MariaDB/MySQL? (y/N): " remove_db
        if [[ "$remove_db" == "y" || "$remove_db" == "Y" ]]; then
            apt purge -y mariadb-server mariadb-client 2>/dev/null || true
            apt purge -y mysql-server mysql-client 2>/dev/null || true
            rm -rf /var/lib/mysql 2>/dev/null
        fi
        
        # Clean up
        apt autoremove -y 2>/dev/null || true
        
        log "=============================================="
        log "PURGE COMPLETE!"
        log "Hiddify Panel has been completely removed."
        log "Your server is now clean for fresh installation."
        log "=============================================="
        
    else
        # Regular uninstall - keep database and some configs
        log "Removing panel files (keeping database and backups)..."
        
        # Keep: hiddify-panel/backup*, database
        # Remove everything else
        cd /opt/hiddify-manager
        
        # Save backups
        mkdir -p /tmp/hiddify-backup 2>/dev/null
        cp -r backup* /tmp/hiddify-backup/ 2>/dev/null || true
        cp -r hiddify-panel/backup* /tmp/hiddify-backup/ 2>/dev/null || true
        
        # Remove files
        rm -rf xray singbox nginx haproxy acme.sh other common 2>/dev/null
        rm -rf .venv* log 2>/dev/null
        rm -f *.sh VERSION current.json 2>/dev/null
        
        # Restore backups
        mv /tmp/hiddify-backup/* /opt/hiddify-manager/ 2>/dev/null || true
        rm -rf /tmp/hiddify-backup 2>/dev/null
        
        log "=============================================="
        log "UNINSTALL COMPLETE!"
        log "Database and backups have been preserved."
        log "Run the installer again to reinstall."
        log "=============================================="
    fi
}

# Run main and log output
main 2>&1 | tee /tmp/hiddify-uninstall.log

# If purge, the log file location changes
if [[ "$PURGE_MODE" != "true" ]] && [[ -d "/opt/hiddify-manager/log/system" ]]; then
    mv /tmp/hiddify-uninstall.log /opt/hiddify-manager/log/system/uninstall.log 2>/dev/null || true
fi

echo ""
echo "Uninstallation log saved to: /tmp/hiddify-uninstall.log"
