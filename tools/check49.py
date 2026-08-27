# -*- coding: utf-8 -*-
"""live checks for the watashi v12.2.49 certificate engine, part 1."""
import os, sys

sys.path.insert(0, "/data/w")
import w49env as W

fails = []


def ok(cond, label, extra=""):
    if not W.say(cond, label, extra):
        fails.append(label)


def live(body):
    """the code without comment lines, so a sentence in a comment can never
    make a check pass or fail"""
    out = []
    for l in body.split("\n"):
        s = l.strip()
        if s.startswith("#"):
            continue
        out.append(l.split(" #")[0] if s.startswith("#") else l)
    return "\n".join(out)


W.build()
M = W.M + "acme.sh/"
cu = open(M + "cert_utils.sh", encoding="utf-8").read()
inst = open(M + "install.sh", encoding="utf-8").read()
run = open(M + "run.sh", encoding="utf-8").read()
get = open(M + "get_cert.sh", encoding="utf-8").read()

print("-- 1. what the files say")
ok('"amazonaws.com" "azurewebsites.net" "cloudapp.net"' in cu, "the restricted list has three separate entries")
ok('"amazonaws.com","azurewebsites.net"' not in cu, "nothing is comma glued any more")
ok("buypass|Buypass" in cu, "buypass is in the ladder")
ok("google|Google Trust Services" in cu, "google is in the ladder")
ok("has_valid_cert" not in cu, "the dead has_valid_cert helper is gone")
ok("letsencrypt_test" not in cu, "the staging server is not used")
ok("my@example.com" not in live(cu), "the placeholder email is not in the engine")
ok("--keylength" in cu, "a key length is pinned")
ok("ws_valid_domain" in cu, "there is a domain guard")
ok("--ecc" in cu, "the ecc store is handled")

print("-- 2. is_ok_domain_zerossl")
for d, want in (("a.ir", "NO"), ("a.by", "NO"), ("x.amazonaws.com", "NO"), ("x.cloudapp.net", "NO"), ("a.com", "YES")):
    out = W.sh("source ./cert_utils.sh; is_ok_domain_zerossl %s && echo YES || echo NO" % d)
    ok(want in out, "zerossl decision for %s is %s" % (d, want), out.strip()[-20:])

print("-- 3. a script name is not a domain")
W.fresh()
out = W.get_cert("cert_utils.sh")
ok("is not a domain name" in out, "cert_utils.sh is refused")
ok(len(W.acme_args()) == 0, "and no certificate authority was contacted", str(len(W.acme_args())))
out = W.sh("source ./cert_utils.sh; get_self_signed_cert '*.crt'")
ok("is not a domain name" in out, "the self signed helper refuses a wildcard")
junk = [f for f in os.listdir(W.H + "/ssl") if "*" in f or f.startswith("cert_utils")]
ok(not junk, "no junk file was created in ssl/", str(junk))

print("-- 4. the happy path")
W.fresh()
out = W.get_cert("a.example.com")
args = W.acme_args()
ok(any("--register-account" in a and "letsencrypt" in a for a in args), "an account is registered with let's encrypt first")
ok(any("-m ssl@example.com" in a for a in args), "with an email built from the real domain")
ok(any(a.startswith("--issue") for a in args), "then the certificate is ordered")
ok(any("--install-cert" in a for a in args), "and installed")
ok(os.path.exists(W.A + "/lib/data/watashi/account-letsencrypt"), "the account is remembered so we never register twice")
ok(out.count("Certificate installed successfully") == 1, "the success line is printed once", str(out.count("Certificate installed successfully")))
ok(os.path.exists(W.H + "/ssl/a.example.com.crt"), "the certificate file is in place")

print("-- 5. let's encrypt fails, zerossl takes over")
W.fresh(rule_list=[("*--server letsencrypt*", 1)])
out = W.get_cert("a.example.com")
args = W.acme_args()
ok(any("--register-account" in a and "zerossl" in a for a in args), "an account is registered with zerossl")
ok(any(a.startswith("--issue") and "zerossl" in a for a in args), "and the order goes to zerossl")
ok("got its certificate from ZeroSSL over http" in out, "zerossl wins the ladder")
ok(out.count("Certificate installed successfully") == 1, "the success line is printed once here too")
ok("All CA providers failed" not in out, "nothing claims a total failure")

print("-- 6. the whole ladder, then google with eab")
W.fresh(rule_list=[("*--issue*", 1)])
out = W.get_cert("a.example.com")
asked = [a for a in W.acme_args() if a.startswith("--issue")]
servers = sorted(set(a.split("--server ")[1].split(" ")[0] for a in asked))
ok(servers == ["buypass", "letsencrypt", "zerossl"], "three CAs were really asked", str(servers))
ok("Google Trust Services needs EAB credentials" in out, "google is skipped with a clear reason")
ok("a self signed fallback" in out, "and the fallback is honest about itself")
ok("All CA providers failed" in out, "the failure is reported")
ok(os.path.exists(W.H + "/ssl/a.example.com.crt"), "a self signed certificate exists so the panel still serves tls")

W.fresh(rule_list=[("*--issue*", 1)])
with open(W.A + "/google_eab.conf", "w") as f:
    f.write('EAB_KID="kid123"\nEAB_HMAC_KEY="hmac456"\n')
out = W.get_cert("a.example.com")
args = W.acme_args()
ok(any("--eab-kid kid123" in a and "--eab-hmac-key hmac456" in a for a in args), "with google_eab.conf the eab credentials are used")
ok(any(a.startswith("--issue") and "google" in a for a in args), "and google is really asked")
os.remove(W.A + "/google_eab.conf")

print("-- 7. cloudflare dns versus the webroot")
W.fresh(cf_token="cf-secret-token")
out = W.get_cert("a.example.com", env={"WS_TEST_DIG4": "", "WS_TEST_DIG6": ""})
args = W.acme_args()
first = [a for a in args if a.startswith("--issue")][0]
ok("--dns dns_cf" in first, "the first order uses the cloudflare dns challenge", first[:60])
ok(any("ENV: CF_Token=cf-secret-token" == l for l in W.calls()), "the saved token is handed to acme.sh")
ok("does not resolve yet" in out, "a domain that does not resolve is not fatal any more")
ok("got its certificate from" in out and "over cloudflare-dns" in out, "and it succeeds over dns")

W.fresh()
out = W.get_cert("a.example.com")
first = [a for a in W.acme_args() if a.startswith("--issue")][0]
ok("-w /opt/hiddify-manager/acme.sh/www/" in first, "without a token the webroot challenge is used", first[:60])
ok(any("SYSTEMCTL: reload hiddify-nginx" in l for l in W.calls()), "nginx is reloaded, not restarted")
ok(not any("restart hiddify-nginx" in l for l in W.calls()), "no restart of nginx during a certificate run")
ok(open(W.H + "/nginx/parts/acme.conf").read().strip() == "", "the challenge location is removed afterwards")

print("-- 8. rate limits")
W.fresh()
W.get_cert("a.example.com")
first = [a for a in W.acme_args() if a.startswith("--issue")][0]
ok("--force" not in first, "a first order never uses --force", first[:70])
ok("--keylength 2048" in first, "rsa 2048 is requested explicitly")
ok("--log /opt/hiddify-manager/log/system/acme.log" in first, "acme.sh logs into the panel log directory")

W.fresh(rule_list=[("*--issue*", 2)])
W.get_cert("a.example.com")
args = W.acme_args()
renew = [a for a in args if a.startswith("--renew")]
ok(renew, "an existing order is renewed against the same CA", str(renew[:1]))
ok(renew and "--force" in renew[0], "--force is used only where it belongs, on a renewal")
ok(all("--force" not in a for a in args if a.startswith("--issue")), "the order itself stays clean")

print("FAILURES: %d %s" % (len(fails), fails))
