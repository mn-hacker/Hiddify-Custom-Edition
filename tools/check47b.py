"""watashi v12.2.47 checker, part 2: celery, drivers, the setting, the db step,
the sing-box stats template, and a contrast against the .b47 originals."""
import json
import os
import re
import types

M = "/data/state/fixm/"
fails = []


def say(ok, label, extra=""):
    print("%s %-62s %s" % ("OK  " if ok else "BAD ", label, extra))
    if not ok:
        fails.append(label)


def read(rel):
    with open(M + rel, "r", encoding="utf-8", newline="") as f:
        return f.read().replace("\r\n", "\n")


P = "hiddify-panel/src/hiddifypanel/"
celery = read(P + "celery.py")
singbox = read(P + "drivers/singbox_api.py")
udriver = read(P + "drivers/user_driver.py")
enums = read(P + "models/config_enum.py")
initdb = read(P + "panel/init_db.py")
usage = read(P + "panel/usage.py")
tpl = read("singbox/configs/01_api.json.j2")

print("-- 4. celery.py")
say("add_periodic_task(60.0, usage.update_local_usage" not in celery, "the hard coded 60s poll is gone")
say(celery.count("usage.ws_usage_interval()") == 2, "both entry points read the setting",
    "%d sites" % celery.count("usage.ws_usage_interval()"))
say(celery.count("add_periodic_task(ws_interval, usage.update_local_usage.s()") == 2,
    "both entry points register the task with the setting")
halves = celery.split("def init_app_no_flask")
say(len(halves) == 2 and halves[0].count("ws_interval") >= 3 and halves[1].count("ws_interval") >= 3,
    "init_app and init_app_no_flask each got the change")
say("from loguru import logger" in celery, "the logger the new lines use is imported")
say("float(usage.WS_DEFAULT_INTERVAL)" in celery, "a bad setting falls back to the default")

print("-- 5. the drivers, run for real")


class FakeRedis:
    def __init__(self):
        self.sets = {}

    def sadd(self, key, value):
        self.sets.setdefault(key, set()).add(value)

    def expire(self, key, ttl):
        pass


class Rec:
    def __init__(self):
        self.lines = []

    def _log(self, m):
        self.lines.append(str(m))

    warning = info = debug = error = exception = _log


def methods_of(text, first, last=None):
    a = text.index(first)
    b = text.index(last) if last and text.index(last) > a else len(text)
    body = text[a:b]
    redis, log = FakeRedis(), Rec()

    class Cache:
        redis_client = redis

    ns = {"os": os, "json": json, "logger": log, "cache": Cache, "defaultdict": dict}
    exec(compile("class Probe:\n" + body, "driver_extract", "exec"), ns)
    return ns["Probe"](), redis, log


# 5a. get_enabled_users must survive a missing or broken 01_api.json
probe, redis, log = methods_of(singbox, "    def get_enabled_users(self):", "    @cache.cache(")
os.environ["HIDDIFY_CONFIG_PATH"] = "/tmp/w47missing"
say(probe.get_enabled_users() == {}, "a missing 01_api.json answers empty instead of raising")
os.makedirs("/tmp/w47cfg/singbox/configs", exist_ok=True)
os.environ["HIDDIFY_CONFIG_PATH"] = "/tmp/w47cfg"
with open("/tmp/w47cfg/singbox/configs/01_api.json", "w") as f:
    f.write('{"experimental": {"v2ray_api": {"stats": {"users": [')
say(probe.get_enabled_users() == {}, "a half written 01_api.json answers empty instead of raising")
with open("/tmp/w47cfg/singbox/configs/01_api.json", "w") as f:
    json.dump({"experimental": {"v2ray_api": {"stats": {"users": [
        "aaa@hiddify.com", "aaa", "bbb@hiddify.com", "bbb", "  "]}}}}, f)
got = probe.get_enabled_users()
say(got == {"aaa": 1, "bbb": 1}, "both name spellings fold onto one user", str(got))
os.environ.pop("HIDDIFY_CONFIG_PATH", None)
say(probe.get_enabled_users() == {}, "no KeyError when HIDDIFY_CONFIG_PATH is unset")

# 5b. add_client / remove_client say what they really do
probe, redis, log = methods_of(singbox, "    def _ws_queue(self, action, user):")
user = types.SimpleNamespace(uuid="u-42")
probe.add_client(user)
probe.remove_client(user)
say(redis.sets.get("ws:singbox:pending-add") == {"u-42"}, "an add is recorded", str(redis.sets))
say(redis.sets.get("ws:singbox:pending-remove") == {"u-42"}, "a remove is recorded")
say(all("config rebuild" in line for line in log.lines) and len(log.lines) == 2,
    "the log explains why sing-box is not instant", str(log.lines[:1]))
say("    def add_client(self, user):\n        pass" not in singbox, "the silent pass bodies are gone")

# 5c. reset really reaches a driver that understands it
body = udriver[udriver.index("def ws_call_get_all_usage"):udriver.index("def get_users_usage(")]
log = Rec()
ns = {"logger": log}
exec(compile(body, "udriver_extract", "exec"), ns)
calls = []


class NewStyle:
    def get_all_usage(self, reset=True):
        calls.append(("new", reset))
        return {"u1": 5}


class OldStyle:
    def get_all_usage(self):
        calls.append(("old", None))
        return {"u1": 7}


ns["ws_call_get_all_usage"](NewStyle(), True)
ns["ws_call_get_all_usage"](NewStyle(), False)
ns["ws_call_get_all_usage"](OldStyle(), True)
ns["ws_call_get_all_usage"](OldStyle(), False)
say(calls == [("new", True), ("new", False), ("old", None), ("old", None)],
    "reset is forwarded, old drivers still work", str(calls))
say(any("without resetting" in line for line in log.lines), "a driver that cannot peek is logged")
say("all_usage = ws_call_get_all_usage(driver, reset)" in udriver, "get_users_usage uses the helper")
say("def get_all_usage(self, reset: bool = True):" in singbox, "the sing-box driver declares reset")
say("stats_query('user', reset=reset)" in singbox, "the sing-box driver passes reset through")

# 5d. the dead ip code
say("Error getting IPs from Redis" not in udriver, "the unreachable redis ip code is gone")
ips = udriver[udriver.index("def get_user_ips"):udriver.index("def is_user_online")]
returns = [ln for ln in ips.split("\n") if ln.strip().startswith("return ")]
say(len(returns) == 1 and len(ips.strip().split("\n")) < 12, "get_user_ips is a short honest stub",
    "%d lines" % len(ips.strip().split("\n")))

print("-- 6. the new setting and the database step")
say(enums.count("usage_update_interval = _IntConfigDscr(ConfigCategory.advanced)") == 1,
    "config_enum.py declares usage_update_interval once")
say(re.search(r"^    usage_update_interval\s*=", enums, re.M) is not None, "it is a real ConfigEnum member")
say("usage_update_interval" in usage and "usage_update_interval" in initdb,
    "usage.py and init_db.py use the very same key name")
say("MAX_DB_VERSION = 144" in initdb, "MAX_DB_VERSION is 144")
say("def _v144(child_id):" in initdb, "_v144 exists")
say("add_config_if_not_exist(key, 30)" in initdb, "_v144 seeds 30 seconds")
say(initdb.index("def _v144") < initdb.index("def _v143"), "_v144 sits next to its neighbour")
say("for ver in range(1, MAX_DB_VERSION + 1)" in initdb, "the upgrade loop still reaches the last step")
dispatch = [ln.strip() for ln in initdb.split("\n") if "_v{" in ln or "'_v'" in ln or '"_v"' in ln]
say(len(dispatch) > 0, "the migration dispatcher finds steps by name", dispatch[0][:60] if dispatch else "none")

print("-- 7. singbox/configs/01_api.json.j2 rendered")
users = [{"uuid": "aaa"}, {"uuid": "bbb"}]
try:
    import jinja2
    out = jinja2.Template(tpl).render(users=users, hconfigs={})
    how = "jinja2"
except ImportError:
    body = re.search(r"\{% for u in users %\}(.*?)\{% endfor%\}", tpl, re.S).group(1)
    out = tpl[:tpl.index("{% for u in users %}")] \
        + "".join(body.replace("{{ u['uuid'] }}", u["uuid"]) for u in users) \
        + tpl[tpl.index("{% endfor%}") + len("{% endfor%}"):]
    how = "manual expansion"
clean = re.sub(r"^[ \t]*//[^\n]*$", "", out, flags=re.M)  # only whole comment lines, never inside a url
clean = re.sub(r",(\s*[\]}])", r"\1", clean)
try:
    doc = json.loads(clean)
    names = doc["experimental"]["v2ray_api"]["stats"]["users"]
    say(True, "the template still renders valid json (%s)" % how, "%d names" % len(names))
    say(names == ["aaa@hiddify.com", "aaa", "bbb@hiddify.com", "bbb"], "every user is counted under both names", str(names))
    say(doc["experimental"]["v2ray_api"]["stats"]["enabled"] is True, "the stats block is still enabled")
except Exception as e:
    say(False, "the template still renders valid json (%s)" % how, str(e)[:60])

print("-- 8. contrast: what the .b47 originals did")
old_usage = read(P + "panel/usage.py.b47")
old_celery = read(P + "celery.py.b47")
old_singbox = read(P + "drivers/singbox_api.py.b47")
old_udriver = read(P + "drivers/user_driver.py.b47")
old_tpl = read("singbox/configs/01_api.json.j2.b47")
say("# if not cache.redis_client.set(lock_key" in old_usage, "the old usage.py really had the lock commented out")
say("ws:usage:pending" not in old_usage, "the old usage.py had no journal")
say("add_periodic_task(60.0" in old_celery, "the old celery.py really polled every 60s")
say("    def add_client(self, user):\n        pass" in old_singbox, "the old driver really did nothing on add")
say("Error getting IPs from Redis" in old_udriver, "the old user_driver really carried dead code")
say(old_tpl.count("u['uuid'] }}\"") == 0 and '"{{ u[\'uuid\'] }}@hiddify.com",' in old_tpl,
    "the old template listed only the @hiddify.com name")

print("FAILURES: %d %s" % (len(fails), fails))
