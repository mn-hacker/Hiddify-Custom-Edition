#!/bin/bash
cd $(dirname -- "$0")
source /opt/hiddify-manager/common/utils.sh

install_package mariadb-server

# Ensure MariaDB is running
systemctl start mariadb 2>/dev/null || true
sleep 2

# Check if we need to setup MySQL
if [ ! -f "mysql_pass" ]; then
    echo "Generating a random password..."
    random_password=$(< /dev/urandom tr -dc 'a-zA-Z0-9' | head -c32; echo)
    echo "$random_password" >"mysql_pass"
    chmod 600 "mysql_pass"
    
    echo "Setting up MariaDB..."
    
    # On fresh Ubuntu 24.04, root can connect via socket without password
    # Try multiple methods to connect
    if sudo mysql -e "SELECT 1" 2>/dev/null; then
        echo "Connected to MySQL via sudo socket auth"
        sudo mysql <<MYSQL_SCRIPT
-- Create hiddifypanel user and database
CREATE DATABASE IF NOT EXISTS hiddifypanel CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
DROP USER IF EXISTS 'hiddifypanel'@'localhost';
CREATE USER 'hiddifypanel'@'localhost' IDENTIFIED BY '$random_password';
GRANT ALL PRIVILEGES ON hiddifypanel.* TO 'hiddifypanel'@'localhost';
GRANT ALL PRIVILEGES ON *.* TO 'hiddifypanel'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
MYSQL_SCRIPT
        echo "MySQL user 'hiddifypanel' created successfully"
    elif mysql -u root -e "SELECT 1" 2>/dev/null; then
        echo "Connected to MySQL via root without password"
        mysql -u root <<MYSQL_SCRIPT
CREATE DATABASE IF NOT EXISTS hiddifypanel CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
DROP USER IF EXISTS 'hiddifypanel'@'localhost';
CREATE USER 'hiddifypanel'@'localhost' IDENTIFIED BY '$random_password';
GRANT ALL PRIVILEGES ON hiddifypanel.* TO 'hiddifypanel'@'localhost';
GRANT ALL PRIVILEGES ON *.* TO 'hiddifypanel'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
MYSQL_SCRIPT
        echo "MySQL user 'hiddifypanel' created successfully"
    else
        echo "ERROR: Cannot connect to MySQL. Trying with skip-grant-tables..."
        systemctl stop mariadb
        mysqld_safe --skip-grant-tables --skip-networking &
        sleep 5
        mysql <<MYSQL_SCRIPT
FLUSH PRIVILEGES;
CREATE DATABASE IF NOT EXISTS hiddifypanel CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
DROP USER IF EXISTS 'hiddifypanel'@'localhost';
CREATE USER 'hiddifypanel'@'localhost' IDENTIFIED BY '$random_password';
GRANT ALL PRIVILEGES ON hiddifypanel.* TO 'hiddifypanel'@'localhost';
GRANT ALL PRIVILEGES ON *.* TO 'hiddifypanel'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
MYSQL_SCRIPT
        pkill -9 mysqld
        sleep 2
        systemctl start mariadb
        echo "MySQL user created via skip-grant-tables"
    fi
    
    # Verify the user was created
    if mysql -u hiddifypanel -p"$random_password" -e "SELECT 1" 2>/dev/null; then
        echo "SUCCESS: MySQL user 'hiddifypanel' verified!"
    else
        echo "WARNING: Could not verify MySQL user creation"
    fi
    
    echo "MariaDB setup complete."
fi

# Path to the MariaDB configuration file
MARIADB_CONF="/etc/mysql/mariadb.conf.d/50-server.cnf"

# Set bind-address to localhost only
if [ -f "$MARIADB_CONF" ]; then
    if ! grep -q "^[^#]*bind-address\s*=\s*127.0.0.1" "$MARIADB_CONF"; then
        if grep -q "^#\+bind-address" "$MARIADB_CONF"; then
            sed -i "s/^#\+bind-address\s*=\s*[0-9.]*/bind-address = 127.0.0.1/" "$MARIADB_CONF"
        else
            sed -i "/\[mysqld\]/a bind-address = 127.0.0.1" "$MARIADB_CONF" 2>/dev/null || true
        fi
        echo "bind-address set to 127.0.0.1 in $MARIADB_CONF"
        systemctl restart mariadb
    fi
fi

systemctl start mariadb