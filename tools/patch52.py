"""watashi v12.2.52 -- the door that stayed shut, and the empty subscription.

Two things the testers found.

1. Three wrong passwords shut the login door, but nobody was told for how
   long. The counter lived per proxy path, so the same visitor was shut out of
   one address while another stayed open and no single clear could open it.
   The remaining time was read from the lifetime of a redis key, and the answer
   was served with status 429, which a cdn in front of the panel turns into its
   own error page: exactly the "like the internet is off" the tester reported.
   The submit button was broken markup too, the tag ended with `{% endif %}}`
   instead of `>`, so the browser ate the icon element as attributes.

2. A subscription link carried only the fake usage/time config. In
   get_valid_proxies() the duplicate guard is
   `all([x in added_ip[key] for x in ips])`; when dns answers with no ip at all
   `all([])` is True, so every ssh/ss/tuic/hysteria2/wireguard/mieru/naive/
   amnezia proxy is dropped silently. And nothing anywhere said why a link came
   back empty, so there was nothing to read afterwards.

Rule 17 bases: shared.py from /data/pkg47, cli.py from /data/pkg48, the rest
from the reference tree.
"""
import os
import py_compile
import shutil

SRC = "/data/state/src3/"
P47 = "/data/pkg47/"
P48 = "/data/pkg48/"
M = "/data/state/fixm52/"
P = "hiddify-panel/src/hiddifypanel/"
MARK = "watashi v12.2.52"
fails = []


def check(ok, label):
    print(("OK   " if ok else "BAD  ") + label)
    if not ok:
        fails.append(label)


def bring(rel, base=SRC):
    """Copies a file into the round folder once, keeping a .b52 beside it."""
    dst = M + rel
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    if not os.path.exists(dst):
        shutil.copy2(base + rel, dst)
    if not os.path.exists(dst + ".b52"):
        shutil.copy2(base + rel, dst + ".b52")
    return dst


def load(path):
    raw = open(path, "rb").read()
    crlf = b"\r\n" in raw
    return raw.replace(b"\r\n", b"\n").decode("utf-8"), crlf


def save(path, text, crlf):
    data = text.encode("utf-8")
    if crlf:
        data = data.replace(b"\n", b"\r\n")
    with open(path, "wb") as handle:
        handle.write(data)


def swap(text, old, new, label):
    if new in text:
        check(True, label + " (already there)")
        return text
    check(text.count(old) == 1, label + " anchor")
    return text.replace(old, new, 1)


LOGIN = P + "panel/common_bp/login.py"
PAGE = P + "panel/common_bp/templates/login.html"
SHARED = P + "hutils/proxy/shared.py"
CLI = P + "panel/cli.py"

bring(LOGIN)
bring(PAGE)
bring(SHARED, P47)
bring(CLI, P48)
check(os.path.exists(M + SHARED), "shared.py came from the applied v12.2.47 round")
check(os.path.exists(M + CLI), "cli.py came from the applied v12.2.48 round")

# ---------------------------------------------------------------- login.py ---
text, crlf = load(M + LOGIN)
check(crlf, "login.py is a windows file")

text = swap(text,
    "import re\n\n\n# --- Watashi v12.2.36",
    "import re\nimport time  # watashi v12.2.52: the door works on deadlines now\n\n\n# --- Watashi v12.2.36",
    "time is imported")

text = swap(text,
    "WS_LOCK_TIME = 600  # and how long it stays shut afterwards, in seconds\n",
    "WS_LOCK_TIME = 600  # and how long it stays shut afterwards, in seconds\n"
    "WS_LOCK_CAP = WS_LOCK_TIME  # watashi v12.2.52: nobody ever waits longer than this\n",
    "a hard ceiling on the wait")

text = swap(text,
    "def ws_door_key():\n"
    "    \"\"\"One counter per visitor and per path, never per account name.\"\"\"\n"
    "    who = request.headers.get('CF-Connecting-IP') or request.headers.get('X-Forwarded-For') or request.remote_addr or 'nowhere'\n"
    "    who = who.split(',')[0].strip()\n"
    "    return 'watashi:door:%s:%s' % (g.get('proxy_path', ''), who)\n",
    "def ws_door_key():\n"
    "    \"\"\"One counter per visitor, whichever address of the panel they knocked on.\n"
    "\n"
    "    watashi v12.2.52: the key used to carry the proxy path as well, so a\n"
    "    visitor could be shut out of one subdomain while another stayed open,\n"
    "    which is precisely how the tester saw it, and no single command could\n"
    "    open every door again.\n"
    "    \"\"\"\n"
    "    who = request.headers.get('CF-Connecting-IP') or request.headers.get('X-Forwarded-For') or request.remote_addr or 'nowhere'\n"
    "    who = who.split(',')[0].strip()\n"
    "    return 'watashi:door:%s' % who\n",
    "one lock per visitor, not per subdomain")

text = swap(text,
    "def ws_wait_left():\n"
    "    \"\"\"Seconds the door stays shut for this visitor, zero when it is open.\"\"\"\n"
    "    store = ws_store()\n"
    "    if store is None:\n"
    "        return 0\n"
    "    try:\n"
    "        left = store.ttl(ws_door_key() + ':shut')\n"
    "        left = int(left or 0)\n"
    "        return left if left > 0 else 0\n"
    "    except BaseException:\n"
    "        return 0\n",
    "def ws_wait_left():\n"
    "    \"\"\"Seconds the door stays shut for this visitor, zero when it is open.\n"
    "\n"
    "    watashi v12.2.52: the answer comes from a written deadline instead of the\n"
    "    lifetime of a key, it is capped at WS_LOCK_CAP, and anything unreadable\n"
    "    or already past is thrown away on sight. A leftover key can no longer\n"
    "    keep anybody waiting.\n"
    "    \"\"\"\n"
    "    store = ws_store()\n"
    "    if store is None:\n"
    "        return 0\n"
    "    key = ws_door_key() + ':until'\n"
    "    try:\n"
    "        raw = store.get(key)\n"
    "        if raw is None:\n"
    "            return 0\n"
    "        if isinstance(raw, bytes):\n"
    "            raw = raw.decode('utf-8', 'ignore')\n"
    "        left = int(float(raw) - time.time())\n"
    "    except BaseException:\n"
    "        ws_drop_key(key)\n"
    "        return 0\n"
    "    if left <= 0:\n"
    "        ws_drop_key(key)\n"
    "        return 0\n"
    "    return left if left < WS_LOCK_CAP else WS_LOCK_CAP\n",
    "the wait is read from a deadline and capped")

text = swap(text,
    "        if count >= WS_TRIES:\n"
    "            store.setex(ws_door_key() + ':shut', WS_LOCK_TIME, 1)\n"
    "            store.delete(key)\n",
    "        if count >= WS_TRIES and not ws_wait_left():\n"
    "            # watashi v12.2.52: a deadline, written once. Knocking again while\n"
    "            # the door is shut can never push it further away.\n"
    "            store.setex(ws_door_key() + ':until', WS_LOCK_TIME + 30, '%d' % int(time.time() + WS_LOCK_TIME))\n"
    "            store.delete(key)\n"
    "            ws_door_log('shut for %d seconds after %d wrong keys' % (WS_LOCK_TIME, count))\n",
    "the lock is written once and never extended")

text = swap(text,
    "        store.delete(ws_door_key() + ':miss')\n"
    "        store.delete(ws_door_key() + ':shut')\n",
    "        store.delete(ws_door_key() + ':miss')\n"
    "        store.delete(ws_door_key() + ':until')\n"
    "        store.delete(ws_door_key() + ':shut')  # watashi v12.2.52: and the old shape\n",
    "a good key clears every trace of the lock")

save(M + LOGIN, text, crlf)
print("-- login.py first pass done")

# --- login.py, second pass: the new helpers and the answer the door gives ----
text, crlf = load(M + LOGIN)

text = swap(text,
    "def ws_entrance_words():\n",
    "def ws_drop_key(key):\n"
    "    \"\"\"Throws a key away without ever letting redis break the page.\"\"\"\n"
    "    store = ws_store()\n"
    "    if store is None:\n"
    "        return\n"
    "    try:\n"
    "        store.delete(key)\n"
    "    except BaseException:\n"
    "        pass\n"
    "\n"
    "\n"
    "def ws_door_log(words):\n"
    "    \"\"\"Every shut door leaves a line behind, so it can be explained later.\"\"\"\n"
    "    try:\n"
    "        app.logger.warning('watashi door: %s %s' % (ws_door_key(), words))\n"
    "    except BaseException:\n"
    "        pass\n"
    "\n"
    "\n"
    "def ws_locked_words(waiting):\n"
    "    \"\"\"The sentence the door says, with the time left spelled out in numbers.\"\"\"\n"
    "    left = int(waiting or 0)\n"
    "    return '%s %d:%02d' % (str(_('login.locked.flash')), left // 60, left % 60)\n"
    "\n"
    "\n"
    "def ws_entrance_words():\n",
    "the door can log and can say how long")

text = swap(text,
    "def ws_render_entrance(form, status=200):\n",
    "def ws_render_entrance(form, status=200, retry_after=0):\n",
    "the door can answer with a waiting time")

text = swap(text,
    "    answer = make_response(body, status)\n"
    "    asked = request.args.get('lang')\n",
    "    answer = make_response(body, status)\n"
    "    if retry_after:\n"
    "        # watashi v12.2.52: a well behaved client waits instead of hammering\n"
    "        answer.headers['Retry-After'] = str(int(retry_after))\n"
    "    asked = request.args.get('lang')\n",
    "Retry-After rides along with a shut door")

text = swap(text,
    "        form = LoginForm()\n"
    "        if ws_wait_left() > 0:\n"
    "            hutils.flask.flash(_('login.locked.flash'), 'danger')  # type: ignore\n"
    "            return ws_render_entrance(LoginForm(), 429)\n",
    "        form = LoginForm()\n"
    "        waiting = ws_wait_left()\n"
    "        if waiting > 0:\n"
    "            # watashi v12.2.52: 200, not 429. A cdn in front of the panel turns a\n"
    "            # 429 into an error page of its own, and that is what the tester saw\n"
    "            # instead of the countdown.\n"
    "            hutils.flask.flash(ws_locked_words(waiting), 'danger')  # type: ignore\n"
    "            return ws_render_entrance(LoginForm(), 200, waiting)\n",
    "a shut door still draws the page")

text = swap(text,
    "        missed = ws_note_miss()\n"
    "        if ws_wait_left() > 0:\n"
    "            hutils.flask.flash(_('login.locked.flash'), 'danger')  # type: ignore\n",
    "        missed = ws_note_miss()\n"
    "        waiting = ws_wait_left()\n"
    "        if waiting > 0:\n"
    "            hutils.flask.flash(ws_locked_words(waiting), 'danger')  # type: ignore\n"
    "            return ws_render_entrance(LoginForm(), 200, waiting)\n",
    "the third wrong key shows the clock at once")

save(M + LOGIN, text, crlf)
check(text.count(MARK) >= 6, "login.py carries the round marker")
check("':shut'" in text, "the old key shape is still cleared")
print("-- login.py done")

# --------------------------------------------------------------- login.html ---
text, crlf = load(M + PAGE)
check(crlf, "login.html is a windows file")

text = swap(text,
    "id=\"lg-go\"{% if lg_locked %} disabled{% endif %}}<i",
    "id=\"lg-go\"{% if lg_locked %} disabled{% endif %}><i",
    "the submit button closes its own tag")

text = swap(text,
    "/* --- while the door is shut, it counts down in plain sight --- */\n",
    "/* --- while the door is shut, it counts down in plain sight ---\n"
    "   watashi v12.2.52: the same clock is drawn on a plain visit as well, not\n"
    "   only after a wrong key, because the panel now answers a shut door with a\n"
    "   page instead of a bare 429. --- */\n",
    "the countdown says which round it belongs to")

save(M + PAGE, text, crlf)
check("{% endif %}}" not in text, "the broken tag is gone")
check(MARK in text, "login.html carries the round marker")
print("-- login.html done")

# ---------------------------------------------------------------- shared.py ---
text, crlf = load(M + SHARED)
check(crlf, "shared.py is a windows file")

text = swap(text,
    "def get_valid_proxies(domains: list[Domain]) -> list[dict]:\n",
    "def ws_sub_note(reason, proxy=None):\n"
    "    \"\"\"Remembers why a proxy did not make it into this subscription.\n"
    "\n"
    "    watashi v12.2.52: an empty subscription used to be silent, so there was\n"
    "    nothing to read afterwards. The reasons live on flask.g, one request long.\n"
    "    \"\"\"\n"
    "    try:\n"
    "        notes = getattr(g, 'ws_sub_notes', None)\n"
    "        if notes is None:\n"
    "            notes = {}\n"
    "            g.ws_sub_notes = notes\n"
    "        word = str(reason or 'no reason given')\n"
    "        notes[word] = notes.get(word, 0) + 1\n"
    "    except Exception:\n"
    "        pass\n"
    "\n"
    "\n"
    "def ws_sub_reasons() -> dict:\n"
    "    \"\"\"Everything the last call to get_valid_proxies() threw away, and why.\"\"\"\n"
    "    try:\n"
    "        return dict(getattr(g, 'ws_sub_notes', None) or {})\n"
    "    except Exception:\n"
    "        return {}\n"
    "\n"
    "\n"
    "def ws_sub_complain(domains, disabled_proxies):\n"
    "    \"\"\"A subscription with no config in it is a bug, so it says so out loud.\"\"\"\n"
    "    try:\n"
    "        from flask import current_app\n"
    "        worst = sorted(ws_sub_reasons().items(), key=lambda pair: -pair[1])[:8]\n"
    "        current_app.logger.warning(\n"
    "            'watashi v12.2.52: a subscription came out empty. domains=%d off_for_this_user=%d reasons=%s'\n"
    "            % (len(domains or []), len(disabled_proxies or set()), worst))\n"
    "    except Exception:\n"
    "        pass\n"
    "\n"
    "\n"
    "def get_valid_proxies(domains: list[Domain]) -> list[dict]:\n",
    "an empty subscription can be explained")

text = swap(text,
    "                if noDomainProxies and all([x in added_ip[key] for x in ips]):\n"
    "                    continue\n",
    "                # watashi v12.2.52: with no resolved ip at all, all([]) is True, so\n"
    "                # every one of these protocols quietly vanished from the link. An\n"
    "                # empty answer from dns is not a duplicate.\n"
    "                if noDomainProxies and ips and all([x in added_ip[key] for x in ips]):\n"
    "                    ws_sub_note('this ip is already served by another domain', proxy)\n"
    "                    continue\n"
    "                if noDomainProxies and not ips:\n"
    "                    ws_sub_note('no ip resolved for %s, kept anyway' % domain.domain, proxy)\n",
    "no resolved ip no longer means no config")

text = swap(text,
    "                if 'msg' not in pinfo:\n"
    "                    allp.append(pinfo)\n"
    "    return allp\n",
    "                if 'msg' not in pinfo:\n"
    "                    allp.append(pinfo)\n"
    "                else:\n"
    "                    ws_sub_note(pinfo.get('msg'), proxy)\n"
    "    if not allp:\n"
    "        ws_sub_complain(domains, disabled_proxies)\n"
    "    return allp\n",
    "every dropped proxy leaves its reason behind")

save(M + SHARED, text, crlf)
check(text.count(MARK) >= 3, "shared.py carries the round marker")
print("-- shared.py done")

# ------------------------------------------------------------------- cli.py ---
text, crlf = load(M + CLI)
check(crlf, "cli.py is a windows file")

NEW_CLI = (
    "    # watashi v12.2.52: two hands for the two bugs the testers found\n"
    "    WS_HEAL_ON = ('vless_enable', 'vmess_enable', 'trojan_enable', 'ws_enable',\n"
    "                  'grpc_enable', 'tcp_enable', 'h2_enable', 'xhttp_enable',\n"
    "                  'httpupgrade_enable', 'quic_enable', 'reality_enable')\n"
    "\n"
    "    @ app.cli.command('unlock-login')\n"
    "    @ click.option('--ip', default='', help='only this visitor, empty means everybody')\n"
    "    def unlock_login(ip):\n"
    "        \"\"\"Opens the doors the wrong password lock has shut.\"\"\"\n"
    "        from hiddifypanel.cache import redis_client\n"
    "        who = (ip or '').strip()\n"
    "        gone = 0\n"
    "        try:\n"
    "            for key in redis_client.scan_iter(match='watashi:door:%s*' % who, count=500):\n"
    "                redis_client.delete(key)\n"
    "                gone += 1\n"
    "        except Exception as problem:\n"
    "            print('could not reach redis: %s' % problem)\n"
    "            return\n"
    "        print('opened %d door keys for %s' % (gone, who or 'everybody'))\n"
    "\n"
    "    @ app.cli.command('sub-doctor')\n"
    "    @ click.option('--uuid', '-u', default='')\n"
    "    @ click.option('--fix', is_flag=True, default=False)\n"
    "    def sub_doctor(uuid, fix):\n"
    "        \"\"\"Explains, line by line, why a subscription link carries no config.\"\"\"\n"
    "        from flask import g\n"
    "        from hiddifypanel.hutils.proxy.shared import ws_sub_reasons\n"
    "        want = (uuid or '').strip()\n"
    "        user = User.by_uuid(want) if want else User.query.first()\n"
    "        if not user:\n"
    "            print('no such user: %s' % (want or '(the table is empty)'))\n"
    "            return\n"
    "        print('user            : %s (%s)' % (user.name, user.uuid))\n"
    "        print('enabled         : %s' % user.enable)\n"
    "        print('usage           : %.3f of %.3f GB' % (user.current_usage_GB or 0, user.usage_limit_GB or 0))\n"
    "        print('days left       : %s of %s' % (user.remaining_days, user.package_days))\n"
    "        print('is_active       : %s' % user.is_active)\n"
    "        if not user.is_active:\n"
    "            print('  >> the link carries the ended package config only, which is the')\n"
    "            print('     panel working as designed, not the empty link bug.')\n"
    "        child = Child.current().id\n"
    "        cfgs = get_hconfigs(child)\n"
    "        switches = [k for k in ConfigEnum if k.type == bool and k.name.endswith('_enable')]\n"
    "        missing = [k for k in switches if k not in cfgs]\n"
    "        print('child           : %s' % child)\n"
    "        print('switch keys     : %d, missing from the database: %d' % (len(switches), len(missing)))\n"
    "        for key in missing:\n"
    "            print('   ? %s' % key.name)\n"
    "        if missing and not fix:\n"
    "            print('  >> a missing switch reads as off, and get_proxies() then drops every')\n"
    "            print('     proxy that needs it. Run again with --fix to write the safe')\n"
    "            print('     defaults for the ones a working panel cannot live without.')\n"
    "        if fix:\n"
    "            healed = []\n"
    "            for key in missing:\n"
    "                if key.name in WS_HEAL_ON:\n"
    "                    set_hconfig(key, True, child, commit=False)\n"
    "                    healed.append(key.name)\n"
    "            db.session.commit()\n"
    "            print('wrote defaults  : %s' % (', '.join(healed) or 'nothing needed'))\n"
    "        with app.test_request_context('/'):\n"
    "            g.account = user\n"
    "            g.user_agent = {'is_browser': False}\n"
    "            rows = Proxy.query.filter(Proxy.child_id == child).count()\n"
    "            kept = hutils.proxy.get_proxies(child, only_enabled=True)\n"
    "            domains = Domain.query.filter(Domain.child_id == child).all()\n"
    "            print('proxy rows      : %d, left after the switches: %d' % (rows, len(kept)))\n"
    "            print('domains         : %d' % len(domains))\n"
    "            for dom in domains[:20]:\n"
    "                print('   - %-40s mode=%s' % (dom.domain, dom.mode))\n"
    "            links = hutils.proxy.get_valid_proxies(domains)\n"
    "            print('configs in link : %d' % len(links))\n"
    "            for reason, count in sorted(ws_sub_reasons().items(), key=lambda pair: -pair[1])[:12]:\n"
    "                print('   x %-46s %d' % (reason, count))\n"
    "            if not links:\n"
    "                print('  >> the line above with the biggest number is the answer.')\n"
    "\n"
)

text = swap(text,
    "    @ app.cli.command()\n"
    "    @ click.option(\"--xui_db_path\", \"-x\")\n",
    NEW_CLI
    + "    @ app.cli.command()\n"
    + "    @ click.option(\"--xui_db_path\", \"-x\")\n",
    "the panel gained sub-doctor and unlock-login")

save(M + CLI, text, crlf)
check(MARK in text, "cli.py carries the round marker")
print("-- cli.py done")

# ------------------------------------------------------- does it still parse ---
for rel in (LOGIN, SHARED, CLI):
    try:
        py_compile.compile(M + rel, cfile="/tmp/w52.pyc", doraise=True)
        check(True, "python is happy: " + rel.split("/")[-1])
    except Exception as problem:
        check(False, "python is happy: " + rel.split("/")[-1] + " " + str(problem)[:90])

for rel in (LOGIN, PAGE, SHARED, CLI):
    raw = open(M + rel, "rb").read()
    check(b"\r\n" in raw and raw.replace(b"\r\n", b"").count(b"\n") == 0, "line endings kept: " + rel.split("/")[-1])
    old = open(M + rel + ".b52", "rb").read()
    check(raw != old, "changed: " + rel.split("/")[-1])

print("FAILURES: %d %s" % (len(fails), fails))
