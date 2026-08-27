# -*- coding: utf-8 -*-
"""
watashi v12.2.49 - the certificate engine.

the real finding: the CA ladder existed, but ZeroSSL / Buypass / Google refuse
every order until an ACME account is registered with them, and nothing in the
panel ever registered one. on top of that acme.sh 3.x stores an ec-256
certificate in <domain>_ecc, and the old install step had no --ecc, so a
certificate that had just been issued could not be found and the panel fell
back to a self signed one. --force on every attempt burned the duplicate limit,
cdn/worker domains were excluded, and nothing renewed anything after install.
"""
import os, shutil, subprocess

SRC = "/data/state/src3/"
M = "/data/state/fixm/"
A = "acme.sh/"
MARK = "v12.2.49"
HEAD = "/data/w/cu49_head.sh"

fails = []


def bring(rel):
    s, d = SRC + rel, M + rel
    os.makedirs(os.path.dirname(d), exist_ok=True)
    if not os.path.exists(d):
        shutil.copy2(s, d)
    return d


def load(p):
    with open(p, "r", encoding="utf-8", newline="") as f:
        return f.read()


def save(p, t):
    with open(p, "w", encoding="utf-8", newline="") as f:
        f.write(t)


def back(p):
    if not os.path.exists(p + ".b49"):
        shutil.copy2(p, p + ".b49")


def check(label, cond):
    if not cond:
        fails.append(label)
        print("BAD  " + label)


def find(lines, needle, start=0):
    for i in range(start, len(lines)):
        if needle in lines[i]:
            return i
    return -1


# ---------------------------------------------------------------- bring files
p_cu = bring(A + "cert_utils.sh")
p_inst = bring(A + "install.sh")
p_run = bring(A + "run.sh")
p_get = bring(A + "get_cert.sh")
bring(A + "generate_self_signed_cert.sh")
for p in (p_cu, p_inst, p_run, p_get):
    back(p)

# ------------------------------------------------------------- cert_utils.sh
old_cu = load(p_cu + ".b49")
if MARK not in load(p_cu):
    i = old_cu.find("function get_self_signed_cert()")
    check("the self signed helper was found in the original", i > 0)
    tail = old_cu[i:]
    nl = tail.find("\n")
    guard = (
        "\n    # watashi: never make a certificate for a script name or a wildcard\n"
        '    if ! ws_valid_domain "$1"; then\n'
        "        echo \"watashi: '$1' is not a domain name, no self signed certificate created.\"\n"
        "        return 1\n"
        "    fi"
    )
    tail = tail[:nl] + guard + tail[nl:]
    save(p_cu, load(HEAD) + tail)

# ---------------------------------------------------------------- install.sh
txt = load(p_inst)
if MARK not in txt:
    lines = txt.split("\n")
    lines.insert(1, "# watashi " + MARK + ": a real account email and a renewal timer")

    i = find(lines, '"$_retryafter"')
    check("the retry-after line was found", i >= 0)
    if i >= 0:
        lines[i] = lines[i].replace('"$_retryafter" > 20', '"$_retryafter" -gt 20')

    i = find(lines, "--register-account")
    check("the register-account line was found", i >= 0)
    if i >= 0:
        lines[i] = "\n".join(
            [
                'WS_ROOT="/opt/hiddify-manager"',
                "# watashi: my@example.com is refused by several CAs, build a real one",
                "WS_MAIL=\"ssl@$(jq -r '.domains[0].domain // \"example.com\"' $WS_ROOT/current.json 2>/dev/null | awk -F. '{if (NF<=2) print $0; else print $(NF-1)\".\"$NF}')\"",
                'acme.sh --register-account --server letsencrypt -m "$WS_MAIL" >/dev/null 2>&1 || true',
                "# watashi: the vendored acme.sh cronjob is removed above, so this panel",
                "# had no renewal at all. from now on a systemd timer does it.",
                'cp -f "$WS_ROOT/acme.sh/watashi-cert-renew.service" /etc/systemd/system/ 2>/dev/null',
                'cp -f "$WS_ROOT/acme.sh/watashi-cert-renew.timer" /etc/systemd/system/ 2>/dev/null',
                "systemctl daemon-reload 2>/dev/null || true",
                "systemctl enable --now watashi-cert-renew.timer 2>/dev/null || true",
            ]
        )
    save(p_inst, "\n".join(lines))

# -------------------------------------------------------------------- run.sh
txt = load(p_run)
if MARK not in txt:
    lines = txt.split("\n")
    lines.insert(1, "# watashi " + MARK + ": cdn domains too, and no cert is replaced blindly")

    i = -1
    for k, l in enumerate(lines):
        if l.strip().startswith("domains=") and "current.json" in l:
            i = k
            break
    check("the domain selection line was found", i >= 0)
    if i >= 0:
        lines[i] = "\n".join(
            [
                "shopt -s nullglob",
                "WS_MODES='[\"direct\",\"relay\",\"sub_link_only\"]'",
                "# watashi: with a cloudflare token the dns challenge works for cdn too",
                'if [ -n "$(jq -r \'.chconfigs["0"].cloudflare // ""\' ../current.json 2>/dev/null | tr -d \'[:space:]\')" ]; then',
                "    WS_MODES='[\"direct\",\"relay\",\"sub_link_only\",\"cdn\",\"worker\",\"auto_cdn_ip\"]'",
                '    echo "watashi: a cloudflare token is present, cdn domains are included."',
                "fi",
                'domains=$(jq -r --argjson modes "$WS_MODES" \'.domains[] | select(.mode as $m | $modes | index($m)) | .domain\' ../current.json)',
            ]
        )

    a = find(lines, "for f in ../ssl/*.crt")
    check("the old blind self-sign loop was found", a >= 0)
    b = -1
    for k in range(len(lines) - 1, -1, -1):
        if "systemctl reload hiddify-haproxy" in lines[k]:
            b = k
            break
    check("the reload tail was found", b > a >= 0)
    if a >= 0 and b > a:
        block = [
            "# watashi: only a domain that has no usable certificate gets a self signed",
            "# one. the old loop looked at ../ssl/*.crt and could overwrite a real one.",
            "WS_ALL=$(jq -r '.domains[].domain' ../current.json)",
            'for d in $WS_ALL; do',
            '    f="../ssl/$d.crt"',
            '    if [ ! -f "$f" ] || ! openssl x509 -checkend 0 -noout -in "$f" >/dev/null 2>&1; then',
            '        echo "watashi: $d has no usable certificate, creating a self signed one."',
            '        bash generate_self_signed_cert.sh "$d"',
            "    fi",
            "done",
            "rm -f ../ssl/cert_utils.sh.crt ../ssl/cert_utils.sh.crt.key 2>/dev/null",
            'find ../ssl -maxdepth 1 -name "[*]*" -delete 2>/dev/null',
            "systemctl reload hiddify-nginx 2>/dev/null || true",
            "systemctl reload hiddify-haproxy 2>/dev/null || true",
        ]
        lines[a : b + 1] = block
    save(p_run, "\n".join(lines))

# ---------------------------------------------------------------- get_cert.sh
txt = load(p_get)
if MARK not in txt:
    lines = txt.split("\n")
    i = find(lines, "get_cert $1")
    if i < 0:
        i = find(lines, "get_cert \"$1\"")
    check("the get_cert call was found", i >= 0)
    if i >= 0:
        lines[i : i + 1] = [
            "# watashi " + MARK + ": a request from the panel is deliberate, so it",
            "# ignores the six hour cooldown that protects apply_configs",
            'export WS_SSL_FORCE="${WS_SSL_FORCE:-1}"',
            lines[i],
        ]
    save(p_get, "\n".join(lines))

# ------------------------------------------------------------------- units
save(
    M + A + "watashi-cert-renew.service",
    "\n".join(
        [
            "[Unit]",
            "Description=Watashi certificate renewal",
            "After=network-online.target hiddify-nginx.service",
            "Wants=network-online.target",
            "",
            "[Service]",
            "Type=oneshot",
            "WorkingDirectory=/opt/hiddify-manager/acme.sh",
            "ExecStart=/bin/bash /opt/hiddify-manager/acme.sh/run.sh",
            "TimeoutStartSec=1800",
            "Nice=10",
            "",
            "[Install]",
            "WantedBy=multi-user.target",
            "",
        ]
    ),
)
save(
    M + A + "watashi-cert-renew.timer",
    "\n".join(
        [
            "[Unit]",
            "Description=Watashi certificate renewal timer",
            "",
            "[Timer]",
            "OnCalendar=*-*-* 03:17:00",
            "RandomizedDelaySec=1800",
            "Persistent=true",
            "Unit=watashi-cert-renew.service",
            "",
            "[Install]",
            "WantedBy=timers.target",
            "",
        ]
    ),
)

# -------------------------------------------------------------------- checks
for rel in ("cert_utils.sh", "install.sh", "run.sh", "get_cert.sh"):
    p = M + A + rel
    t = load(p)
    check(rel + " has no CRLF", "\r" not in t)
    check(rel + " carries the marker", MARK in t)
    r = subprocess.run(["bash", "-n", p], capture_output=True, text=True)
    check(rel + " is valid bash", r.returncode == 0)
    if r.returncode != 0:
        print(r.stderr[-500:])
    print("  %-24s %d B" % (rel, len(t)))

print("FAILURES: %d %s" % (len(fails), fails))
