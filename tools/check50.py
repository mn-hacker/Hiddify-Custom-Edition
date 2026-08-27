"""v12.2.50 checks, part 1: the core manager itself."""

import json
import os
import shutil
import sys

sys.path.insert(0, "/data/w")
import w50env as W

fails = []


def t(ok, label, extra=""):
    if not W.say(ok, label, extra):
        fails.append(label)


def binout(path, arg="version"):
    rc, out = W.sh('"%s" %s' % (path, arg))
    return out.strip()


SB = W.H + "/singbox/sing-box"
ROWS = []

print("-- 1. the registry describes every core we ship")
W.build()
reg = open(W.H + "/common/core_registry.conf").read()
rc, out = W.cm("list")
names = out.split()
t(rc == 0, "the manager lists the cores", str(names))
for name in ("xray", "singbox", "mtproxygo", "wgcf", "ssh-liberty-bridge", "v2ray-plugin"):
    t(name in names, "%s is registered" % name)
t("singbox/sing-box" in reg and "xray/bin/xray" in reg, "the real install paths are used")
t("other/telegram/tgo/mtg" in reg, "mtg points at the tgo folder")
t("other/warp/singbox/wgcf" in reg, "wgcf points at the warp folder")
t("@V@" in reg and "@BIN@" in reg, "the version and binary placeholders are there")

print("-- 2. a fresh install of a pinned core")
W.make_singbox("1.13.0.h10")
W.latest_json("mn-hacker/Hiddify-Custom-SingBox", "v1.13.0.h10")
W.latest_json("XTLS/Xray-core", "v26.7.28")
ROWS.append(("singbox", "1.13.0.h10", "amd64", "sing-box-1.13.0.h10-linux-amd64.tar.gz"))
W.lock(ROWS)
rc, out = W.cm("install singbox")
t(rc == 0, "install singbox ends well", out.strip()[-90:])
t("sha256 verified" in out, "the sha256 is checked before anything moves")
t(os.path.exists(SB), "the binary is in place")
t("1.13.0.h10" in binout(SB), "and it is the version we asked for", binout(SB))
t("SYSTEMCTL restart hiddify-singbox.service" in W.calls(), "the service is restarted")
db = open(W.H + "/common/cores/installed.db").read()
t("singbox|1.13.0.h10" in db, "the installed version is written down", db.strip())
rc, out = W.cm("json")
try:
    data = json.loads(out)
    row = [r for r in data if r["name"] == "singbox"][0]
    t(row["installed"] == "1.13.0.h10" and row["active"] is True, "the panel json is usable", str(row))
except Exception as e:
    t(False, "the panel json is usable", str(e))
rc, out = W.cm("latest xray")
t(out.strip() == "26.7.28", "latest asks the vendor and drops the v", out.strip())

print("-- 3. a tampered download never reaches the live binary")
good = open(SB, "rb").read()
shutil.rmtree(W.H + "/common/cores/singbox/1.13.0.h10")
W.make_singbox("1.13.0.h10", ok=False)  # same name, different bytes, lock unchanged
W.reset_log()
rc, out = W.cm("install singbox")
t(rc == 3, "the install stops on a hash mismatch", "rc=%d" % rc)
t("sha256 mismatch" in out, "and it says why")
t(open(SB, "rb").read() == good, "the working binary is still there, byte for byte")
t("1.13.0.h10" in binout(SB), "and it still runs")
W.make_singbox("1.13.0.h10")

print("-- 4. an unpinned version needs a deliberate yes")
W.make_singbox("1.13.1")
W.reset_log()
rc, out = W.cm("install singbox 1.13.1")
t(rc == 4, "an unpinned version is refused", "rc=%d" % rc)
t("not pinned in packages.lock" in out, "and the message explains the way out")
t("1.13.0.h10" in binout(SB), "the live core did not move")
rc, out = W.cm("install singbox 1.13.1", {"CM_ALLOW_UNPINNED": "1"})
t(rc == 0, "with CM_ALLOW_UNPINNED=1 it goes through", out.strip()[-90:])
lock = open(W.H + "/common/packages.lock").read()
t("singbox|1.13.1|amd64|" in lock, "and the new version is pinned for next time")
t("1.13.1" in binout(SB), "the new version is live", binout(SB))

print("-- 5. a binary that cannot run is not installed at all")
W.make_singbox("1.13.2", ok=False)
ROWS.append(("singbox", "1.13.2", "amd64", "sing-box-1.13.2-linux-amd64.tar.gz"))
W.lock(ROWS)
W.reset_log()
rc, out = W.cm("install singbox 1.13.2")
t(rc == 2, "a binary that does not answer is rejected", "rc=%d" % rc)
t("does not run here" in out, "and it says so plainly")
t("1.13.1" in binout(SB), "the previous core is untouched", binout(SB))
t("SYSTEMCTL restart" not in W.calls(), "the service was never restarted for it")

print("-- 6. a service that does not come up rolls itself back")
W.make_singbox("1.13.3")
ROWS.append(("singbox", "1.13.3", "amd64", "sing-box-1.13.3-linux-amd64.tar.gz"))
W.lock(ROWS)
W.down("hiddify-singbox")
W.reset_log()
rc, out = W.cm("install singbox 1.13.3")
t(rc == 3, "the install reports the failure", "rc=%d" % rc)
t("did not come up" in out, "and names the service")
t("rolling singbox back to 1.13.1" in out, "and rolls back on its own")
t("1.13.1" in binout(SB), "the core in place is the one that worked", binout(SB))
db = open(W.H + "/common/cores/installed.db").read()
t("singbox|1.13.1" in db, "and the record says the same", db.strip())
W.down("hiddify-singbox", False)

print("-- 7. rollback on request")
W.reset_log()
rc, out = W.cm("install singbox 1.13.0.h10")
t(rc == 0 and "1.13.0.h10" in binout(SB), "a downgrade to an older pinned version works", binout(SB))
rc, out = W.cm("rollback singbox")
t(rc == 0, "rollback ends well", out.strip()[-80:])
t("1.13.1" in binout(SB), "and the core before it is back", binout(SB))

print("-- 8. the store does not grow for ever")
rc, out = W.cm("prune singbox", {"CM_KEEP": "1"})
kept = sorted(
    d for d in os.listdir(W.H + "/common/cores/singbox") if os.path.isdir(W.H + "/common/cores/singbox/" + d)
)
t(len(kept) <= 2, "prune keeps the current version and one spare", str(kept))
t("1.13.1" in kept, "the version in use is never pruned", str(kept))
rc, out = W.cm("verify singbox")
t(rc == 0 and out.strip().startswith("ok"), "verify says the live core is healthy", out.strip())
rc, out = W.cm("status")
t("singbox" in out and "active" in out, "status prints a readable table")

print("FAILURES: %d %s" % (len(fails), fails))
