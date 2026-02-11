#!/bin/bash

cd /opt/hiddify-manager || exit

# 1. Update current.json
echo "Updating configuration..."
# Try finding hiddify-panel-cli
if [ -f "/opt/hiddify-manager/common/utils.sh" ]; then
    source /opt/hiddify-manager/common/utils.sh
    if type hiddify-panel-cli &>/dev/null; then
        hiddify-panel-cli all-configs > /opt/hiddify-manager/current.json
    else
        # Fallback if function not available (unlikely)
        /opt/hiddify-manager/.venv313/bin/python -m hiddifypanel all-configs > /opt/hiddify-manager/current.json
    fi
else
    echo "Error: utils.sh not found"
    exit 1
fi

# 2. Render mtg.toml
echo "Rendering mtg.toml..."
cat <<EOF > /opt/hiddify-manager/render_mtg.py
import json
import os
import sys
import base64
from jinja2 import Environment, FileSystemLoader

try:
    with open("/opt/hiddify-manager/current.json") as f:
        configs = json.load(f)
        # Handle empty/missing keys gracefully
        if "chconfigs" in configs:
            configs["chconfigs"] = {int(k): v for k, v in configs["chconfigs"].items()}
            configs["hconfigs"] = configs["chconfigs"].get(0, {})
        else:
            print("Error: Invalid current.json format")
            sys.exit(1)
except Exception as e:
    print(f"Error loading current.json: {e}")
    sys.exit(1)

def b64encode(s):
    if type(s) == str:
        s = s.encode("utf-8")
    return base64.b64encode(s).decode("utf-8")

def hexencode(s):
    return "".join(hex(ord(c))[2:].zfill(2) for c in s)

env = Environment(loader=FileSystemLoader("/"))
env.filters["b64encode"] = b64encode
env.filters["hexencode"] = hexencode

template_path = "/opt/hiddify-manager/other/telegram/tgo/mtg.toml.j2"
output_path = "/opt/hiddify-manager/other/telegram/tgo/mtg.toml"

try:
    template = env.get_template(template_path)
    rendered = template.render(**configs, os=os)
    
    with open(output_path, "w") as f:
        f.write(rendered)
    print(f"Successfully rendered {output_path}")
except Exception as e:
    print(f"Error rendering template: {e}")
    sys.exit(1)
EOF

# Use the correct python
PYTHON_CMD="/opt/hiddify-manager/.venv313/bin/python"
if [ ! -f "$PYTHON_CMD" ]; then
    PYTHON_CMD="/opt/hiddify-manager/.venv/bin/python"
fi

$PYTHON_CMD /opt/hiddify-manager/render_mtg.py

# 3. Install and Run MTProxy
echo "Restarting MTProxy..."
cd /opt/hiddify-manager/other/telegram/tgo
bash install.sh
bash run.sh

echo "Done."
