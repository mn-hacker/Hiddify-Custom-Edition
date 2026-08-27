"""test bench for v12.2.50. builds a fake /opt/hiddify-manager with fake
curl, wget, systemctl and fake core releases, so the core manager can be run
end to end without a network and without touching a real service."""

import hashlib
import json
import os
import shutil
import subprocess
import tarfile
import zipfile

M = "/data/state/fixm50/"
H = "/opt/hiddify-manager"
BIN = "/tmp/w50bin"
T = "/tmp/w50"
SRV = T + "/files"
API = T + "/api"
LOG = T + "/calls.log"

FILES = [
    "common/core_manager.sh",
    "common/core_registry.conf",
    "common/package_manager.sh",
    "singbox/install.sh",
    "singbox/add_version.sh",
    "xray/install.sh",
    "xray/add_version.sh",
]

UTILS = """#!/bin/bash
function error() { echo "ERROR: $*" >&2; }
function warning() { echo "WARNING: $*"; }
function is_installed() { [ -x "$1" ]; }
function install_package() { echo "install_package $*" >>"$WS_T_LOG"; }
function remove_package() { :; }
function hconfig() { echo "${2:-}"; }
"""

CURL = """#!/bin/bash
# fake curl: serves /tmp/w50/api and /tmp/w50/files, no network
out=""
url=""
while [ $# -gt 0 ]; do
    case "$1" in
    -o)
        out="$2"
        shift 2
        ;;
    --connect-timeout)
        shift 2
        ;;
    -*) shift ;;
    *)
        url="$1"
        shift
        ;;
    esac
done
echo "CURL $url" >>"$WS_T_LOG"
src=""
case "$url" in
*api.github.com*releases/latest*)
    repo=$(echo "$url" | sed 's#.*/repos/##; s#/releases/latest##; s#/#_#g')
    src="/tmp/w50/api/$repo.json"
    ;;
*)
    src="/tmp/w50/files/$(basename "$url")"
    ;;
esac
if [ -f "/tmp/w50/fail_$(basename "$url")" ] || [ ! -f "$src" ]; then
    echo "CURL-FAIL $url" >>"$WS_T_LOG"
    exit 22
fi
if [ -n "$out" ]; then cp -f "$src" "$out"; else cat "$src"; fi
"""

WGET = """#!/bin/bash
out=""
url=""
while [ $# -gt 0 ]; do
    case "$1" in
    -O)
        out="$2"
        shift 2
        ;;
    -*) shift ;;
    *)
        url="$1"
        shift
        ;;
    esac
done
echo "WGET $url" >>"$WS_T_LOG"
src="/tmp/w50/files/$(basename "$url")"
if [ ! -f "$src" ]; then exit 8; fi
if [ -n "$out" ]; then cp -f "$src" "$out"; else cat "$src"; fi
"""

SYSTEMCTL = """#!/bin/bash
echo "SYSTEMCTL $*" >>"$WS_T_LOG"
if [ "$1" = "is-active" ]; then
    unit="${@: -1}"
    [ -f "/tmp/w50/down_${unit%.service}" ] && exit 3
    exit 0
fi
exit 0
"""


def _w(path, body, mode=0o755):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", newline="\n") as f:
        f.write(body)
    os.chmod(path, mode)


def core_script(name, version, ok=True):
    if ok:
        return (
            "#!/bin/bash\n"
            'if [ "$1" = "version" ] || [ "$1" = "--version" ]; then\n'
            '    echo "%s version %s"\n'
            "    exit 0\n"
            "fi\n"
            "exit 0\n"
        ) % (name, version)
    return "#!/bin/bash\nexit 1\n"


def make_singbox(version, ok=True, arch="amd64"):
    """a release shaped like the real one: one directory holding the binary"""
    d = T + "/build/sing-box-%s-linux-%s" % (version, arch)
    shutil.rmtree(T + "/build", ignore_errors=True)
    _w(d + "/sing-box", core_script("sing-box", version, ok))
    _w(d + "/LICENSE", "x\n", 0o644)
    out = "%s/sing-box-%s-linux-%s.tar.gz" % (SRV, version, arch)
    os.makedirs(SRV, exist_ok=True)
    with tarfile.open(out, "w:gz") as t:
        t.add(d, arcname=os.path.basename(d))
    return out


def make_xray(version, ok=True, arch="amd64"):
    """the xray release is a flat zip"""
    d = T + "/buildx"
    shutil.rmtree(d, ignore_errors=True)
    _w(d + "/xray", core_script("Xray", version, ok))
    _w(d + "/geosite.dat", "from the archive\n", 0o644)
    name = "Xray-linux-64.zip" if arch == "amd64" else "Xray-linux-arm64-v8a.zip"
    out = SRV + "/" + name
    os.makedirs(SRV, exist_ok=True)
    with zipfile.ZipFile(out, "w") as z:
        z.write(d + "/xray", "xray")
        z.write(d + "/geosite.dat", "geosite.dat")
    return out


def make_plain(name, body="binary\n"):
    os.makedirs(SRV, exist_ok=True)
    _w(SRV + "/" + name, body)
    return SRV + "/" + name


def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        h.update(f.read())
    return h.hexdigest()


def latest_json(repo, tag):
    os.makedirs(API, exist_ok=True)
    _w(API + "/" + repo.replace("/", "_") + ".json", json.dumps({"tag_name": tag}), 0o644)


URLS = {
    "singbox": "https://github.com/mn-hacker/Hiddify-Custom-SingBox/releases/download/v%s/%s",
    "xray": "https://github.com/XTLS/Xray-core/releases/download/v%s/%s",
    "mtproxygo": "https://github.com/9seconds/mtg/releases/download/v%s/%s",
    "wgcf": "https://github.com/ViRb3/wgcf/releases/download/v%s/%s",
}


def lock(rows):
    """rows: [(name, version, arch, asset_file_name)] -> real sha256 from disk"""
    lines = []
    for name, version, arch, asset in rows:
        url = URLS[name] % (version, asset)
        lines.append("|".join([name, version, arch, url, sha(SRV + "/" + asset)]))
    _w(H + "/common/packages.lock", "\n".join(lines) + "\n", 0o644)


def build():
    shutil.rmtree(H, ignore_errors=True)
    shutil.rmtree(T, ignore_errors=True)
    for rel in FILES:
        os.makedirs(os.path.dirname(H + "/" + rel), exist_ok=True)
        shutil.copy2(M + rel, H + "/" + rel)
    _w(H + "/common/utils.sh", UTILS, 0o644)
    _w(H + "/common/packages.db", "", 0o644)
    os.makedirs(H + "/log/system", exist_ok=True)
    os.makedirs(H + "/xray/bin", exist_ok=True)
    os.makedirs(H + "/other/telegram/tgo", exist_ok=True)
    os.makedirs(H + "/other/warp/singbox", exist_ok=True)
    os.makedirs(H + "/other/ssh", exist_ok=True)
    os.makedirs(H + "/other/v2ray", exist_ok=True)
    _w(H + "/singbox/hiddify-singbox.service", "[Unit]\n", 0o644)
    _w(H + "/xray/hiddify-xray.service", "[Unit]\n", 0o644)
    _w(BIN + "/curl", CURL)
    _w(BIN + "/wget", WGET)
    _w(BIN + "/systemctl", SYSTEMCTL)
    os.makedirs(SRV, exist_ok=True)
    os.makedirs(API, exist_ok=True)
    reset_log()


def reset_log():
    os.makedirs(T, ignore_errors=True) if False else os.makedirs(T, exist_ok=True)
    open(LOG, "w").close()


def calls():
    try:
        return open(LOG).read()
    except IOError:
        return ""


def down(unit, yes=True):
    p = T + "/down_" + unit
    if yes:
        _w(p, "x\n", 0o644)
    elif os.path.exists(p):
        os.remove(p)


def fresh():
    """forget every installed version, keep the fake releases"""
    shutil.rmtree(H + "/common/cores", ignore_errors=True)
    for p in (H + "/singbox/sing-box", H + "/xray/bin/xray"):
        if os.path.exists(p):
            os.remove(p)
    for f in os.listdir(T):
        if f.startswith("down_") or f.startswith("fail_"):
            os.remove(T + "/" + f)
    reset_log()


def sh(cmd, env=None, cwd=None):
    e = dict(os.environ)
    e["PATH"] = BIN + ":" + e["PATH"]
    e["WS_T_LOG"] = LOG
    e["WS_ROOT"] = H
    e["CM_GH_API"] = "https://api.github.com"
    e["CM_PROBE_WAIT"] = "0"
    if env:
        e.update(env)
    r = subprocess.run(
        ["bash", "-c", cmd],
        capture_output=True,
        text=True,
        env=e,
        cwd=cwd or H,
        timeout=300,
    )
    return r.returncode, r.stdout + r.stderr


def cm(args, env=None):
    return sh("bash %s/common/core_manager.sh %s" % (H, args), env)


def say(ok, label, extra=""):
    print("%s %-62s %s" % ("OK  " if ok else "BAD ", label, extra))
    return bool(ok)


def body(rel):
    return open(M + rel).read()


def live(text):
    out = []
    for line in text.split("\n"):
        s = line.strip()
        if s.startswith("#"):
            continue
        out.append(line)
    return "\n".join(out)
