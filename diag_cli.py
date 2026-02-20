import os
import subprocess
import time
import urllib.request
import json

print("--- Hiddify CLI Diagnostic Tool ---")

cli_dir = "/opt/hiddify-manager/other/hiddify-cli"
env_file = os.path.join(cli_dir, ".env")
bin_path = os.path.join(cli_dir, "hiddify-cli")
conf_path = os.path.join(cli_dir, "h_client_config.json")

log_path = "/opt/hiddify-manager/log/diag_cli.log"

if not os.path.exists(bin_path):
    print("Error: hiddify-cli binary not found at", bin_path)
    exit(1)

sub_link = ""
if os.path.exists(env_file):
    with open(env_file, "r") as f:
        for line in f:
            if line.startswith("SUB_LINK="):
                sub_link = line.strip().split("=", 1)[1]
                break

if not sub_link:
    print("Error: SUB_LINK not found in .env")
    exit(1)

print(f"Loaded SUB_LINK: {sub_link}")

# Step 1: Let's check what the panel is actually returning in the subscription
print("\n[Diagnostic Step 1] Validating Subscription URL content...")
try:
    req = urllib.request.Request(sub_link, headers={'User-Agent': 'hiddify-cli'})
    with urllib.request.urlopen(req) as response:
        content = response.read().decode('utf-8')
        try:
            json_data = json.loads(content)
            print("✅ Subscription link returned valid JSON config.")
            print(f"   Config keys found: {list(json_data.keys())}")
            
            # Let's save a copy for deeper investigation if needed
            with open("/opt/hiddify-manager/log/sub_config_debug.json", "w") as f:
                f.write(content)
                
        except json.JSONDecodeError:
            print("❌ Subscription link returned INVALID JSON text. This will crash the client.")
except urllib.error.URLError as e:
    print(f"❌ Failed to reach the panel to get config: {e.reason}")

# Step 2: Attempting to run the binary exactly like the service does
print("\n[Diagnostic Step 2] Running hiddify-cli (Timeout 8s)...")
try:
    process = subprocess.Popen(
        [bin_path, "run", "-c", sub_link, "-d", conf_path],
        cwd=cli_dir,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True
    )
    
    time.sleep(8)
    
    if process.poll() is not None:
        output = process.stdout.read()
        print("❌ hiddify-cli crashed or exited early.")
        print(output)
        
        with open(log_path, "w") as f:
            f.write(output)
        print(f"\nSaved detailed crash output to {log_path}")
    else:
        print("✅ hiddify-cli is successfully running without immediate crash!")
        process.terminate()
        
except Exception as e:
    print("Failed to run hiddify-cli:", e)
