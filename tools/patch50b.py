"""watashi v12.2.50 - stage 2: the two core installers and the two pinning
scripts. see patch50.py for the findings."""

import os
import shutil
import subprocess

SRC = "/data/state/src3/"
M = "/data/state/fixm50/"
MARK = "v12.2.50"
fails = []


def bring(rel):
    dst = M + rel
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    if not os.path.exists(dst):
        shutil.copy2(SRC + rel, dst)


def load(rel):
    with open(M + rel, "r", newline="") as f:
        return f.read()


def save(rel, body):
    with open(M + rel, "w", newline="") as f:
        f.write(body)


def back(rel):
    b = M + rel + ".b50"
    if not os.path.exists(b):
        shutil.copy2(M + rel, b)


def swap(body, old, new, label):
    if old not in body:
        fails.append("not found: " + label)
        return body
    return body.replace(old, new, 1)


def check(rel):
    r = subprocess.run(["bash", "-n", M + rel], capture_output=True, text=True)
    if r.returncode != 0:
        fails.append("bash -n %s: %s" % (rel, r.stderr.strip()[:160]))
    if MARK not in load(rel):
        fails.append("no marker in " + rel)


# ------------------------------------------------------- singbox/install.sh
rel = "singbox/install.sh"
bring(rel)
back(rel)
b = load(rel)
if MARK not in b:
    old = (
        "    # Find and copy binary - handle both directory format and flat format\n"
        '    if [ -d "sing-box-"* ]; then\n'
        "        # Directory format (e.g., sing-box-1.8.8-linux-amd64/)\n"
        '        cp -f sing-box-*/sing-box . 2>/dev/null || { echo "ERROR: Failed to copy singbox binary from directory"; exit 2; }\n'
        '    elif [ -f "sing-box" ]; then\n'
    )
    new = (
        "    # watashi " + MARK + ": find the binary by name. `[ -d \"sing-box-\"* ]` is a\n"
        "    # bash error the moment that glob matches more than one directory, and\n"
        "    # the old copy landed on the live binary with no check that it runs.\n"
        "    SB_NEW=$(find . -maxdepth 3 -type f -name sing-box ! -path ./sing-box -print -quit 2>/dev/null)\n"
        '    if [ -n "$SB_NEW" ]; then\n'
        '        cp -f "$SB_NEW" ./sing-box.new || { echo "ERROR: Failed to copy singbox binary"; exit 2; }\n'
        "        chmod +x ./sing-box.new\n"
        "        if ! ./sing-box.new version >/dev/null 2>&1; then\n"
        '            echo "ERROR: the new sing-box binary does not run here, keeping the current one"\n'
        "            rm -f ./sing-box.new\n"
        "            exit 5\n"
        "        fi\n"
        "        if [ -f ./sing-box ]; then\n"
        "            cp -f ./sing-box ./sing-box.previous 2>/dev/null || true\n"
        "        fi\n"
        "        mv -f ./sing-box.new ./sing-box\n"
        '    elif [ -f "sing-box" ]; then\n'
    )
    b = swap(b, old, new, "singbox glob")
    b = swap(
        b,
        "    set_installed_version singbox $version\n",
        '    set_installed_version singbox "$version" "$(detect_arch)"\n',
        "singbox set-installed",
    )
    save(rel, b)
check(rel)

# ---------------------------------------------------------- xray/install.sh
rel = "xray/install.sh"
bring(rel)
back(rel)
b = load(rel)
if MARK not in b:
    old = (
        "    systemctl stop hiddify-xray.service > /dev/null 2>&1 \n"
        "    rm -rf bin/*\n"
        "    install_package unzip \n"
        '    unzip -o sb.zip -d bin/ > /dev/null || { echo "ERROR: Failed to extract xray"; exit 1; }\n'
        "    rm -f sb.zip \n"
    )
    new = (
        "    install_package unzip\n"
        "    # watashi " + MARK + ": unpack beside the live binary and only take over\n"
        "    # when the new one really runs. `rm -rf bin/*` used to throw away the\n"
        "    # working xray and the geo files before anyone knew whether the new\n"
        "    # archive was usable at all.\n"
        "    rm -rf bin/.new\n"
        "    mkdir -p bin/.new\n"
        '    unzip -o sb.zip -d bin/.new > /dev/null || { echo "ERROR: Failed to extract xray"; exit 1; }\n'
        "    rm -f sb.zip\n"
        "    chmod +x bin/.new/xray 2>/dev/null\n"
        "    if ! bin/.new/xray version >/dev/null 2>&1; then\n"
        '        echo "ERROR: the new xray binary does not run here, keeping the current one"\n'
        "        rm -rf bin/.new\n"
        "        exit 1\n"
        "    fi\n"
        "    systemctl stop hiddify-xray.service > /dev/null 2>&1\n"
        "    if [ -f bin/xray ]; then\n"
        "        cp -f bin/xray bin/xray.previous 2>/dev/null || true\n"
        "    fi\n"
        "    cp -f bin/.new/xray bin/xray.new && mv -f bin/xray.new bin/xray\n"
        "    cp -f bin/.new/*.dat bin/ 2>/dev/null || true\n"
        "    rm -rf bin/.new\n"
    )
    b = swap(b, old, new, "xray staged install")
    b = swap(
        b,
        "    set_installed_version xray $version\n",
        '    set_installed_version xray "$version" "$(detect_arch)"\n',
        "xray set-installed",
    )
    old = (
        'echo "Downloading enhanced geo files for adblock..."\n'
        'curl -sL --connect-timeout 10 "${GEO_URL}/geosite.dat" -o bin/geosite.dat || echo "Warning: Failed to download geosite.dat"\n'
        'curl -sL --connect-timeout 10 "${GEO_URL}/geoip.dat" -o bin/geoip.dat || echo "Warning: Failed to download geoip.dat"\n'
    )
    new = (
        "# watashi " + MARK + ": these two files are about 10 MB each and do not change\n"
        "# during a reinstall. fetch them only when they are missing or a week old,\n"
        "# and never let a failed download replace a good file.\n"
        "for geo in geosite.dat geoip.dat; do\n"
        '    if [ -s "bin/$geo" ] && [ -z "$(find bin/$geo -mtime +7 2>/dev/null)" ]; then\n'
        '        echo "$geo is recent, keeping it"\n'
        "        continue\n"
        "    fi\n"
        '    if curl -sL --connect-timeout 10 -o "bin/$geo.new" "${GEO_URL}/$geo" && [ -s "bin/$geo.new" ]; then\n'
        '        mv -f "bin/$geo.new" "bin/$geo"\n'
        '        echo "$geo updated"\n'
        "    else\n"
        '        rm -f "bin/$geo.new"\n'
        '        echo "Warning: Failed to download $geo, keeping the current file"\n'
        "    fi\n"
        "done\n"
    )
    b = swap(b, old, new, "xray geo cache")
    save(rel, b)
check(rel)

# ------------------------------------------------------------- add_version.sh
SB = (
    "#!/bin/bash\n"
    "# watashi " + MARK + ": the asset names here were wrong. the releases carry\n"
    "# sing-box-<version>-linux-<arch>.tar.gz, not sing-box-linux-<arch>.zip, so\n"
    "# every attempt to pin a new version downloaded a 404 page and stored its\n"
    "# hash as if it were a core.\n"
    "latest=$1\n"
    'if [ -z "$latest" ]; then\n'
    '    echo "usage: $0 <version>   e.g. $0 1.13.0.h10"\n'
    "    exit 1\n"
    "fi\n"
    "cd \"$(dirname -- \"$0\")\" || exit 1\n"
    "source ../common/package_manager.sh\n"
    "base=https://github.com/mn-hacker/Hiddify-Custom-SingBox/releases/download/v$latest\n"
    "add_package singbox $latest arm64 $base/sing-box-$latest-linux-arm64.tar.gz\n"
    "add_package singbox $latest amd64 $base/sing-box-$latest-linux-amd64.tar.gz\n"
)
XR = (
    "#!/bin/bash\n"
    "# watashi " + MARK + ": same shape as the sing-box script, with a usage guard so\n"
    "# an empty argument can no longer pin a version called v.\n"
    "latest=$1\n"
    'if [ -z "$latest" ]; then\n'
    '    echo "usage: $0 <version>   e.g. $0 26.7.28"\n'
    "    exit 1\n"
    "fi\n"
    "cd \"$(dirname -- \"$0\")\" || exit 1\n"
    "source ../common/package_manager.sh\n"
    "base=https://github.com/XTLS/Xray-core/releases/download/v$latest\n"
    "add_package xray $latest arm64 $base/Xray-linux-arm64-v8a.zip\n"
    "add_package xray $latest amd64 $base/Xray-linux-64.zip\n"
)
for rel, body in (("singbox/add_version.sh", SB), ("xray/add_version.sh", XR)):
    bring(rel)
    back(rel)
    save(rel, body)
    check(rel)

print("FAILURES: %d %s" % (len(fails), fails))
