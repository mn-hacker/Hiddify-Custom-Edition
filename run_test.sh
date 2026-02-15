#!/bin/bash
cd /opt/hiddify-manager/

# Try to find the correct python venv
PYTHON_CMD="python3"

if [ -f .venv313/bin/python3 ]; then
    PYTHON_CMD=".venv313/bin/python3"
elif [ -f .venv/bin/python3 ]; then
    PYTHON_CMD=".venv/bin/python3"
elif [ -f hiddify-panel/.venv/bin/python3 ]; then
    PYTHON_CMD="hiddify-panel/.venv/bin/python3"
fi

echo "Using Python: $PYTHON_CMD"
$PYTHON_CMD test_features.py
