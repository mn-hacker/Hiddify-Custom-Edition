# -*- coding: utf-8 -*-
"""live checks for the watashi v12.2.49 certificate engine, part 2."""
import os, shutil, subprocess, sys

sys.path.insert(0, "/data/w")
import w49env as W

fails = []


def ok(cond, label, extra=""):
    if not W.say(cond, label, extra):
        fails.append(label)


def live(body):
    return "\n".join(l for l in body.split("\n") if not l.strip().startswith("#"))


def issuer_is_subject(path):
    q = lambda w: subprocess.run(
        ["openssl", "x509", "-" + w, "-noout", "-in", path], capture_output=True, text=True
    ).stdout.split("=", 1)[-1].strip()
    return q("issuer") == q("subject")


W.build()
M = W.M + "acme.sh/"
inst = open(M + "install.sh", encoding="utf-8").read()
run = open(M + "run.sh", encoding="utf-8").read()
svc = open(M + "watashi-cert-renew.service", encoding="utf-8").read()
tmr = open(M + "watashi-cert-renew.timer", encoding="utf-8").read()

print("-- 9. the ecc store, the bug that broke ssl in the first place")
W.fresh(rule_list=[("*--install-cert*--ecc*", 0), ("*--install-cert*", 1)])
out = W.get_cert("a.example.com")
ok("trying the ecc store" in out, "when the rsa store is empty we look in the ecc store")
ok("Certificate installed successfully" in out, "and the certificate is installed")
ok("All CA providers failed" not in out, "no false total failure")
ok(os.path.exists(W.H + "/ssl/a.example.com.crt"), "the file is really there")
ok(not os.path.exists(W.H + "/ssl/a.example.com.crt.bk"), "the backup copy is cleaned up")

print("-- 10. the six hour cooldown")
W.fresh(rule_list=[("*--issue*", 1)])
out = W.get_cert("a.example.com")
asked = [a for a in W.acme_args() if a.startswith("--issue")]
ok(len(asked) >= 3, "a failing domain walks the whole ladder once", str(len(asked)))
ok(os.path.exists(W.A + "/lib/data/watashi/lasttry-a.example.com"), "the failure is remembered")

W.reset_log()
out = W.get_cert("a.example.com")
ok(len(W.acme_args()) == 0, "the next apply_configs does not ask again", str(len(W.acme_args())))
ok("keeping the current certificate" in out, "and it says why")

W.reset_log()
W.get_cert("a.example.com", env={"WS_SSL_FORCE": "1"})
ok(len([a for a in W.acme_args() if a.startswith("--issue")]) >= 3, "a deliberate request still tries at once")

W.reset_log()
W.sh("bash get_cert.sh a.example.com")
ok(len([a for a in W.acme_args() if a.startswith("--issue")]) >= 3, "the button in the panel goes through get_cert.sh and is never blocked")

W.rules([])
W.reset_log()
W.get_cert("a.example.com", env={"WS_SSL_FORCE": "1"})
ok(not os.path.exists(W.A + "/lib/data/watashi/lasttry-a.example.com"), "a success clears the cooldown")

print("-- 11. a healthy certificate is left alone")
W.fresh()
shutil.copy2(W.T + "/real.crt", W.H + "/ssl/b.example.com.crt")
shutil.copy2(W.T + "/real.key", W.H + "/ssl/b.example.com.crt.key")
out = W.get_cert("b.example.com")
ok("skipping renewal" in out, "an 89 day certificate is not renewed")
ok(len(W.acme_args()) == 0, "and no CA is contacted at all", str(len(W.acme_args())))

print("-- 12. run.sh over a realistic domain list")
DOMS = [
    {"domain": "a.example.com", "mode": "direct"},
    {"domain": "r.example.com", "mode": "relay"},
    {"domain": "s.example.com", "mode": "sub_link_only"},
    {"domain": "c.example.com", "mode": "cdn"},
    {"domain": "w.example.com", "mode": "worker"},
    {"domain": "f.example.com", "mode": "fake"},
]
W.fresh(domains=DOMS)
out = W.sh("bash run.sh")
asked = sorted(set(a.split("-d ")[1].split(" ")[0] for a in W.acme_args() if a.startswith("--issue")))
ok(asked == ["a.example.com", "r.example.com", "s.example.com"], "without a token only the reachable modes are asked", str(asked))
for d in DOMS:
    ok(os.path.exists(W.H + "/ssl/" + d["domain"] + ".crt"), "%s ends up with a certificate file" % d["domain"])
ok(issuer_is_subject(W.H + "/ssl/c.example.com.crt"), "the cdn domain gets a self signed certificate")
ok(not [f for f in os.listdir(W.H + "/ssl") if "*" in f], "no wildcard named junk file")
ok(not os.path.exists(W.H + "/ssl/cert_utils.sh.crt"), "no certificate named after a script")

W.fresh(cf_token="cf-secret-token", domains=DOMS)
out = W.sh("bash run.sh")
asked = sorted(set(a.split("-d ")[1].split(" ")[0] for a in W.acme_args() if a.startswith("--issue")))
ok("c.example.com" in asked and "w.example.com" in asked, "with a token the cdn and worker domains are asked too", str(asked))
ok("cdn domains are included" in out, "and run.sh says so")
issues = [a for a in W.acme_args() if a.startswith("--issue")]
ok(issues and all("--dns dns_cf" in a for a in issues), "every order uses the dns challenge")

print("-- 12b. a real cdn certificate survives a renewal run")
W.fresh(domains=DOMS)
shutil.copy2(W.T + "/real.crt", W.H + "/ssl/c.example.com.crt")
shutil.copy2(W.T + "/real.key", W.H + "/ssl/c.example.com.crt.key")
before = open(W.H + "/ssl/c.example.com.crt", "rb").read()
W.sh("bash run.sh")
after = open(W.H + "/ssl/c.example.com.crt", "rb").read()
ok(before == after, "the real certificate is byte identical afterwards")

print("-- 13. install.sh and the renewal timer")
ok('"$_retryafter" -gt 20' in inst, "the retry comparison is numeric now")
ok('_retryafter" > 20' not in inst, "the old string comparison is gone")
ok("my@example.com" not in live(inst), "the placeholder account email is gone")
ok("--register-account --server letsencrypt -m" in inst, "the account is registered against a named server")
ok("systemctl enable --now watashi-cert-renew.timer" in inst, "the timer is enabled at install time")
ok("ExecStart=/bin/bash /opt/hiddify-manager/acme.sh/run.sh" in svc, "the service runs the certificate script")
ok("Type=oneshot" in svc and "TimeoutStartSec=" in svc, "it is a one shot with a timeout")
ok("WorkingDirectory=/opt/hiddify-manager/acme.sh" in svc, "from the right directory")
ok("OnCalendar=*-*-* 03:17:00" in tmr and "Persistent=true" in tmr, "the timer runs nightly and catches up after downtime")
ok("RandomizedDelaySec=1800" in tmr, "with a random delay so every panel does not hit the CA at once")
ok("WantedBy=timers.target" in tmr, "and it is installable")
for part in ("[Unit]", "[Service]", "[Install]"):
    ok(part in svc, "the service has its %s section" % part)
for part in ("[Unit]", "[Timer]", "[Install]"):
    ok(part in tmr, "the timer has its %s section" % part)

print("-- 14. contrast with the file we replaced")
old_cu = open(M + "cert_utils.sh.b49", encoding="utf-8").read()
old_inst = open(M + "install.sh.b49", encoding="utf-8").read()
old_run = open(M + "run.sh.b49", encoding="utf-8").read()
ok('"amazonaws.com","azurewebsites.net"' in old_cu, "the old list really was comma glued")
ok("--register-account" not in old_cu, "the old engine really never registered an account")
ok("dns_cf" not in old_cu, "and had no dns challenge")
ok("--force" in old_cu and "--ecc" not in old_cu, "and forced every order while ignoring the ecc store")
ok('_retryafter" > 20' in old_inst, "the old string comparison was real")
ok("my@example.com" in old_inst, "the placeholder email was real")
ok("timer" not in old_inst, "and there was no renewal timer at all")
ok("for f in ../ssl/*.crt" in old_run, "the old run.sh looped over whatever was in ssl/")
ok("nullglob" not in old_run, "without nullglob, so an empty directory produced a literal star")

print("FAILURES: %d %s" % (len(fails), fails))
