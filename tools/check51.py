"""v12.2.51 checks, part 1: the bumper and the root door (commander)."""

import hashlib
import os
import shutil
import subprocess
import sys
import zipfile

sys.path.insert(0, "/data/w")
import w50env as W

fails = []


def t(ok, label, extra=""):
    if not W.say(ok, label, extra):
        fails.append(label)


H = W.H
M51 = "/data/state/fixm51/"
STUB = "/tmp/w51stub"
BUMP = "bash common/bump_cores.sh"
PAD = 120000


def sha(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()


def big_xray(version, asset, ok=True):
    """A release-sized zip with a working (or broken) xray inside."""
    body = '#!/bin/bash\necho "Xray version %s"\n' % version
    if not ok:
        body = "#!/bin/bash\nexit 1\n"
    path = W.SRV + "/" + asset
    with zipfile.ZipFile(path, "w") as z:
        z.writestr("xray", body)
        z.writestr("geosite.dat", "x" * PAD)
        z.writestr("pad.bin", os.urandom(PAD).hex())
    return path


def stubs():
    os.makedirs(STUB, exist_ok=True)
    open(STUB + "/strenum.py", "w").write(
        "from enum import Enum\n\n\nclass StrEnum(str, Enum):\n    pass\n"
    )


def sh(cmd, cwd=H, env=None):
    return W.sh(cmd, env=env, cwd=cwd)


W.build()
stubs()
for rel in ("common/bump_cores.sh", "common/commander.py"):
    shutil.copy2(M51 + rel, H + "/" + rel)
W.make_singbox("1.13.0.h10")
big_xray("26.3.27", "Xray-linux-64.zip")
big_xray("26.3.27", "Xray-linux-arm64-v8a.zip")
ROWS = [
    ("singbox", "1.13.0.h10", "amd64", "sing-box-1.13.0.h10-linux-amd64.tar.gz"),
    ("xray", "26.3.27", "amd64", "Xray-linux-64.zip"),
]
W.lock(ROWS)
W.latest_json("XTLS/Xray-core", "v26.7.28")
W.latest_json("mn-hacker/Hiddify-Custom-SingBox", "v1.13.19")

print("-- 1. the bumper can say what is old")
rc, out = sh(BUMP + " check")
t("CORE" in out and "PINNED" in out and "NEWEST" in out, "check prints a table", out.strip().splitlines()[0][:60] if out.strip() else "")
t("xray" in out and "26.3.27" in out, "it shows what is pinned today")
t("26.7.28" in out, "and what the vendor has now", [l for l in out.splitlines() if l.startswith("xray")][:1])
rc, out = sh(BUMP)
t(rc != 0 and "usage:" in out, "a bare call explains itself", out.strip()[:60])

print("-- 2. pinning a new release writes a real hash")
big_xray("26.7.28", "Xray-linux-64.zip")
big_xray("26.7.28", "Xray-linux-arm64-v8a.zip")
W.reset_log()
rc, out = sh(BUMP + " pin xray 26.7.28")
lock = open(H + "/common/packages.lock").read()
t(rc == 0, "the pin ends well", out.strip()[-70:])
t("xray|26.7.28|amd64|" in lock, "the amd64 line is written")
t("xray|26.7.28|arm64|" in lock, "the arm64 line is written")
want = sha(W.SRV + "/Xray-linux-64.zip")
t(want in lock, "the hash in the lock is the hash of the file", want[:16])
t("releases/download/v26.7.28/Xray-linux-64.zip" in lock, "the url points at the real asset")
rc, out2 = sh(BUMP + " pin xray 26.7.28")
t("already pinned" in out2, "pinning twice does nothing", out2.strip()[-60:])
t(open(H + "/common/packages.lock").read().count("xray|26.7.28|amd64|") == 1, "and it does not write the line again")

print("-- 3. a 404 page is never pinned")
open(W.SRV + "/Xray-linux-64.zip", "w").write("<!DOCTYPE html><html>Not Found</html>")
rc, out = sh(BUMP + " pin xray 26.9.99")
lock = open(H + "/common/packages.lock").read()
t(rc != 0, "the pin fails", out.strip()[-70:])
t("web page" in out or "not a release" in out, "and it says what came back instead")
t("xray|26.9.99" not in lock, "nothing was pinned")
open(W.SRV + "/Xray-linux-64.zip", "w").write("tiny")
rc, out = sh(BUMP + " pin xray 26.9.98")
t("that is not a release" in out, "a four byte answer is refused too", out.strip()[-60:])
t("xray|26.9.98" not in open(H + "/common/packages.lock").read(), "still nothing pinned")
open(W.T + "/fail_Xray-linux-64.zip", "w").close()
rc, out = sh(BUMP + " pin xray 26.9.97")
t(rc != 0 and "could not download" in out, "a dead download is reported", out.strip()[-60:])
os.remove(W.T + "/fail_Xray-linux-64.zip")

print("-- 4. tested is a deliberate mark, not a guess")
rc, out = sh(BUMP + " mark-tested xray 26.9.96")
t(rc != 0 and "is not pinned yet" in out, "an unpinned version cannot be called tested", out.strip()[:70])
rc, out = sh(BUMP + " mark-tested xray 26.7.28")
reg = open(H + "/common/core_registry.conf").read()
t(rc == 0, "the mark goes through", out.strip()[-60:])
xrow = [l for l in reg.splitlines() if l.startswith("xray|")][0]
t(xrow.split("|")[9] == "26.7.28", "the registry now says tested up to 26.7.28", xrow.split("|")[9])
t(len(xrow.split("|")) == 10, "and the row still has all of its fields", len(xrow.split("|")))
rc, out = sh("bash common/core_manager.sh tested xray")
t(out.strip() == "26.7.28", "the core manager reads the same thing", out.strip())
t(len(reg.splitlines()) == len(open(M51 + "common/core_registry.conf").read().splitlines()) if os.path.exists(M51 + "common/core_registry.conf") else True, "no row was lost")

print("-- 5. the root door only opens for real cores")
env = {"PYTHONPATH": STUB}
big_xray("26.7.28", "Xray-linux-64.zip")
W.lock(ROWS)
rc, out = sh(BUMP + " pin xray 26.7.28")
W.reset_log()
rc, out = sh("python3 common/commander.py core --action upgrade --name xray", env=env)
t(rc == 0, "a real request goes through", out.strip()[-70:])
t(os.path.exists(H + "/xray/bin/xray"), "and the core is installed by it")
rc, ver = sh('"%s/xray/bin/xray" version' % H)
t("26.7.28" in ver, "the version the vendor has is the one installed", ver.strip())
for bad, label in (
    ("--action delete --name xray", "a made up action"),
    ("--action install --name 'xray;rm -rf /'", "a name with a shell command in it"),
    ("--action install --name xray --version '$(id)'", "a version with a shell command in it"),
    ("--action install --name ../../etc/passwd", "a name that walks out of the tree"),
):
    rc, out = sh("python3 common/commander.py core " + bad, env=env)
    t(rc != 0, "%s is refused" % label, out.strip().splitlines()[-1][:60] if out.strip() else "")

print("-- 6. the panel asks through the commander, never the shell")
admin = open(M51 + "hiddify-panel/src/hiddifypanel/panel/admin/CoreAdmin.py").read()
t("commander(Command.core" in admin, "the page uses the commander for changes")
t("shell=True" not in admin, "no shell is ever asked to parse a string")
run_c = open(M51 + "hiddify-panel/src/hiddifypanel/panel/run_commander.py").read()
t("core = 'core'" in run_c, "run_commander knows the command")
t("'--action', action, '--name', name" in run_c, "and passes it as separate words")
cmd = open(M51 + "common/commander.py").read()
t("WS_CORE_ACTIONS" in cmd and "is_core_name_valid" in cmd, "the root side validates on its own")
t("['bash', Command.core.value, action, name]" in cmd, "and calls the manager as a list of words")

print("FAILURES: %d %s" % (len(fails), fails))
