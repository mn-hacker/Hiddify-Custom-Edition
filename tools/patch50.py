"""
watashi v12.2.50 - the core layer.

what i found by reading the real files:

1. common/package_manager.sh moved the downloaded file over the live binary
   BEFORE it checked the sha256, and deleted that file on a mismatch. a bad
   mirror or a half download therefore destroyed a working core.
2. the lock lookup was `grep "^name|version" | grep arch`, which matches
   1.13.0 against 1.13.0.h10 and can return two lines at once.
3. get_latest_version was called without an arch by set_installed_version, and
   that function printed "for $arch" while $arch was never set there.
4. singbox/install.sh used `if [ -d "sing-box-"* ]`, which is a bash error as
   soon as the glob matches more than one directory.
5. both add_version.sh files asked for asset names that do not exist in the
   releases, so pinning a new version downloaded a 404 page.
6. xray/install.sh ran `rm -rf bin/*` before it knew the new archive was even
   usable, and re-downloaded the two ~10 MB geo files on every single install.
7. nothing anywhere kept the previous binary, so a bad release left a dead
   service and no way back.

what this patch does: adds common/core_registry.conf and
common/core_manager.sh (fetch, verify, stage, probe, activate, roll back,
prune) and fixes the six items above in place.
"""

import os
import shutil
import subprocess

SRC = "/data/state/src3/"
M = "/data/state/fixm50/"
W = "/data/w/"
MARK = "v12.2.50"
fails = []


def bring(rel):
    dst = M + rel
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    if not os.path.exists(dst):
        shutil.copy2(SRC + rel, dst)
    return dst


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


def check(rel, want=True):
    p = M + rel
    r = subprocess.run(["bash", "-n", p], capture_output=True, text=True)
    if r.returncode != 0:
        fails.append("bash -n %s: %s" % (rel, r.stderr.strip()[:160]))
    if want and MARK not in load(rel):
        fails.append("no marker in " + rel)


# ---------------------------------------------------------------- new files
os.makedirs(M + "common", exist_ok=True)
shutil.copy2(W + "cm50_core_manager.sh", M + "common/core_manager.sh")
shutil.copy2(W + "cm50_registry.conf", M + "common/core_registry.conf")
check("common/core_manager.sh")
if MARK not in open(M + "common/core_registry.conf").read():
    fails.append("no marker in the registry")

# ------------------------------------------------------- 1. package_manager
rel = "common/package_manager.sh"
bring(rel)
back(rel)
b = load(rel)

if MARK not in b:
    b = swap(
        b,
        'generate_hash() {\n',
        "# watashi " + MARK + ": one place that knows the architecture name, so no\n"
        "# caller has to guess it or leave it empty.\n"
        "detect_arch() {\n"
        '    case "$(uname -m)" in\n'
        '    x86_64 | amd64) echo "amd64" ;;\n'
        '    aarch64 | arm64) echo "arm64" ;;\n'
        '    *) echo "" ;;\n'
        "    esac\n"
        "}\n\n"
        "generate_hash() {\n",
        "detect_arch helper",
    )

    b = swap(
        b,
        '    entry=$(grep "^$package_name|$requested_version" "$PACKAGES_LOCK" | grep "$arch")\n',
        "    # watashi " + MARK + ": name, version and arch are whole columns, and only\n"
        "    # one line may come out. the old grep matched 1.13.0 against 1.13.0.h10\n"
        "    # and could hand two lines to the read below, which parsed neither.\n"
        '    entry=$(awk -F\'|\' -v n="$package_name" -v v="$requested_version" -v a="$arch" \'$1==n && $2==v && $3==a {print; exit}\' "$PACKAGES_LOCK")\n',
        "exact lock lookup",
    )

    b = swap(
        b,
        '    mv "$tmp_file" "$output_file"\n'
        "\n"
        "    # Verify the hash\n"
        '    local downloaded_hash=$(generate_hash "$output_file")\n'
        '    if [[ "$downloaded_hash" != "$stored_hash" ]]; then\n'
        '        error "Hash mismatch for $output_file. Expected $stored_hash, got $downloaded_hash."\n'
        '        rm "$output_file"\n'
        "        return 4\n"
        "    fi\n",
        "    # watashi " + MARK + ": verify first, move second. the old order copied an\n"
        "    # unverified download over the live binary and then deleted it when the\n"
        "    # hash did not match, which left the service with no binary at all.\n"
        '    local downloaded_hash=$(generate_hash "$tmp_file")\n'
        '    if [[ "$downloaded_hash" != "$stored_hash" ]]; then\n'
        '        error "Hash mismatch for $url. Expected $stored_hash, got $downloaded_hash. $output_file was left untouched."\n'
        '        rm -f "$tmp_file"\n'
        "        return 4\n"
        "    fi\n"
        "\n"
        "    # keep the file that works, so there is always something to go back to\n"
        '    if [[ -f "$output_file" ]]; then\n'
        '        cp -f "$output_file" "$output_file.previous" 2>/dev/null || true\n'
        "    fi\n"
        '    mv "$tmp_file" "$output_file"\n',
        "verify before move",
    )

    b = swap(
        b,
        '        entry=$(grep "^$package_name" "$PACKAGES_LOCK" | grep "$arch" | sort -t\'|\' -k2.1V | tail -n 1)\n',
        '        if [[ -z "$arch" ]]; then\n'
        "            arch=$(detect_arch)\n"
        "        fi\n"
        "        # watashi " + MARK + ": whole column match, so xray never picks up a\n"
        "        # sing-box line and the arch is a column instead of a substring.\n"
        '        entry=$(awk -F\'|\' -v n="$package_name" -v a="$arch" \'$1==n && $3==a {print}\' "$PACKAGES_LOCK" | sort -t\'|\' -k2.1V | tail -n 1)\n',
        "exact latest lookup",
    )

    b = swap(
        b,
        "    local package_name=$1\n"
        "    local version=$2\n"
        '    if [[ -z "$version" ]]; then\n'
        "        version=$(get_latest_version $package_name)\n"
        "    fi\n",
        "    local package_name=$1\n"
        "    local version=$2\n"
        "    # watashi " + MARK + ": $arch used to be unset in this function, so the\n"
        "    # message lied and the fallback asked for an arch-blind latest version.\n"
        "    local arch=${3:-$(detect_arch)}\n"
        '    if [[ -z "$version" ]]; then\n'
        '        version=$(get_latest_version "$package_name" "$arch")\n'
        "    fi\n",
        "arch aware set-installed",
    )

    b = swap(
        b,
        "    set-installed)\n" '        set_installed_version "$2" "$3"\n',
        "    set-installed)\n" '        set_installed_version "$2" "$3" "$4"\n',
        "set-installed cli",
    )
    save(rel, b)
check(rel)

print("stage 1 done, failures so far: %d %s" % (len(fails), fails))
