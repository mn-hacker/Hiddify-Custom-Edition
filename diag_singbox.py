import os
import subprocess
import glob

print("--- Hiddify Sing-box Diagnostic Tool ---")

singbox_dir = "/opt/hiddify-manager/singbox"
configs_dir = os.path.join(singbox_dir, "configs")
bin_path = os.path.join(singbox_dir, "sing-box")

if not os.path.exists(bin_path):
    print("Error: sing-box binary not found at", bin_path)
    exit(1)

print("Running manual sing-box config check...")
try:
    result = subprocess.run(
        [bin_path, "check", "-C", configs_dir],
        capture_output=True, text=True
    )
    if result.returncode == 0:
        print("✅ Config check passed! No syntax errors detected.")
    else:
        print("❌ Config check failed with error:")
        print(result.stderr)
        
        # Save error to log
        with open("/opt/hiddify-manager/log/diag_singbox.log", "w") as f:
            f.write(result.stderr)
        print("Error log saved to /opt/hiddify-manager/log/diag_singbox.log")
        
except Exception as e:
    print("Failed to run sing-box check:", e)
