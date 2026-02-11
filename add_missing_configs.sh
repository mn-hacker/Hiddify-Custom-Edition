#!/bin/bash

cd /opt/hiddify-manager || exit

echo "Attempting to fix configurations via Python environment..."

# Find app.cfg
if [ -f "/opt/hiddify-manager/hiddify-panel/app.cfg" ]; then
    export HIDDIFY_CFG_PATH="/opt/hiddify-manager/hiddify-panel/app.cfg"
elif [ -f "hiddify-panel/app.cfg" ]; then
    export HIDDIFY_CFG_PATH="$(pwd)/hiddify-panel/app.cfg"
else
    # Fallback search
    export HIDDIFY_CFG_PATH=$(find . -name app.cfg | head -n 1)
    if [ -n "$HIDDIFY_CFG_PATH" ]; then
        export HIDDIFY_CFG_PATH="$(realpath $HIDDIFY_CFG_PATH)"
    fi
fi

if [ -z "$HIDDIFY_CFG_PATH" ]; then
    echo "Warning: Could not find app.cfg. Alchemy might fail."
else
    echo "Using config: $HIDDIFY_CFG_PATH"
fi

# 1. Create the python script
cat <<EOF > /opt/hiddify-manager/add_configs.py
import sys
import os
import sqlite3

# Try to use sqlalchemy if available, else sqlite fallback
try:
    from hiddifypanel import create_app
    from hiddifypanel.database import db
    from hiddifypanel.models import ConfigEnum, StrConfig, BoolConfig, hconfig, set_hconfig
    from hiddifypanel.panel.init_db import add_config_if_not_exist

    app = create_app()
    with app.app_context():
        print(f"DB URI: {app.config.get('SQLALCHEMY_DATABASE_URI')}")
        print("Using SQLAlchemy connection...")
        add_config_if_not_exist(ConfigEnum.use_glass_theme, False)
        add_config_if_not_exist(ConfigEnum.ech_enable, False)
        add_config_if_not_exist(ConfigEnum.ech_config, "")
        db.session.commit()
        print("Database updated via SQLAlchemy.")
except Exception as e:
    print(f"SQLAlchemy method failed: {e}")
    print("Falling back to direct SQLite...")
    
    # Fallback to sqlite if module loading fails
    # Find db path
    db_paths = [
        "/opt/hiddify-manager/hiddify-panel/hiddifypanel.db",
        "/opt/hiddify-manager/hiddifypanel.db"
    ]
    
    conn = None
    for path in db_paths:
        if os.path.exists(path):
            conn = sqlite3.connect(path)
            print(f"Connected to SQLite: {path}")
            break
            
    if not conn:
        print("Could not find SQLite database.")
        sys.exit(1)
        
    c = conn.cursor()
    try:
        c.execute("INSERT OR IGNORE INTO bool_config (child_id, key, value) VALUES (0, 'use_glass_theme', 0)")
        c.execute("INSERT OR IGNORE INTO bool_config (child_id, key, value) VALUES (0, 'ech_enable', 0)")
        c.execute("INSERT OR IGNORE INTO str_config (child_id, key, value) VALUES (0, 'ech_config', '')")
        conn.commit()
        print("Database updated via SQLite.")
    except Exception as ie:
        print(f"SQLite error: {ie}")
    finally:
        conn.close()

EOF

# 2. Try to find and use the correct python
PYTHON_CMD="python3"

if [ -f "/opt/hiddify-manager/.venv/bin/python" ]; then
    PYTHON_CMD="/opt/hiddify-manager/.venv/bin/python"
elif [ -f "/opt/hiddify-manager/.venv313/bin/python" ]; then
    PYTHON_CMD="/opt/hiddify-manager/.venv313/bin/python"
fi

echo "Using Python: $PYTHON_CMD"

# 3. Run it
$PYTHON_CMD /opt/hiddify-manager/add_configs.py

# 4. Clean up
rm /opt/hiddify-manager/add_configs.py
echo "Finished."
