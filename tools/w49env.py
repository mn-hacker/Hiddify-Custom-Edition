# -*- coding: utf-8 -*-
"""live test bench for the watashi v12.2.49 certificate engine.

the real bash engine runs. only acme.sh, systemctl and dig are faked, and the
fake acme.sh installs a certificate that was really signed by a local CA, so
openssl checks in the engine are answered honestly.
"""
import json, os, shutil, subprocess

M = "/data/state/fixm/"
H = "/opt/hiddify-manager"
A = H + "/acme.sh"
BIN = "/tmp/w49bin"
T = "/tmp/w49"
LOG = T + "/acme-calls.log"
RULES = T + "/rules.txt"

FILES = [
    "cert_utils.sh",
    "install.sh",
    "run.sh",
    "get_cert.sh",
    "generate_self_signed_cert.sh",
    "watashi-cert-renew.service",
    "watashi-cert-renew.timer",
]

FAKE_ACME = r"""#!/bin/bash
echo "ARGS: $*" >>"$WS_TEST_LOG"
[ -n "$CF_Token" ] && echo "ENV: CF_Token=$CF_Token" >>"$WS_TEST_LOG"
rc=0
if [ -s "$WS_TEST_RULES" ]; then
    while IFS='|' read -r pat code; do
        [ -z "$pat" ] && continue
        case " $* " in
        $pat)
            rc="$code"
            break
            ;;
        esac
    done <"$WS_TEST_RULES"
fi
if [ "$rc" = "0" ] && [ "$1" = "--install-cert" ]; then
    fc=""
    kp=""
    while [ $# -gt 0 ]; do
        case "$1" in
        --fullchainpath)
            fc="$2"
            shift
            ;;
        --keypath)
            kp="$2"
            shift
            ;;
        esac
        shift
    done
    [ -n "$fc" ] && cp /tmp/w49/real.crt "$fc"
    [ -n "$kp" ] && cp /tmp/w49/real.key "$kp"
fi
exit "$rc"
"""

FAKE_SYSTEMCTL = r"""#!/bin/bash
echo "SYSTEMCTL: $*" >>"$WS_TEST_LOG"
exit 0
"""

FAKE_DIG = r"""#!/bin/bash
if [[ "$*" == *aaaa* ]]; then
    echo "${WS_TEST_DIG6-}"
else
    echo "${WS_TEST_DIG4-1.2.3.4}"
fi
exit 0
"""

UTILS = r"""#!/bin/bash
hconfig() { jq -r ".chconfigs[\"0\"].$1 // \"\"" /opt/hiddify-manager/current.json 2>/dev/null; }
error() { echo "ERROR: $*"; }
is_installed() { return 0; }
install_package() { return 0; }
remove_package() { return 0; }
SERVER_IP="${SERVER_IP:-1.2.3.4}"
SERVER_IPv6="${SERVER_IPv6:-}"
"""


def _w(p, t, mode=0o755):
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w", encoding="utf-8", newline="\n") as f:
        f.write(t)
    os.chmod(p, mode)


def _real_cert():
    """a genuine CA plus an 89 day leaf for a.example.com"""
    if os.path.exists(T + "/real.crt"):
        return
    q = lambda c: subprocess.run(c, shell=True, capture_output=True, text=True)
    q(
        'openssl req -x509 -newkey rsa:2048 -nodes -keyout %s/ca.key -out %s/ca.crt '
        '-days 3000 -subj "/CN=Watashi Test CA" 2>/dev/null' % (T, T)
    )
    q(
        'openssl req -newkey rsa:2048 -nodes -keyout %s/real.key -out %s/real.csr '
        '-subj "/CN=a.example.com" 2>/dev/null' % (T, T)
    )
    q(
        "openssl x509 -req -in %s/real.csr -CA %s/ca.crt -CAkey %s/ca.key "
        "-set_serial 1 -days 89 -out %s/real.crt 2>/dev/null" % (T, T, T, T)
    )


def build():
    for d in (
        A + "/lib/data",
        A + "/www",
        H + "/ssl",
        H + "/log/system",
        H + "/nginx/parts",
        H + "/common",
        BIN,
        T,
    ):
        os.makedirs(d, exist_ok=True)
    for f in FILES:
        shutil.copy2(M + "acme.sh/" + f, A + "/" + f)
    _w(H + "/common/utils.sh", UTILS)
    _w(A + "/lib/acme.sh.env", "#!/bin/bash\n:\n")
    _w(BIN + "/acme.sh", FAKE_ACME)
    _w(BIN + "/systemctl", FAKE_SYSTEMCTL)
    _w(BIN + "/dig", FAKE_DIG)
    _w(H + "/nginx/parts/acme.conf", "", 0o644)
    _real_cert()
    reset_log()
    rules([])


def current_json(cf_token="", domains=None):
    if domains is None:
        domains = [{"domain": "a.example.com", "mode": "direct"}]
    data = {"chconfigs": {"0": {"cloudflare": cf_token}}, "domains": domains}
    with open(H + "/current.json", "w", encoding="utf-8", newline="\n") as f:
        json.dump(data, f)


def rules(pairs):
    with open(RULES, "w", encoding="utf-8", newline="\n") as f:
        for pat, rc in pairs:
            f.write("%s|%s\n" % (pat, rc))


def reset_log():
    with open(LOG, "w", encoding="utf-8", newline="\n") as f:
        f.write("")


def calls():
    with open(LOG, "r", encoding="utf-8", errors="replace") as f:
        return [l.rstrip("\n") for l in f if l.strip()]


def acme_args():
    return [l[6:] for l in calls() if l.startswith("ARGS: ")]


def clean_ssl():
    for f in os.listdir(H + "/ssl"):
        try:
            os.remove(H + "/ssl/" + f)
        except OSError:
            pass


def clean_state():
    shutil.rmtree(A + "/lib/data/watashi", ignore_errors=True)


def fresh(cf_token="", domains=None, rule_list=None):
    """a completely clean world. every section starts here so that one section
    can never poison the next one."""
    clean_ssl()
    clean_state()
    try:
        os.remove(A + "/google_eab.conf")
    except OSError:
        pass
    current_json(cf_token, domains)
    rules(rule_list or [])
    reset_log()


def sh(cmd, env=None):
    e = dict(os.environ)
    e["PATH"] = BIN + ":" + e.get("PATH", "")
    e["WS_TEST_LOG"] = LOG
    e["WS_TEST_RULES"] = RULES
    e["SERVER_IP"] = "1.2.3.4"
    e["WS_RETRY_DELAY"] = "0"
    e["WS_CA_GAP"] = "0"
    e.pop("WS_SSL_FORCE", None)
    if env:
        e.update(env)
    r = subprocess.run(
        ["bash", "-c", cmd], cwd=A, env=e, capture_output=True, text=True, timeout=600
    )
    return r.stdout + r.stderr


def get_cert(domain, env=None):
    return sh("source ./cert_utils.sh; get_cert %s" % domain, env)


def say(ok, label, extra=""):
    print("%s %-62s %s" % ("OK  " if ok else "BAD ", label, extra))
    return bool(ok)
