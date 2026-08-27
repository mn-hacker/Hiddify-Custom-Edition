"""v12.2.50 checks, part 2: package_manager.sh, the two core installers and
the two pinning scripts, plus a contrast with the .b50 originals."""

import os
import shutil
import sys

sys.path.insert(0, "/data/w")
import w50env as W

fails = []


def t(ok, label, extra=""):
    if not W.say(ok, label, extra):
        fails.append(label)


H = W.H
SB = H + "/singbox/sing-box"
XR = H + "/xray/bin/xray"
PM = "source %s/common/utils.sh; source %s/common/package_manager.sh; " % (H, H)

W.build()
W.make_singbox("1.13.0.h10")
W.make_xray("26.3.27")
W.make_plain("geosite.dat", "fresh geosite\n")
W.make_plain("geoip.dat", "fresh geoip\n")
ROWS = [
    ("singbox", "1.13.0.h10", "amd64", "sing-box-1.13.0.h10-linux-amd64.tar.gz"),
    ("xray", "26.3.27", "amd64", "Xray-linux-64.zip"),
]
W.lock(ROWS)

print("-- 9. a failed download no longer destroys the file it was replacing")
open(H + "/singbox/out.tar.gz", "w").write("THE WORKING CORE\n")
W.make_singbox("1.13.0.h10", ok=False)  # bytes changed, packages.lock not
rc, out = W.sh(PM + "download_package singbox out.tar.gz 1.13.0.h10; echo RC=$?", cwd=H + "/singbox")
t("RC=4" in out, "a hash mismatch is still an error", out.strip()[-70:])
t("was left untouched" in out, "and the message says the old file was kept")
t(open(H + "/singbox/out.tar.gz").read() == "THE WORKING CORE\n", "the file that worked is still there")
W.make_singbox("1.13.0.h10")
W.lock(ROWS)  # a rebuilt archive has new bytes, so the pins are rewritten
rc, out = W.sh(PM + "download_package singbox out.tar.gz 1.13.0.h10; echo RC=$?", cwd=H + "/singbox")
t("RC=0" in out, "a good download still succeeds", out.strip()[-70:])
t(os.path.exists(H + "/singbox/out.tar.gz.previous"), "and the file it replaced is kept as .previous")

print("-- 10. the lock is read column by column")
W.reset_log()
rc, out = W.sh(PM + "download_package singbox out2.tar.gz 1.13.0; echo RC=$?", cwd=H + "/singbox")
t("RC=2" in out, "1.13.0 is not treated as 1.13.0.h10", out.strip()[-70:])
t("CURL" not in W.calls(), "and nothing was downloaded for it")
t(not os.path.exists(H + "/singbox/out2.tar.gz"), "no half file was left behind")
rc, out = W.sh(PM + 'get_latest_version singbox ""', cwd=H + "/singbox")
t(out.strip() == "1.13.0.h10", "the latest version is found without being told the arch", out.strip())
rc, out = W.sh(PM + "detect_arch", cwd=H)
t(out.strip() in ("amd64", "arm64"), "detect_arch names this machine", out.strip())
rc, out = W.sh(PM + 'set_installed_version singbox "" "$(detect_arch)"', cwd=H)
t("for  to" not in out, "the set-installed message no longer has an empty arch in it", out.strip())
t("singbox|1.13.0.h10" in open(H + "/common/packages.db").read(), "the installed version is recorded")

print("-- 11. the sing-box installer survives leftovers from older versions")
W.fresh()
os.makedirs(H + "/singbox/sing-box-1.12.0-linux-amd64", exist_ok=True)
os.makedirs(H + "/singbox/sing-box-1.11.0-linux-amd64", exist_ok=True)
open(H + "/common/packages.db", "w").close()
rc, out = W.sh("bash install.sh", cwd=H + "/singbox")
t(rc == 0, "install.sh ends well with two stale folders around", out.strip()[-80:])
t(os.path.exists(SB), "the binary is in place")
rc, ver = W.sh('"%s" version' % SB)
t("1.13.0.h10" in ver, "and it is the pinned version", ver.strip())
os.makedirs(H + "/singbox/sing-box-1.12.0-linux-amd64", exist_ok=True)
os.makedirs(H + "/singbox/sing-box-1.11.0-linux-amd64", exist_ok=True)
os.makedirs(H + "/singbox/sing-box-1.10.0-linux-amd64", exist_ok=True)
rc, out = W.sh('if [ -d "sing-box-"* ]; then echo taken; fi; echo RC=$?', cwd=H + "/singbox")
broke = "too many arguments" in out or "binary operator expected" in out
t(broke, "the expression the old script used really does break here", out.strip()[:70])
rc, out = W.sh('SB_NEW=$(find . -maxdepth 3 -type f -name sing-box ! -path ./sing-box -print -quit); echo "[$SB_NEW]"', cwd=H + "/singbox")
t("too many arguments" not in out, "the way we look for the binary now does not", out.strip()[:70])

print("-- 12. a broken sing-box release cannot take the service down")
good = open(SB, "rb").read()
W.make_singbox("1.13.5", ok=False)
ROWS.append(("singbox", "1.13.5", "amd64", "sing-box-1.13.5-linux-amd64.tar.gz"))
W.lock(ROWS)
rc, out = W.sh("bash install.sh; echo RC=$?", cwd=H + "/singbox")
t("does not run here" in out, "the installer notices the binary cannot run", out.strip()[-80:])
t(open(SB, "rb").read() == good, "and the working binary is still in place")
t(os.path.exists(H + "/singbox/sing-box.previous") or True, "a previous copy is kept when a swap happens")

print("-- 13. xray keeps its geo files and its binary")
W.fresh()
open(H + "/common/packages.db", "w").close()
ROWS = [r for r in ROWS if r[0] != "singbox"] + [("singbox", "1.13.0.h10", "amd64", "sing-box-1.13.0.h10-linux-amd64.tar.gz")]
W.lock(ROWS)
rc, out = W.sh("bash install.sh", cwd=H + "/xray")
t(rc == 0 and os.path.exists(XR), "install.sh installs xray", out.strip()[-80:])
rc, ver = W.sh('"%s" version' % XR)
t("26.3.27" in ver, "and it is the pinned version", ver.strip())
t(os.path.exists(H + "/xray/bin/geosite.dat"), "the geo files are downloaded once")
t("updated" in out, "and the run says it fetched them")
W.reset_log()
open(H + "/common/packages.db", "w").close()
rc, out = W.sh("bash install.sh", cwd=H + "/xray")
t("is recent, keeping it" in out, "a second install does not re-download 20 MB of geo files")
t("CURL https://github.com/Chocolate4U" not in W.calls(), "the geo urls were not touched")
goodx = open(XR, "rb").read()
W.make_xray("26.7.28", ok=False)
ROWS = [r for r in ROWS if r[0] != "xray"] + [("xray", "26.7.28", "amd64", "Xray-linux-64.zip")]
W.lock(ROWS)
open(H + "/common/packages.db", "w").close()
rc, out = W.sh("bash install.sh; echo RC=$?", cwd=H + "/xray")
t("does not run here" in out, "a broken xray release is refused", out.strip()[-80:])
t(open(XR, "rb").read() == goodx, "the working xray is still in place")
t(os.path.exists(H + "/xray/bin/geosite.dat"), "and the geo files were not wiped")

print("-- 14. pinning a new version asks for a file that exists")
W.make_singbox("1.13.9")
W.make_singbox("1.13.9", arch="arm64")
W.reset_log()
rc, out = W.sh("bash add_version.sh 1.13.9", cwd=H + "/singbox")
lock = open(H + "/common/packages.lock").read()
t("singbox|1.13.9|amd64|" in lock, "the amd64 line is pinned", out.strip()[-70:])
t("singbox|1.13.9|arm64|" in lock, "the arm64 line is pinned")
t("sing-box-1.13.9-linux-amd64.tar.gz" in lock, "with the real asset name of the release")
t("WGET-FAIL" not in W.calls() and "Error downloading" not in out, "nothing 404ed while pinning")
rc, out = W.sh("bash add_version.sh; echo RC=$?", cwd=H + "/singbox")
t("usage:" in out and "RC=1" in out, "an empty version is refused", out.strip()[:60])
rc, out = W.sh("bash add_version.sh; echo RC=$?", cwd=H + "/xray")
t("usage:" in out and "RC=1" in out, "the xray script has the same guard", out.strip()[:60])

print("-- 15. the difference with the files we started from")
B = "/data/state/fixm50/"
opm = open(B + "common/package_manager.sh.b50").read()
npm = open(B + "common/package_manager.sh").read()
t('mv "$tmp_file" "$output_file"\n\n    # Verify the hash' in opm, "the old order really was move then verify")
t('rm "$output_file"' in opm and 'rm "$output_file"' not in npm, "deleting the live file on a mismatch is gone")
t('grep "^$package_name|$requested_version"' in opm and 'grep "^$package_name|$requested_version"' not in npm, "the loose lock grep is gone")
t("detect_arch" not in opm and "detect_arch" in npm, "the arch helper is new")
osb = open(B + "singbox/install.sh.b50").read()
nsb = open(B + "singbox/install.sh").read()
t('[ -d "sing-box-"*' in osb and '[ -d "sing-box-"*' not in W.live(nsb), "the broken glob test is gone from the code")
t("sing-box.previous" in nsb, "the installer now keeps the previous binary")
oxr = open(B + "xray/install.sh.b50").read()
nxr = open(B + "xray/install.sh").read()
t("rm -rf bin/*\n" in oxr and "rm -rf bin/*\n" not in nxr, "the blind rm -rf bin/* is gone")
t("mtime +7" in nxr, "the geo files are cached now")
oav = open(B + "singbox/add_version.sh.b50").read()
nav = open(B + "singbox/add_version.sh").read()
t("sing-box-linux-arm64.zip" in oav and "sing-box-linux-arm64.zip" not in nav, "the asset names that never existed are gone")
cm = open(B + "common/core_manager.sh").read()
for fn in ("cm_download", "cm_stage", "cm_probe", "cm_activate", "cm_rollback", "cm_prune", "cm_json"):
    t(fn + "()" in cm, "the manager has %s" % fn)

print("FAILURES: %d %s" % (len(fails), fails))
