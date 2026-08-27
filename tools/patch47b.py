"""
watashi v12.2.47 - part 2 of 2: the cores, the new setting and the DB step.

Findings, all read from the real files:

6. singbox/configs/01_api.json.j2 listed only "<uuid>@hiddify.com" in
   experimental.v2ray_api.stats.users. sing-box attributes traffic to the user
   *name* the inbound authenticated. vless/vmess/trojan/hysteria/tuic/ss all
   use "<uuid>@hiddify.com" (protocols/*.pj2), but naive authenticates with
   "username": "<uuid>" (05_inbounds_4300_naive.json.j2) and mieru with
   "username": "<uuid>" (protocols/mieru.pj2). Their traffic was therefore
   never counted at all, so those users never ran out of quota. Both spellings
   are listed now; the driver already splits on "@", so both land on one uuid.
7. drivers/singbox_api.py: add_client/remove_client were bare "pass" with no
   explanation, which reads like a bug. sing-box exposes StatsService only (no
   live user management), so a real cut-off needs a config rebuild + reload.
   They now record the request and say so in the log.
8. drivers/singbox_api.py: get_enabled_users() raised when 01_api.json was
   missing or half written, and every caller only logged the traceback.
9. drivers/user_driver.py: get_user_ips() carried ~25 lines of unreachable
   code after "return set()".
10. hutils/proxy/shared.py: the mieru fallback appended tracebacks to
    /tmp/mieru_debug.log for ever, where nobody looks.
11. models/config_enum.py + panel/init_db.py: the new usage_update_interval
    setting (seconds, default 30) with an idempotent _v144 step.
"""
import os
import shutil

SRC = "/data/state/src3/"
M = "/data/state/fixm/"
SUFFIX = ".b47"
MARK = "watashi v12.2.47"

fails = []


def say(ok, label, extra=""):
    print("%s %-58s %s" % ("OK  " if ok else "BAD ", label, extra))
    if not ok:
        fails.append(label)


def bring(rel):
    dst = M + rel
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    if not os.path.exists(dst):
        shutil.copy2(SRC + rel, dst)
        print("     brought %s" % rel)
    return dst


def load(path):
    with open(path, "r", encoding="utf-8", newline="") as f:
        raw = f.read()
    crlf = "\r\n" in raw
    return raw.replace("\r\n", "\n"), crlf


def save(path, text, crlf):
    out = text.replace("\n", "\r\n") if crlf else text
    with open(path, "w", encoding="utf-8", newline="") as f:
        f.write(out)


def backup(path):
    if not os.path.exists(path + SUFFIX):
        shutil.copy2(path, path + SUFFIX)


def swap(text, old, new, label, count=1):
    n = text.count(old)
    if n != count:
        say(False, label, "wanted %d matches, found %d" % (count, n))
        return text
    say(True, label)
    return text.replace(old, new)


def cut(text, head, tail, new, label):
    """Replace everything from head up to (not including) tail."""
    if text.count(head) != 1 or text.count(tail) != 1 or text.index(head) > text.index(tail):
        say(False, label, "anchors not unique or out of order")
        return text
    say(True, label)
    return text[:text.index(head)] + new + text[text.index(tail):]


# --------------------------------------------------------- 1. singbox driver
OLD_ENABLED = '''    def get_enabled_users(self):
        config_dir = os.environ['HIDDIFY_CONFIG_PATH']
        with open(f"{config_dir}/singbox/configs/01_api.json") as f:
            json_data = json.load(f)
            return {u.split("@")[0]: 1 for u in json_data['experimental']['v2ray_api']['stats']['users']}'''

NEW_ENABLED = '''    def get_enabled_users(self):
        # watashi v12.2.47: this file is rewritten by apply-users, so a read can
        # land on a missing or half written file. That used to raise on every
        # poll; an unknown list is answered as empty instead, and the bare uuid
        # spelling (naive, mieru) maps onto the same user as uuid@hiddify.com.
        config_dir = os.environ.get('HIDDIFY_CONFIG_PATH', '/opt/hiddify-manager')
        path = f"{config_dir}/singbox/configs/01_api.json"
        try:
            with open(path) as f:
                json_data = json.load(f)
            names = json_data['experimental']['v2ray_api']['stats']['users']
        except FileNotFoundError:
            logger.debug(f"singbox: {path} does not exist yet")
            return {}
        except Exception as e:
            logger.warning(f"singbox: cannot read {path} ({e})")
            return {}
        return {str(n).split("@")[0]: 1 for n in names if str(n).strip()}'''

OLD_CLIENT = '''    def add_client(self, user):
        pass

    def remove_client(self, user):
        pass'''

NEW_CLIENT = '''    def _ws_queue(self, action, user):
        # watashi v12.2.47: sing-box has no live user management. Its V2Ray API
        # is StatsService only (GetStats/QueryStats/GetSysStats), so a user can
        # be added or cut off only by rebuilding the configs and reloading the
        # service, which is what hiddify.quick_apply_users() does. We record the
        # request here so the log shows why the change is not instant, and so a
        # later round can rebuild only what changed.
        uuid = getattr(user, 'uuid', user)
        try:
            key = f"ws:singbox:pending-{action}"
            cache.redis_client.sadd(key, str(uuid))
            cache.redis_client.expire(key, 3600)
        except Exception:
            pass
        logger.info(f"singbox: {action} {uuid} queued; sing-box needs a config rebuild to apply it")

    def add_client(self, user):
        self._ws_queue('add', user)

    def remove_client(self, user):
        self._ws_queue('remove', user)'''

print("-- 1. drivers/singbox_api.py")
p = bring("hiddify-panel/src/hiddifypanel/drivers/singbox_api.py")
text, crlf = load(p)
if MARK in text:
    say(True, "singbox_api.py is already patched", "nothing to do")
else:
    backup(p)
    text = swap(text, OLD_ENABLED, NEW_ENABLED, "singbox_api.py: enabled list survives a bad file")
    text = swap(text, OLD_CLIENT, NEW_CLIENT, "singbox_api.py: add/remove are honest now")
    save(p, text, crlf)
    print("     size %d bytes, crlf=%s" % (os.path.getsize(p), crlf))

# ------------------------------------------------------------ 2. user_driver
NEW_IPS = '''def get_user_ips(uuid: str) -> set:
    """The IP based limiter was removed, so there is nothing to report.

    watashi v12.2.47: the ~25 lines of unreachable code that used to sit after
    the return were deleted. Callers already treat an empty set as unknown.
    """
    return set()


'''

print("-- 2. drivers/user_driver.py")
p = bring("hiddify-panel/src/hiddifypanel/drivers/user_driver.py")
text, crlf = load(p)
if MARK in text:
    say(True, "user_driver.py is already patched", "nothing to do")
else:
    backup(p)
    before = len(text)
    text = cut(text, "def get_user_ips(uuid: str) -> set:", "def is_user_online(uuid: str) -> bool:",
               NEW_IPS, "user_driver.py: dead ip code removed")
    say(len(text) < before, "user_driver.py: the file got shorter", "%d -> %d bytes" % (before, len(text)))
    save(p, text, crlf)
    print("     size %d bytes, crlf=%s" % (os.path.getsize(p), crlf))

# ------------------------------------------------------------ 3. config_enum
print("-- 3. models/config_enum.py")
p = bring("hiddify-panel/src/hiddifypanel/models/config_enum.py")
text, crlf = load(p)
if "usage_update_interval" in text:
    say(True, "config_enum.py already has the key", "nothing to do")
else:
    backup(p)
    anchor = "    last_priodic_usage_check = _IntConfigDscr(ConfigCategory.hidden)\n"
    added = anchor + "    # watashi v12.2.47: seconds between two usage polls (10..600, default 30).\n" \
                     "    # The cut-off can never be faster than this, so it must be reachable.\n" \
                     "    usage_update_interval = _IntConfigDscr(ConfigCategory.advanced)\n"
    text = swap(text, anchor, added, "config_enum.py: usage_update_interval added")
    save(p, text, crlf)
    print("     size %d bytes, crlf=%s" % (os.path.getsize(p), crlf))

# --------------------------------------------------------------- 4. init_db
STEP = '''def _v144(child_id):
    # watashi v12.2.47: how often the panel drains the cores. 60s was hard coded
    # in celery.py, so a user could burn several GB between two polls before the
    # panel noticed the package was finished. 30s is the new default and the
    # owner can change it in the settings. add_config_if_not_exist writes
    # nothing when the key already has a value, so re-running is safe.
    key = getattr(ConfigEnum, 'usage_update_interval', None)
    if key is not None:
        add_config_if_not_exist(key, 30)
    logger.info('watashi: the usage poll interval is a setting now')


'''

print("-- 4. panel/init_db.py")
p = bring("hiddify-panel/src/hiddifypanel/panel/init_db.py")
text, crlf = load(p)
if "_v144" in text:
    say(True, "init_db.py already has the step", "nothing to do")
else:
    backup(p)
    text = swap(text, "MAX_DB_VERSION = 143", "MAX_DB_VERSION = 144", "init_db.py: db version 144")
    text = swap(text, "def _v143(child_id):", STEP + "def _v143(child_id):", "init_db.py: _v144 in front of _v143")
    save(p, text, crlf)
    print("     size %d bytes, crlf=%s" % (os.path.getsize(p), crlf))

# ---------------------------------------------------------------- 5. shared
OLD_DEBUG = '''        except Exception:
            import traceback
            try:
                with open("/tmp/mieru_debug.log", "a") as f:
                    f.write(traceback.format_exc())
            except:
                pass
            # Fallback to avoid crash'''

NEW_DEBUG = '''        except Exception:
            # watashi v12.2.47: this used to append tracebacks to
            # /tmp/mieru_debug.log for ever, where nobody looks and nothing
            # rotates. It goes to the panel log with the rest of the story now.
            logger.exception("mieru: cannot build the port bindings; falling back to empty lists")
            # Fallback to avoid crash'''

print("-- 5. hutils/proxy/shared.py")
p = bring("hiddify-panel/src/hiddifypanel/hutils/proxy/shared.py")
text, crlf = load(p)
if MARK in text:
    say(True, "shared.py is already patched", "nothing to do")
else:
    backup(p)
    text = swap(text, OLD_DEBUG, NEW_DEBUG, "shared.py: the /tmp debug writer is gone")
    if "from loguru import logger" not in text:
        first = text.index("\n") + 1
        text = text[:first] + "from loguru import logger\n" + text[first:]
        say(True, "shared.py: loguru import added")
    else:
        say(True, "shared.py: loguru was already imported")
    say("/tmp/mieru_debug.log" not in text, "shared.py: no /tmp path left")
    save(p, text, crlf)
    print("     size %d bytes, crlf=%s" % (os.path.getsize(p), crlf))

# --------------------------------------------------------------- 6. 01_api.j2
T = "\t"
OLD_STATS = (T * 4 + '"users": [\n'
             + T * 5 + '{% for u in users %}\n'
             + T * 6 + '"{{ u[\'uuid\'] }}@hiddify.com",\n'
             + T * 5 + '{% endfor%}\n'
             + T * 4 + ']')

NEW_STATS = (T * 4 + '// watashi v12.2.47: sing-box counts traffic against the user *name* the\n'
             + T * 4 + '// inbound authenticated. vless/vmess/trojan/hysteria/tuic/ss use\n'
             + T * 4 + '// "<uuid>@hiddify.com", but naive and mieru authenticate with the bare\n'
             + T * 4 + '// uuid, so their traffic was never counted and those users never ran\n'
             + T * 4 + '// out of quota. Both spellings are listed; the panel splits on "@".\n'
             + T * 4 + '"users": [\n'
             + T * 5 + '{% for u in users %}\n'
             + T * 6 + '"{{ u[\'uuid\'] }}@hiddify.com",\n'
             + T * 6 + '"{{ u[\'uuid\'] }}",\n'
             + T * 5 + '{% endfor%}\n'
             + T * 4 + ']')

print("-- 6. singbox/configs/01_api.json.j2")
p = bring("singbox/configs/01_api.json.j2")
text, crlf = load(p)
if MARK in text:
    say(True, "01_api.json.j2 is already patched", "nothing to do")
else:
    backup(p)
    text = swap(text, OLD_STATS, NEW_STATS, "01_api.json.j2: bare uuid is counted too")
    save(p, text, crlf)
    print("     size %d bytes, crlf=%s" % (os.path.getsize(p), crlf))

print("FAILURES: %d %s" % (len(fails), fails))
