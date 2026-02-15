import sys
import os
sys.path.append(os.path.abspath("hiddify-panel/src"))
from hiddifypanel.models import *
from hiddifypanel.panel import hiddify
from hiddifypanel.database import db
from hiddifypanel import create_app

app = create_app()
with app.app_context():
    child_id = 1 # Assuming default child
    
    print(f"Checking keys for Child ID: {child_id}")
    
    keys_to_check = [
        ConfigEnum.telegram_bot_token,
        ConfigEnum.telegram_bot_info,
        ConfigEnum.backup_interval,
        ConfigEnum.notify_expiry_enable,
        ConfigEnum.notify_usage_enable
    ]
    
    for key in keys_to_check:
        if key.type == bool:
            exists = BoolConfig.query.filter_by(key=key, child_id=child_id).first()
        else:
            exists = StrConfig.query.filter_by(key=key, child_id=child_id).first()
            
        print(f"{key.name}: {'FOUND' if exists else 'MISSING'}")
        
    print("\n--- All Missing Keys in telegram_bot category ---")
    bot_cat_keys = [c for c in ConfigEnum if c.category == ConfigCategory.telegram_bot]
    for key in bot_cat_keys:
        if key.type == bool:
            exists = BoolConfig.query.filter_by(key=key, child_id=child_id).first()
        else:
            exists = StrConfig.query.filter_by(key=key, child_id=child_id).first()
        if not exists:
            print(f"MISSING: {key.name}")
