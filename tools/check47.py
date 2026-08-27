"""watashi v12.2.47 checker, part 1: files, usage.py static, usage.py live."""
import json
import os
import py_compile
import types

M = "/data/state/fixm/"
B = ".b47"
fails = []


def say(ok, label, extra=""):
    print("%s %-62s %s" % ("OK  " if ok else "BAD ", label, extra))
    if not ok:
        fails.append(label)


def read(rel):
    with open(M + rel, "r", encoding="utf-8", newline="") as f:
        return f.read()


FILES = {
    "hiddify-panel/src/hiddifypanel/panel/usage.py": True,
    "hiddify-panel/src/hiddifypanel/celery.py": True,
    "hiddify-panel/src/hiddifypanel/drivers/singbox_api.py": True,
    "hiddify-panel/src/hiddifypanel/drivers/user_driver.py": True,
    "hiddify-panel/src/hiddifypanel/models/config_enum.py": True,
    "hiddify-panel/src/hiddifypanel/panel/init_db.py": True,
    "hiddify-panel/src/hiddifypanel/hutils/proxy/shared.py": True,
    "singbox/configs/01_api.json.j2": False,
}

print("-- 1. files, backups, line endings, syntax")
for rel, want_crlf in FILES.items():
    raw = read(rel)
    name = os.path.basename(rel)
    say(os.path.exists(M + rel + B), "backup exists: " + name, "%d bytes" % os.path.getsize(M + rel))
    say(("\r\n" in raw) == want_crlf, "line endings kept: " + name, "crlf" if want_crlf else "lf")
    if rel.endswith(".py"):
        try:
            py_compile.compile(M + rel, cfile="/tmp/w47.pyc", doraise=True)
            say(True, "compiles: " + name)
        except Exception as e:
            say(False, "compiles: " + name, str(e)[:60])

usage = read("hiddify-panel/src/hiddifypanel/panel/usage.py").replace("\r\n", "\n")

print("-- 2. panel/usage.py, read statically")
say('set(lock_key, "locked", nx=True' in usage, "the lock is really taken (nx=True)")
say("# if not cache.redis_client.set(lock_key" not in usage, "the commented out lock is gone")
say("cache.redis_client.delete(lock_key)" in usage, "the lock is released in finally")
say('nx=False' not in usage, "the old nx=False relock is gone")
say("def ws_usage_interval" in usage and "min(600, max(10," in usage, "the interval helper clamps 10..600")
say("ws_save_pending(merged)" in usage and usage.index("ws_save_pending(merged)") < usage.index("add_users_usage_new(\n"),
    "the journal is written before the database call")
say("on_usage_committed=None" in usage, "add_users_usage_new takes the commit callback")
say("if on_usage_committed is not None:" in usage, "the callback fires after the db call")
say("ws_apply_users_once()" in usage, "apply-users goes through the debounce")
live_apply = [ln for ln in usage.split("\n") if "hiddify.quick_apply_users()" in ln and not ln.strip().startswith("#")]
say(len(live_apply) == 1, "only the debounce calls apply-users directly", "%d live call sites" % len(live_apply))
say("core_only" in usage and "its package is finished" in usage, "the idle cut-off sweep is there")

print("-- 3. panel/usage.py, run for real against fakes")


class FakeRedis:
    def __init__(self):
        self.kv = {}
        self.sets = {}
        self.down = False

    def _c(self):
        if self.down:
            raise RuntimeError("redis is down")

    def set(self, key, value, nx=False, ex=None):
        self._c()
        if nx and key in self.kv:
            return None
        self.kv[key] = value
        return True

    def get(self, key):
        self._c()
        return self.kv.get(key)

    def delete(self, key):
        self._c()
        self.kv.pop(key, None)

    def sadd(self, key, value):
        self._c()
        self.sets.setdefault(key, set()).add(value)

    def expire(self, key, ttl):
        self._c()


class Rec:
    def __init__(self):
        self.lines = []

    def _log(self, msg):
        self.lines.append(str(msg))

    warning = info = debug = error = exception = trace = _log


def build(interval_value=30):
    head = usage.index("WS_PENDING_KEY = ")
    mid = usage.index("@shared_task(ignore_result=True)")
    end = usage.index("def add_users_usage_uuid(")
    src = usage[head:mid] + "\n" + usage[mid:end]
    redis = FakeRedis()
    log = Rec()
    st = {"drains": 0, "batches": [], "fail_db": False, "applies": 0, "next": {}}

    class Cache:
        redis_client = redis

    class Drivers:
        @staticmethod
        def get_users_usage(reset=True):
            st["drains"] += 1
            return st["next"]

    class Hiddify:
        @staticmethod
        def quick_apply_users():
            st["applies"] += 1

    def add_users_usage_new(usages, child_id, on_usage_committed=None):
        st["batches"].append(sorted((u["uuid"], u["usage"]) for u in usages))
        if st["fail_db"]:
            raise RuntimeError("the database said no")
        if on_usage_committed:
            on_usage_committed()
        return {"status": "success"}

    ns = {
        "Dict": dict, "json": json, "logger": log, "cache": Cache,
        "user_driver": Drivers, "hiddify": Hiddify,
        "add_users_usage_new": add_users_usage_new,
        "shared_task": lambda **kw: (lambda f: f),
        "hconfig": lambda key: interval_value,
        "ConfigEnum": types.SimpleNamespace(usage_update_interval="k"),
    }
    exec(compile(src, "usage_extract", "exec"), ns)
    return ns, redis, st, log


# 3a. the interval clamp
for raw, want in ((30, 30), (5, 10), (0, 30), (900, 600), (None, 30), ("junk", 30)):
    ns, _, _, _ = build(raw)
    got = ns["ws_usage_interval"]()
    say(got == want, "interval %r becomes %r" % (raw, want), "got %r" % got)

# 3b. the happy path
ns, redis, st, log = build()
st["next"] = {"u1": {"usage": 1000}, "u2": {"usage": 0}}
ns["update_local_usage"]()
say(st["batches"] == [[("u1", 1000)]], "only real traffic reaches the database", str(st["batches"]))
say(redis.get("ws:usage:pending") is None, "the journal is empty once the database took it")
say("lock-update-local-usage" not in redis.kv, "the lock is gone after the run")
say(redis.get("ws:usage:last-run") is not None, "the heartbeat is written")

# 3c. a failing database must not lose bytes, and must not double count
ns, redis, st, log = build()
st["fail_db"] = True
st["next"] = {"u1": {"usage": 50 * 1024 ** 3}}
ns["update_local_usage"]()
kept = json.loads(redis.get("ws:usage:pending"))
say(kept == {"u1": 50 * 1024 ** 3}, "a failed write keeps the bytes in the journal", str(kept))
say("lock-update-local-usage" not in redis.kv, "the lock is released even after a failure")
st["fail_db"] = False
st["next"] = {"u1": {"usage": 5 * 1024 ** 3}}
ns["update_local_usage"]()
say(st["batches"][-1] == [("u1", 55 * 1024 ** 3)], "the next run stores drained plus journalled",
    str(st["batches"][-1]))
say(redis.get("ws:usage:pending") is None, "the journal clears after the retry")
st["next"] = {}
ns["update_local_usage"]()
say(st["batches"][-1] == [], "nothing is counted twice on the following run", str(st["batches"][-1]))

# 3d. two overlapping runs: the second must not drain the cores
ns, redis, st, log = build()
redis.set("lock-update-local-usage", "locked")
st["next"] = {"u1": {"usage": 7}}
res = ns["update_local_usage"]()
say(st["drains"] == 0, "a locked out run never drains the cores", "drains=%d" % st["drains"])
say(res.get("msg", "").startswith("last update task"), "the locked out run says so", str(res))

# 3e. redis down: the accounting still runs, memory keeps the bytes
ns, redis, st, log = build()
redis.down = True
st["fail_db"] = True
st["next"] = {"u1": {"usage": 800}}
ns["update_local_usage"]()
say(st["drains"] == 1, "a redis outage does not stop the accounting")
st["fail_db"] = False
st["next"] = {"u1": {"usage": 200}}
ns["update_local_usage"]()
say(st["batches"][-1] == [("u1", 1000)], "the memory journal survives a redis outage", str(st["batches"][-1]))

# 3f. the apply-users debounce
ns, redis, st, log = build()
for _ in range(4):
    ns["ws_apply_users_once"](min_gap=60)
say(st["applies"] == 1, "four cut-offs in one minute start one apply-users", "applies=%d" % st["applies"])
say(any("not starting a second one" in line for line in log.lines), "the skipped applies are logged")

print("FAILURES: %d %s" % (len(fails), fails))
