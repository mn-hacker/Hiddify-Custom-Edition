
import sys
import os
import time
import redis
import json
from datetime import datetime

# Context setup
sys.path.append("/opt/hiddify-manager/hiddify-panel/src/")
os.environ['HIDDIFY_CFG_PATH'] = '/opt/hiddify-manager/hiddify-panel/app.cfg'

from hiddifypanel import create_app
from hiddifypanel.database import db
from hiddifypanel.models import *
from hiddifypanel.panel import connection_limit

try:
    app = create_app()
except Exception:
    from flask import Flask
    app = Flask(__name__)
    app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:////opt/hiddify-manager/hiddify-panel/hiddifypanel.db'
    app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
    from hiddifypanel.database import db
    db.init_app(app)

def test_features():
    with app.app_context():
        print("--- Hiddify Feature Verification ---")
        
        # 1. Check Configs
        print("\n[1] Checking Configurations:")
        configs = {
            "Connection Limit": ConfigEnum.user_limit_enable,
            "Access Log": ConfigEnum.access_log_enable,
            "Telegram Bot": ConfigEnum.telegram_enable,
            "Block Ads": ConfigEnum.block_ads_enable
        }
        
        # Store original state
        original_states = {}
        for name, key in configs.items():
            val = hconfig(key)
            original_states[key] = val
            status = "ENABLED" if val else "DISABLED"
            print(f"  - {name}: {status} (Value: {val})")

        # 2. Test Connection Tracking (Monitoring & Limit)
        print("\n[2] Testing Connection Tracking (Monitoring):")
        
        # Temporarily enable Connection Limit for testing
        print("  > Auto-enabling Connection Limit for 20 seconds to test logic...")
        set_hconfig(ConfigEnum.user_limit_enable, True)
        db.session.commit()
        
        try:
            # Find a user
            user = User.query.first()
            if not user:
                print("  Failed: No users found to test.")
                return

            uuid = user.uuid
            fake_ip = "11.22.33.44"
            print(f"  - Testing with User: {user.name} ({uuid})")
            print(f"  - Simulating connection from IP: {fake_ip}")

            # Find active log file
            log_files = [p for p in connection_limit.ACCESS_LOG_PATHS if os.path.exists(p)]
            if not log_files:
                # Create a dummy log file if none exist
                target_log = "/opt/hiddify-manager/log/test_access.log"
                print(f"  - No real logs found. Creating dummy log: {target_log}")
                # Add to path list temporarily for the script (this won't affect the real app reading it unless we monkeypatch, 
                # but connection_limit module is imported. We need to be careful.)
                # Actually, connection_limit.ACCESS_LOG_PATHS is a list, we can append to it in memory
                connection_limit.ACCESS_LOG_PATHS.append(target_log)
                open(target_log, 'a').close()
            else:
                target_log = log_files[0]
                print(f"  - Writing validation log to: {target_log}")

            # Append fake log line
            # Format: 2023/10/26 14:30:15 ... from 1.2.3.4:5678 ... email: uuid
            now_str = datetime.now().strftime("%Y/%m/%d %H:%M:%S")
            # Using 'from IP:PORT' format which represents Xray logs and matches regex r'from\s+\[?(\d+\.\d+\.\d+\.\d+)\]?:\d+'
            log_line = f"\n{now_str} [Info] [123] from {fake_ip}:54321 accepted tcp:{fake_ip}:0 email: {uuid}\n"
            
            try:
                with open(target_log, "a") as f:
                    f.write(log_line)
                print("  - Log line written successfully.")
            except Exception as e:
                print(f"  - Error writing log: {e}")
                
            print("  - Waiting 10 seconds for processor to pick it up...")
            
            # Manually run the check function to avoid waiting for Cron/Celery
            # This ensures we test the LOGIC, not the scheduler
            try:
                print("  > Triggering check_connection_limits() manually...")
                res = connection_limit.check_connection_limits()
                print(f"  > Function Result: {res}")
            except Exception as e:
                print(f"  > Manual trigger failed: {e}")

            time.sleep(2)

            # Check Redis
            try:
                r = connection_limit.get_redis()
                if not r:
                     print("  - Error: Redis client not available.")
                else:
                    # Check if IP is tracked
                    user_key = connection_limit.USER_IPS_KEY.format(uuid=uuid)
                    is_tracked = r.zscore(user_key, fake_ip)
                    
                    if is_tracked:
                        print("  [SUCCESS] Connection Tracking is WORKING!")
                        print(f"  - IP {fake_ip} found in Redis for user {user.name}")
                    else:
                        print("  [FAIL] Connection Tracking did NOT pick up the IP.")
            except Exception as e:
                 print(f"  - Error checking Redis: {e}")

        finally:
            # Revert config
            print(f"  > Reverting Connection Limit to: {original_states[ConfigEnum.user_limit_enable]}")
            set_hconfig(ConfigEnum.user_limit_enable, original_states[ConfigEnum.user_limit_enable])
            db.session.commit()

        # 3. Telegram Bot Check
        print("\n[3] Telegram Bot Status:")
        if hconfig(ConfigEnum.telegram_enable):
            token = hconfig(ConfigEnum.telegram_bot_token)
            if token and len(token) > 10:
                 print("  [SUCCESS] Bot Token is present.")
            else:
                 print("  [FAIL] Bot Token is missing or invalid.")
        else:
             print("  - Telegram Bot is DISABLED (Enable in panel to use).")

if __name__ == "__main__":
    test_features()
