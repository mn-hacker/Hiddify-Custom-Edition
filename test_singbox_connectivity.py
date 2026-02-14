
import sys
import os
import json
from unittest.mock import MagicMock

# 1. Setup paths
# Add src to sys.path so we can import hiddifypanel
sys.path.append(os.path.join(os.getcwd(), 'hiddify-panel', 'src'))

# Set dummy env vars
os.environ["REDIS_URI_MAIN"] = "redis://localhost:6379/0"

# 2. Mock external dependencies BEFORE importing hiddifypanel
sys.modules['flask'] = MagicMock()
sys.modules['flask_babel'] = MagicMock()
sys.modules['hiddifypanel.models'] = MagicMock()
sys.modules['redis_cache'] = MagicMock()
sys.modules['redis'] = MagicMock()
sys.modules['flask_classful'] = MagicMock()
sys.modules['dotenv'] = MagicMock()
sys.modules['user_agents'] = MagicMock()
sys.modules['loguru'] = MagicMock()
sys.modules['yaml'] = MagicMock()
sys.modules['urllib3'] = MagicMock()
sys.modules['requests'] = MagicMock()
sys.modules['click'] = MagicMock()

# Setup Flask mocks
from flask import g, request, render_template

# Mock generic user agent
g.user_agent = {'is_hiddify': False, 'is_hiddify_prefere_xray': False}
request.args.get = MagicMock(return_value="")

# Mock render_template to return a valid JSON structure for base config
# This is crucial because configs_as_json uses it
def mock_render_template(template_name, **kwargs):
    if 'base_singbox_config' in template_name:
        return '{"log": {}, "dns": {"rules": [{"domain": []}]}, "inbounds": [], "outbounds": [], "route": {"rules": []}}'
    return "{}"
render_template.side_effect = mock_render_template

# 3. Import the target module
# We let hiddifypanel.hutils import naturally.
# However, we must mock hiddifypanel.hutils.proxy.xrayjson BEFORE it is imported by singbox
# to avoid needing the actual XRay logic.

# Create a mock for xrayjson
xrayjson_mock = MagicMock()
sys.modules['hiddifypanel.hutils.proxy.xrayjson'] = xrayjson_mock
# Define to_xray on the mock
xrayjson_mock.to_xray.return_value = {"tag": "mock-xray-outbound"}

# Now import singbox
try:
    from hiddifypanel.hutils.proxy import singbox
    from hiddifypanel.models import ProxyTransport, ProxyProto, ProxyL3
except ImportError as e:
    print(f"Import Error: {e}")
    sys.exit(1)

# Helper to create dummy proxy dict
def create_proxy(name, proto, transport, l3, port=443, **kwargs):
    p = {
        "name": name,
        "proto": proto,
        "transport": transport,
        "l3": l3,
        "port": port,
        "server": "example.com",
        "uuid": "uuid-1234",
        "cipher": "aes-256-gcm",
        "password": "password",
        "sni": "sni.example.com",
        "alpn": "h3",
        "allow_insecure": False,
        "mode": "Direct",
        "path": "/",
        "host": "host.example.com",
        "extra_info": "",
        "dbdomain": MagicMock(id=1),
        "params": {}
    }
    p.update(kwargs)
    return p

# Test function
def test_configs():
    print("Testing SingBox Config Generation...")
    
    # Test 1: VLESS raw TCP (Vision)
    p1 = create_proxy("VLESS-TCP", ProxyProto.vless, "tcp", ProxyL3.tls)
    c1 = singbox.to_singbox(p1)
    print("\n--- VLESS TCP ---")
    print(json.dumps(c1, indent=2))

    # Test 2: VMess WS
    p2 = create_proxy("VMess-WS", ProxyProto.vmess, "ws", ProxyL3.tls)
    c2 = singbox.to_singbox(p2)
    print("\n--- VMess WS ---")
    print(json.dumps(c2, indent=2))
    
    # Test 3: XHTTP
    p3 = create_proxy("VLESS-XHTTP", ProxyProto.vless, "xhttp", ProxyL3.tls, # Using string "xhttp" if enum fails
                      xhttp_mode="auto", params={"headers": {"User-Agent": "test"}})
    c3 = singbox.to_singbox(p3)
    print("\n--- VLESS XHTTP ---")
    print(json.dumps(c3, indent=2))
    
    # Test 4: Shadowsocks
    p4 = create_proxy("SS-New", ProxyProto.ss, "tcp", ProxyL3.tls)
    c4 = singbox.to_singbox(p4)
    print("\n--- SS ---")
    print(json.dumps(c4, indent=2))

if __name__ == "__main__":
    test_configs()
