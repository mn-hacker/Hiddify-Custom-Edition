"""watashi v12.2.48 checker, part 1: the files, the statics, and a live backup run."""
import os
import sys
import types
import time
import json
import datetime
import py_compile

M = "/data/state/fixm/"
P = "hiddify-panel/src/hiddifypanel/"
FILES = [
    P + "celery.py",
    P + "panel/cli.py",
    P + "panel/user_notifications.py",
    P + "panel/admin/Actions.py",
    P + "panel/admin/SettingAdmin.py",
    P + "models/config_enum.py",
]
fails = []


def say(ok, label, extra=""):
    print("%s %-62s %s" % ("OK  " if ok else "BAD ", label, extra))
    if not ok:
        fails.append(label)


def raw(path):
    with open(path, "r", encoding="utf-8", newline="") as f:
        return f.read()


def text(rel):
    return raw(M + rel).replace("\r\n", "\n")


def slice_of(body, start, end):
    i = body.find(start)
    j = body.find(end, i + 1)
    if i < 0:
        return ""
    return body[i:j] if j > i else body[i:]


def live(body):
    """Only the lines that really run: notes and dead comments must not fail a check."""
    return "\n".join(ln for ln in body.split("\n") if not ln.strip().startswith("#"))


print("-- 1. the files, their backups and their line endings")
for rel in FILES:
    p = M + rel
    b = p + ".b48"
    name = rel.split("/")[-1]
    say(os.path.exists(p), "%s is in the tree" % name, "%d B" % (os.path.getsize(p) if os.path.exists(p) else 0))
    say(os.path.exists(b), "%s has a .b48 backup" % name, "%d B" % (os.path.getsize(b) if os.path.exists(b) else 0))
    body = raw(p)
    say("\r\n" in body, "%s kept its windows line endings" % name)
    try:
        py_compile.compile(p, cfile="/tmp/w48c.pyc", doraise=True)
        say(True, "%s compiles" % name)
    except Exception as e:
        say(False, "%s compiles" % name, str(e)[:40])

print("-- 2. celery.py: the schedule that really runs")
cel = text(P + "celery.py")
say('hour="*/6"' not in live(cel), "the pinned every-6-hours schedule is gone")
say(cel.count('crontab(minute="30"),\n        backup_task.s()') == 2, "both paths wake the backup hourly",
    "%d place(s)" % cel.count('crontab(minute="30"),\n        backup_task.s()'))
say("backup_interval" not in live(cel), "the interval is no longer read at start up")
say(cel.count('name="backup_task"') == 2, "exactly one backup schedule per path")
say("watashi v12.2.48" in cel, "the round marker is there")
say('add_periodic_task(ws_interval' in cel, "the v12.2.47 usage schedule is untouched")

print("-- 3. cli.py: the backup task keeps its own time")
cli = text(P + "panel/cli.py")
say("def backup_task(force: bool = False)" in cli, "backup_task can be forced")
say("backup_task(force=True)" in cli, "the manual backup never waits for the clock")
say("AdminUser.telegram_id.isnot(None)" in cli, "the admin filter is real sql now")
say("AdminUser.telegram_id is not None" not in live(cli), "the python 'is not None' constant is gone")
say("test_notification, downgrade]" in cli, "the test command is registered")
say("isinstance(raw, bytes)" in cli, "redis bytes are decoded before float()")
say("ws_prune_backups" in cli, "old backups are pruned")

print("-- 4. the settings agree with each other")
enum = text(P + "models/config_enum.py")
line = [ln for ln in enum.split("\n") if ln.strip().startswith("backup_interval")]
say(len(line) == 1 and "ApplyMode" not in line[0], "backup_interval needs no apply/restart", line[0].strip()[:52] if line else "")
sett = text(P + "panel/admin/SettingAdmin.py")
say('"backup_interval": "6"' in sett, "the settings box defaults to 6, like init_db")
say('"backup_interval": "7"' not in sett, "the old mismatched 7 is gone")

print("-- 5. Actions.py: the two new buttons")
act = text(P + "panel/admin/Actions.py")
for needle, label in [
    ("@route('backup_now', methods=['POST'])", "the backup view is a POST route"),
    ("@route('test_notification', methods=['POST'])", "the test view is a POST route"),
    ("ac_url('backup_now')", "the backup card points at its own view"),
    ("ac_url('test_notification')", "the test card points at its own view"),
    ("'key': 'backupnow'", "the backup card is in the job list"),
    ("'key': 'testnotify'", "the test card is in the job list"),
]:
    say(needle in act, label)
say(act.count("    return jobs\n") == 1, "the job list still ends exactly once")
say(act.count("login_required") >= 12, "every view kept its login guard", "%d guards" % act.count("login_required"))
groups = set()
for ln in act.split("\n"):
    if "'group':" in ln:
        groups.add(ln.split(":")[1].strip().strip("',"))
say(groups <= {"daily", "watch", "fresh", "keys"}, "the new cards use groups the page knows", " ".join(sorted(groups)))

print("-- 6. a live backup run, with the real code and fake surroundings")


class FakeRedis:
    def __init__(self):
        self.store = {}

    def get(self, k):
        v = self.store.get(k)
        return v.encode() if isinstance(v, str) else v

    def set(self, k, v, **kw):
        self.store[k] = v
        return True


class Rec:
    def __init__(self):
        self.lines = []

    def _add(self, msg):
        self.lines.append(str(msg))

    def info(self, m):
        self._add(m)

    def warning(self, m):
        self._add(m)

    def error(self, m):
        self._add(m)

    def exception(self, m):
        self._add(m)


def build(interval_value, redis=None):
    """Run the real helpers and the real backup_task with stand-ins around them."""
    body = slice_of(cli, "WS_BACKUP_LAST_KEY", "def all_configs():")
    cache_mod = types.ModuleType("hiddifypanel.cache")
    cache_mod.redis_client = redis if redis is not None else FakeRedis()
    pkg = types.ModuleType("hiddifypanel")
    sys.modules["hiddifypanel"] = pkg
    sys.modules["hiddifypanel.cache"] = cache_mod

    class Enum:
        backup_interval = "backup_interval"
        telegram_bot_token = "telegram_bot_token"

    def hconfig(key):
        return interval_value if key == "backup_interval" else None

    hiddify = types.SimpleNamespace(dump_db_to_dict=lambda: {"users": []})
    ns = {
        "os": os, "json": json, "datetime": datetime,
        "hconfig": hconfig, "ConfigEnum": Enum,
        "hiddify": hiddify,
        "logger": Rec(),
        "shared_task": (lambda **kw: (lambda f: f)),
        "db": types.SimpleNamespace(session=None),
        "AdminUser": None, "AdminMode": None,
        "admin_links": lambda: "",
    }
    exec(compile(body, "cli_extract", "exec"), ns)
    ns["_redis"] = cache_mod.redis_client
    return ns


work = "/tmp/w48run"
os.makedirs(work, exist_ok=True)
os.chdir(work)
os.system("rm -rf %s/backup" % work)

ns = build("12")
say(ns["ws_backup_interval"]() == 12, "the interval comes from the panel", "12 hours")
for given, want, label in [("0", 0, "0 switches the automatic backup off"),
                           ("", 6, "an empty setting falls back to 6"),
                           ("junk", 6, "a broken setting falls back to 6"),
                           ("5000", 720, "a silly setting is clamped"),
                           ("-4", 0, "a negative setting means off"),
                           ("1", 1, "one hour is allowed")]:
    got = build(given)["ws_backup_interval"]()
    say(got == want, label, "%r becomes %s" % (given, got))

ns = build("6")
first = ns["backup_task"]()
say(first.get("status") == "ok", "the first run writes a backup", str(first.get("file")))
second = ns["backup_task"]()
say(second.get("status") == "skipped" and second.get("reason") == "too early",
    "a second run in the same hour is refused", str(second))
forced = ns["backup_task"](force=True)
say(forced.get("status") == "ok", "but the owner can always force one", str(forced.get("file")))
ns["_redis"].store["ws:backup:last-run"] = str(datetime.datetime.now().timestamp() - 6 * 3600)
late = ns["backup_task"]()
say(late.get("status") == "ok", "six hours later it runs on its own", str(late.get("file")))

off = build("0")
say(off["backup_task"]().get("reason") == "disabled", "with 0 hours nothing is written")
say(off["backup_task"](force=True).get("status") == "ok", "even switched off, a manual backup works")

one = build("1")
one["_redis"].store["ws:backup:last-run"] = str(datetime.datetime.now().timestamp() - 3000)
say(one["backup_task"]().get("reason") == "too early", "one hour means one hour, not fifty minutes")
one["_redis"].store["ws:backup:last-run"] = str(datetime.datetime.now().timestamp() - 3550)
say(one["backup_task"]().get("status") == "ok", "five minutes of slack, so :30 never slips an hour")

print("-- 7. the backup folder no longer grows for ever")
os.makedirs("backup", exist_ok=True)
for i in range(60):
    p = "backup/2026_01_%02d__00_00_%02d.json" % (i // 24 + 1, i % 60)
    with open(p, "w") as f:
        f.write("{}")
    os.utime(p, (time.time() - (60 - i) * 60, time.time() - (60 - i) * 60))
kept_before = len([n for n in os.listdir("backup") if n.endswith(".json")])
removed = build("6")["ws_prune_backups"]()
kept = len([n for n in os.listdir("backup") if n.endswith(".json")])
say(kept == 48, "only the newest 48 backups stay", "%d -> %d, %d removed" % (kept_before, kept, removed))

empty = build("6", redis=FakeRedis())
empty["_redis"].store.clear()
last = empty["ws_backup_last_run"]()
say(last > 0, "after a redis wipe the files themselves remember the time",
    datetime.datetime.fromtimestamp(last).strftime("%Y-%m-%d %H:%M"))

print("-- 8. what the old files did (.b48)")
say('hour="*/6"' in raw(M + P + "celery.py.b48"), "the old celery.py really was pinned to 6 hours")
say("AdminUser.telegram_id is not None" in raw(M + P + "panel/cli.py.b48"), "the old admin filter really was a python constant")
say('"backup_interval": "7"' in raw(M + P + "panel/admin/SettingAdmin.py.b48"), "the old settings box really said 7")
say("ws_ensure_bot" not in raw(M + P + "panel/user_notifications.py.b48"), "the old notifications really never woke the bot")

print("FAILURES: %d %s" % (len(fails), fails))
