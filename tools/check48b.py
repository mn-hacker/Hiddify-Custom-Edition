"""watashi v12.2.48 checker, part 2: the notification code, run for real."""
import os
import sys
import types
import datetime

M = "/data/state/fixm/"
P = "hiddify-panel/src/hiddifypanel/"
REL = P + "panel/user_notifications.py"
fails = []


def say(ok, label, extra=""):
    print("%s %-62s %s" % ("OK  " if ok else "BAD ", label, extra))
    if not ok:
        fails.append(label)


with open(M + REL, "r", encoding="utf-8", newline="") as f:
    body = f.read().replace("\r\n", "\n")


def live(t):
    return "\n".join(ln for ln in t.split("\n") if not ln.strip().startswith("#"))


print("-- 1. what the task now does before it sends anything")
guard = body.find("if not ws_ensure_bot():")
loop = body.find("for user in users_with_telegram:")
say(0 < guard < loop, "the bot is woken before the first user is touched")
say("ws_usage_heartbeat_alarm()" in live(body), "the frozen-usage alarm runs once an hour")
say("0 <= user.remaining_days <= notify_expiry_days" in body, "the last day of a subscription is warned about")
say("max(10, notify_usage_percent - 30)" in body, "the 80% flag clears relative to the setting")
say("< 50:" not in live(body), "the hard coded 50% is gone")
say(body.count("msg += ws_usage_block(user)") == 3, "all three messages use the safe usage block",
    "%d place(s)" % body.count("msg += ws_usage_block(user)"))
say("Usage.get_usage_msg(user.uuid)" not in body.split("def ws_usage_block")[0],
    "no message calls the fragile builder directly any more")
say('logger.info(' in body and 'notifications sent - expiry' in body, "the hourly result is written to the log")
for name in ["ws_ensure_bot", "ws_usage_block", "ws_notify_admins", "ws_usage_heartbeat_alarm", "ws_send_test_notification"]:
    say(("def %s(" % name) in body, "%s exists" % name)

print("-- 2. the live harness")


class Rec:
    def __init__(self):
        self.lines = []

    def info(self, m):
        self.lines.append("info: %s" % m)

    def warning(self, m):
        self.lines.append("warn: %s" % m)

    def error(self, m):
        self.lines.append("error: %s" % m)

    def exception(self, m):
        self.lines.append("exc: %s" % m)


class FakeBot:
    def __init__(self, explode=False):
        self.token = "1:2"
        self.username = ""
        self.sent = []
        self.explode = explode

    def send_message(self, chat, text, **kw):
        if self.explode:
            raise Exception("404 Unauthorized")
        self.sent.append((chat, text))


class FakeRedis:
    def __init__(self):
        self.store = {}

    def get(self, k):
        v = self.store.get(k)
        return v.encode() if isinstance(v, str) else v

    def set(self, k, v, **kw):
        self.store[k] = v
        return True


class Q:
    def __init__(self, rows):
        self.rows = rows

    def filter(self, *a, **kw):
        return self

    def all(self):
        return self.rows


def build(token="777:realtoken", admins=None, explode=False, usage_ok=False, stamp=None, interval=30):
    """Run the real helper functions with stand-ins for flask, telebot and redis."""
    bot = FakeBot(explode)
    calls = {"register": 0}

    def register_bot(set_hook=False, remove_hook=False):
        calls["register"] += 1
        calls["hook"] = set_hook
        if token:
            bot.token = token
            bot.username = "ws_test_bot"

    def get_usage_msg(uuid, domain=None):
        if usage_ok:
            return "5.00 GB from 50.00 GB"
        raise IndexError("list index out of range")

    tg = types.ModuleType("hiddifypanel.panel.commercial.telegrambot")
    tg.bot = bot
    tg.register_bot = register_bot
    tg.Usage = types.SimpleNamespace(get_usage_msg=get_usage_msg, user_keyboard=lambda uuid: None)

    class AdminMode:
        super_admin = "super_admin"

    class AdminUser:
        mode = types.SimpleNamespace(__eq__=lambda self, other: True)
        telegram_id = types.SimpleNamespace(isnot=lambda x: True, __ne__=lambda self, o: True)

    models = types.ModuleType("hiddifypanel.models")
    models.AdminUser = AdminUser
    models.AdminMode = AdminMode

    cache = types.ModuleType("hiddifypanel.cache")
    cache.redis_client = FakeRedis()
    if stamp is not None:
        cache.redis_client.store["ws:usage:last-run"] = str(stamp)

    usage_mod = types.ModuleType("hiddifypanel.panel.usage")
    usage_mod.WS_LAST_RUN_KEY = "ws:usage:last-run"
    usage_mod.ws_usage_interval = lambda: interval

    for name, mod in [
        ("hiddifypanel", types.ModuleType("hiddifypanel")),
        ("hiddifypanel.panel", types.ModuleType("hiddifypanel.panel")),
        ("hiddifypanel.panel.commercial", types.ModuleType("hiddifypanel.panel.commercial")),
        ("hiddifypanel.panel.commercial.telegrambot", tg),
        ("hiddifypanel.models", models),
        ("hiddifypanel.cache", cache),
        ("hiddifypanel.panel.usage", usage_mod),
    ]:
        sys.modules[name] = mod

    class Enum:
        telegram_bot_token = "telegram_bot_token"

    rows = admins if admins is not None else [types.SimpleNamespace(telegram_id=555, name="owner")]
    ns = {
        "datetime": datetime,
        "logger": Rec(),
        "hconfig": (lambda key: token),
        "ConfigEnum": Enum,
        "db": types.SimpleNamespace(session=types.SimpleNamespace(query=lambda model: Q(rows))),
        "User": types.SimpleNamespace(by_uuid=lambda u: types.SimpleNamespace(
            telegram_id=999, name="a user", uuid=u, current_usage_GB=1.0, usage_limit_GB=2.0)),
    }
    exec(compile(body[body.find("def ws_ensure_bot"):], "notify_extract", "exec"), ns)
    ns["_bot"] = bot
    ns["_calls"] = calls
    ns["_redis"] = cache.redis_client
    return ns


print("-- 3. the dead token, which is the whole bug")
ns = build(token=None)
say(ns["ws_ensure_bot"]() is False, "with no token saved the task refuses to send")
ns = build()
say(ns["_bot"].token == "1:2", "the bot object really starts with the placeholder token")
ok = ns["ws_ensure_bot"]()
say(ok and ns["_bot"].token == "777:realtoken", "one call turns it into the real bot", ns["_bot"].token)
say(ns["_calls"]["register"] == 1 and ns["_calls"]["hook"] is False, "the webhook is left alone",
    "register calls: %d" % ns["_calls"]["register"])
ns["ws_ensure_bot"]()
say(ns["_calls"]["register"] == 1, "a second call does not re-register for nothing")

print("-- 4. the message body survives a panel without a domain")
ns = build(usage_ok=False)
user = types.SimpleNamespace(uuid="u1", name="a user", current_usage_GB=1.0, usage_limit_GB=2.0)
say(ns["ws_usage_block"](user) == "1.00 GB / 2.00 GB", "a broken usage message falls back to plain numbers",
    ns["ws_usage_block"](user))
ns = build(usage_ok=True)
say("5.00 GB" in ns["ws_usage_block"](user), "a healthy panel keeps the rich message")

print("-- 5. reaching the admins")
ns = build()
say(ns["ws_notify_admins"]("hello") == 1, "the admin gets exactly one message")
say(ns["_bot"].sent and ns["_bot"].sent[0][0] == 555, "it went to the right chat id", str(ns["_bot"].sent[0][0]))
ns = build(explode=True)
say(ns["ws_notify_admins"]("hello") == 0, "a telegram error is counted, not raised")
say(any("could not be reached" in ln for ln in ns["logger"].lines), "and it is written to the log")
ns = build(admins=[])
say(ns["ws_notify_admins"]("hello") == 0, "no connected admin means nothing is sent")

print("-- 6. the alarm for a frozen usage accounting")
now = datetime.datetime.now().timestamp()
ns = build(stamp=now - 20)
say(ns["ws_usage_heartbeat_alarm"]() is False, "a ticking accounting raises no alarm")
say(ns["_bot"].sent == [], "and nobody is bothered")
ns = build(stamp=now - 7200)
say(ns["ws_usage_heartbeat_alarm"]() is True, "two hours of silence is reported")
say(len(ns["_bot"].sent) == 1 and "has not run" in ns["_bot"].sent[0][1], "the admin is told on telegram",
    ns["_bot"].sent[0][1][:44] if ns["_bot"].sent else "")
ns = build(stamp=None)
say(ns["ws_usage_heartbeat_alarm"]() is False, "a panel that never ran yet is not accused")

print("-- 7. the test notification the owner asked for")
ns = build(token=None)
out = ns["ws_send_test_notification"]()
say(out["bot"] is False and out["errors"], "without a token it says why", out["errors"][0])
ns = build()
out = ns["ws_send_test_notification"]()
say(out["admins"] == 1 and not out["errors"], "with a token the admin gets the test", str(out))
ns = build()
out = ns["ws_send_test_notification"](uuid="abc")
say(out["user"] == "a user" and out["admins"] == 1, "a uuid can be tested too", str(out["user"]))
ns = build(admins=[])
out = ns["ws_send_test_notification"]()
say(out["admins"] == 0 and any("press start" in e for e in out["errors"]), "and it explains an empty result",
    out["errors"][-1][:44])

print("FAILURES: %d %s" % (len(fails), fails))
