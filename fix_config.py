import sys
import os

# Set path to verify imports
sys.path.append(os.getcwd() + "\\hiddify-panel\\src")

from hiddifypanel import create_app
from hiddifypanel.database import db
from hiddifypanel.models import ConfigEnum, StrConfig, BoolConfig, hconfig, set_hconfig, Child
from hiddifypanel.panel.init_db import add_config_if_not_exist

app = create_app()

with app.app_context():
    print("Checking and fixing missing configurations...")
    
    # configs to add
    configs = [
        (ConfigEnum.use_glass_theme, False),
        (ConfigEnum.ech_enable, False),
        (ConfigEnum.ech_config, "")
    ]
    
    for key, val in configs:
        exists = hconfig(key)
        if exists is None:
            print(f"Adding missing config: {key} = {val}")
            add_config_if_not_exist(key, val)
        else:
            print(f"Config {key} already exists with value: {exists}")
            
    # Commit changes
    try:
        db.session.commit()
        print("Database updated successfully.")
    except Exception as e:
        print(f"Error updating database: {e}")
        db.session.rollback()
