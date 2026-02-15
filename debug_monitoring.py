
import os
import sys
import re
import datetime
import glob
import json
import stat
import pwd
import grp

def get_log_paths():
    if os.name == 'nt':
        return [
            "log.txt",
            "d:/Downloads/Watashi-Manager/log/singbox.log",
        ]
    return [
        "/opt/hiddify-manager/log/singbox.log",
        "/opt/hiddify-manager/log/system/singbox.log",
        "/opt/hiddify-manager/log/xray_access.log",
        "/opt/hiddify-manager/xray/access.log",
        "/opt/hiddify-manager/singbox/singbox.log",
        "/opt/hiddify-manager/singbox/access.log",
        "/var/log/xray/access.log",
        "/var/log/singbox/access.log",
    ]

def check_file_permissions(path):
    try:
        st = os.stat(path)
        mode = oct(st.st_mode)[-3:]
        try:
            owner = pwd.getpwuid(st.st_uid).pw_name
        except:
            owner = str(st.st_uid)
        try:
            group = grp.getgrgid(st.st_gid).gr_name
        except:
            group = str(st.st_gid)
            
        print(f"    Permissions: {mode} ({owner}:{group})")
        
        # Check readability
        if not os.access(path, os.R_OK):
            print("    [ERROR] File is NOT readable by current user!")
        else:
            print("    [OK] File is readable.")
            
    except Exception as e:
        print(f"    [ERROR] Checking permissions: {e}")

def check_logs():
    print("--- Diagnostic: Checking Access Logs & Permissions ---")
    paths = get_log_paths()
    found_any = False
    
    for path in paths:
        if os.path.exists(path):
            found_any = True
            print(f"\n[FOUND] {path}")
            
            # Check permissions (Linux only usually)
            if os.name != 'nt':
                check_file_permissions(path)
            
            try:
                with open(path, 'rb') as f:
                    # Read last 2KB
                    f.seek(0, 2)
                    size = f.tell()
                    f.seek(max(0, size - 4096))
                    content = f.read().decode('utf-8', errors='ignore')
                    
                    lines = content.strip().split('\n')
                    print(f"    Last {len(lines)} lines (sample):")
                    for line in lines[-5:]:
                        print(f"      {line[:100]}...")
                        # Try parsing
                        parse_line(line)
            except Exception as e:
                print(f"    [ERROR] Reading file content: {e}")
        else:
            # print(f"[MISSING] {path}")
            pass

    if not found_any:
        print("\n[WARNING] No log files found in standard locations!")

def parse_line(line):
    # Test SingBox parsing logic
    # Regex 1: Std Singbox/Xray "from ... accepted ..."
    ip_match = re.search(r'from\s+\[?(\d+\.\d+\.\d+\.\d+)\]?:\d+', line)
    if ip_match:
        print(f"        -> Parsed IP (Standard): {ip_match.group(1)}")
    
    # Regex 2: Nobetci/Singbox "IP:port accepted"
    ip_match2 = re.search(r'\[?(\d+\.\d+\.\d+\.\d+)\]?:\d+\s+accepted', line)
    if ip_match2:
        print(f"        -> Parsed IP (Singbox/Nobetci): {ip_match2.group(1)}")

    # Regex 3: Singbox generic "inbound connection from"
    ip_match3 = re.search(r'inbound connection from\s+\[?(\d+\.\d+\.\d+\.\d+)\]?:\d+', line)
    if ip_match3:
        print(f"        -> Parsed IP (Inbound): {ip_match3.group(1)}")

    # UUID Check
    if "email:" in line:
        print("        -> Found 'email:' field")

if __name__ == "__main__":
    check_logs()
