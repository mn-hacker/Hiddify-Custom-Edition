"""watashi v12.2.52 -- does the door behave, and can an empty link explain itself.

The sandbox has no flask, so the login view is imported against small stand in
modules written here, with a fake redis underneath. That proves the logic of the
lock, not a real flask app, and the report says so out loud.
"""
import importlib.util
import os
import re
import subprocess
import sys
import time

M = "/data/state/fixm52/"
P = "hiddify-panel/src/hiddifypanel/"
LOGIN = M + P + "panel/common_bp/login.py"
PAGE = M + P + "panel/common_bp/templates/login.html"
SHARED = M + P + "hutils/proxy/shared.py"
CLI = M + P + "panel/cli.py"
PY = "/tmp/w52py"
fails = []


def say(ok, label, extra=""):
    print("%s %-62s %s" % ("OK  " if ok else "BAD ", label, extra))
    if not ok:
        fails.append(label)


def body(path):
    return open(path, "rb").read().replace(b"\r\n", b"\n").decode("utf-8")


def live(text):
    """The same text with comments and docstring openers taken out."""
    out = []
    for line in text.split("\n"):
        bare = line.strip()
        if bare.startswith("#") or bare.startswith('"""') or bare.startswith("*") or bare.startswith("/*"):
            continue
        out.append(line.split("  # ")[0])
    return "\n".join(out)


STUBS = {}

STUBS["flask.py"] = '''
RENDERED = {}
FLASHED = []


class Bag(dict):
    def get(self, name, default=None):
        return dict.get(self, name, default)

    def __getattr__(self, name):
        try:
            return self[name]
        except KeyError:
            raise AttributeError(name)

    def __setattr__(self, name, value):
        self[name] = value


g = Bag()


class Answer:
    def __init__(self, text, status=200):
        self.text = text
        self.status_code = status
        self.headers = {}
        self.cookies = {}

    def set_cookie(self, name, value, **rest):
        self.cookies[name] = value


class Ask:
    def __init__(self):
        self.headers = {}
        self.remote_addr = "9.9.9.9"
        self.args = {}
        self.cookies = {}
        self.form = {}
        self.path = "/pp/"
        self.query_string = b""
        self.host = "panel.example"
        self.authorization = None


request = Ask()


def make_response(text, status=200):
    return Answer(text, status)


def render_template(name, **rest):
    RENDERED.clear()
    RENDERED["name"] = name
    RENDERED.update(rest)
    return "PAGE"


def redirect(url):
    return ("redirect", url)


def jsonify(*a, **k):
    return k or (a[0] if a else {})


def flash(*a, **k):
    FLASHED.append(a)


class Voice:
    def __init__(self):
        self.lines = []

    def warning(self, text):
        self.lines.append(text)

    def info(self, text):
        self.lines.append(text)


class App:
    logger = Voice()


current_app = App()
'''

STUBS["wtforms.py"] = '''
class Spec:
    def __init__(self, *a, **k):
        self.default = k.get("default", "")


class fields:
    StringField = Spec
    PasswordField = Spec
    SubmitField = Spec
    BooleanField = Spec


class validators:
    class Length:
        def __init__(self, *a, **k):
            pass

    class DataRequired:
        def __init__(self, *a, **k):
            pass
'''

STUBS["flask_wtf.py"] = '''
from wtforms import Spec


class Bound:
    def __init__(self, value=""):
        self.data = value

    def __call__(self, **rest):
        return ""


class FlaskForm:
    def __init__(self, *a, **k):
        for name in dir(type(self)):
            if isinstance(getattr(type(self), name, None), Spec):
                object.__setattr__(self, name, Bound())
        self.csrf_token = Bound()

    def validate_on_submit(self):
        return False
'''

STUBS["flask_babel.py"] = '''
import contextlib


def lazy_gettext(text):
    return text


def gettext(text):
    return text


def get_locale():
    return "en"


@contextlib.contextmanager
def force_locale(name):
    yield
'''

STUBS["flask_classful.py"] = '''
class FlaskView:
    pass


def route(*a, **k):
    def keep(fn):
        return fn
    return keep
'''

STUBS["apiflask.py"] = '''
def abort(*a, **k):
    raise Exception("abort %s" % (a,))
'''

STUBS["hiddifypanel/__init__.py"] = "from . import hutils\n"
STUBS["hiddifypanel/hutils/__init__.py"] = "from . import flask\nfrom . import proxy\n"
STUBS["hiddifypanel/hutils/proxy/__init__.py"] = ""
STUBS["hiddifypanel/hutils/flask.py"] = '''
FLASHED = []


def flash(text, level="info"):
    FLASHED.append((str(text), level))


def hurl_for(*a, **k):
    return "/somewhere"


def static_url_for(**k):
    return "/static/x"


def is_admin_proxy_path():
    return True


def is_admin_panel_call():
    return True


def get_user_agent():
    return {"is_browser": True}
'''

STUBS["hiddifypanel/auth.py"] = '''
current_account = None


def login_required(*a, **k):
    def keep(fn):
        return fn
    return keep


def login_user(*a, **k):
    return True


def logout_user(*a, **k):
    return True


def login_by_uuid(*a, **k):
    return False
'''

STUBS["hiddifypanel/models.py"] = '''
class Role:
    super_admin = "super_admin"
    admin = "admin"
    agent = "agent"
    user = "user"
    custom = "custom"


class Sub:
    def __init__(self, name):
        self.name = name
        self.type = str

    def __str__(self):
        return self.name


class ConfigEnum:
    branding_title = Sub("branding_title")
    lang = Sub("lang")
    branding_site = Sub("branding_site")
    admin_lang = Sub("admin_lang")


def hconfig(key, child_id=None):
    return ""


class AdminUser:
    @staticmethod
    def by_username_password(name, key):
        return None

    @staticmethod
    def by_uuid(value, throw=False):
        return None


class User:
    @staticmethod
    def by_uuid(value, throw=False):
        return None
'''

STUBS["hiddifypanel/panel/__init__.py"] = ""
STUBS["hiddifypanel/panel/hiddify.py"] = '''
def get_account_panel_link(*a, **k):
    return "/panel/link"
'''

STUBS["hiddifypanel/cache.py"] = '''
import time


class FakeRedis:
    """Just enough redis for a door: get, setex, incr, expire, delete, ttl."""

    def __init__(self):
        self.data = {}
        self.dies = {}

    def _sweep(self, key):
        end = self.dies.get(key)
        if end is not None and end <= time.time():
            self.data.pop(key, None)
            self.dies.pop(key, None)

    def get(self, key):
        self._sweep(key)
        value = self.data.get(key)
        return None if value is None else str(value).encode()

    def setex(self, key, ttl, value):
        self.data[key] = value
        self.dies[key] = time.time() + ttl

    def incr(self, key):
        self._sweep(key)
        self.data[key] = int(self.data.get(key, 0)) + 1
        return self.data[key]

    def expire(self, key, ttl):
        self.dies[key] = time.time() + ttl

    def delete(self, *keys):
        for key in keys:
            self.data.pop(key, None)
            self.dies.pop(key, None)

    def ttl(self, key):
        self._sweep(key)
        if key not in self.data:
            return -2
        end = self.dies.get(key)
        return -1 if end is None else int(end - time.time())

    def wipe(self):
        self.data.clear()
        self.dies.clear()


redis_client = FakeRedis()
'''


def plant():
    for name, text in STUBS.items():
        path = os.path.join(PY, name)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as handle:
            handle.write(text)


def bring(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


plant()
if PY not in sys.path:
    sys.path.insert(0, PY)

print("-- 1. the door, on top of a fake redis --------------------------------")
import flask as fl  # noqa: E402  the stand in written above
import hiddifypanel.cache as store_mod  # noqa: E402
import hiddifypanel.hutils.flask as hflask  # noqa: E402

R = store_mod.redis_client
try:
    door = bring(LOGIN, "ws_login52")
    say(True, "the login view loads against the stand ins")
except Exception as problem:
    say(False, "the login view loads against the stand ins", str(problem)[:110])
    print("FAILURES: %d %s" % (len(fails), fails))
    raise SystemExit(0)


def fresh(path="aaa", ip="9.9.9.9"):
    R.wipe()
    fl.g.clear()
    fl.g["proxy_path"] = path
    fl.request.headers = {}
    fl.request.remote_addr = ip
    fl.request.args = {}
    fl.request.cookies = {}
    fl.RENDERED.clear()
    del hflask.FLASHED[:]
    del fl.current_app.logger.lines[:]


fresh("aaa")
key_a = door.ws_door_key()
fl.g["proxy_path"] = "bbb-other-subdomain"
key_b = door.ws_door_key()
say(key_a == key_b, "one lock per visitor, not one per subdomain", key_a)
say(":" in key_a and key_a.startswith("watashi:door:") and key_a.count(":") == 2, "the key is the visitor and nothing else", key_a)

fresh()
fl.request.headers = {"CF-Connecting-IP": "5.5.5.5, 10.0.0.1"}
say(door.ws_door_key().endswith("5.5.5.5"), "the visitor behind cloudflare is read from the header")

fresh()
say(door.ws_wait_left() == 0, "an untouched door is open")
door.ws_note_miss()
door.ws_note_miss()
say(door.ws_wait_left() == 0, "two wrong keys still let you knock")
door.ws_note_miss()
left = door.ws_wait_left()
say(door.WS_LOCK_TIME - 3 <= left <= door.WS_LOCK_TIME, "the third wrong key shuts it for ten minutes", str(left))
say(len(fl.current_app.logger.lines) == 1, "the shut door wrote a line in the log", (fl.current_app.logger.lines or [""])[0][:60])

written = dict(R.data)
deadline = [v for k, v in written.items() if k.endswith(":until")]
say(len(deadline) == 1 and int(deadline[0]) > time.time(), "the lock is a deadline, not a key lifetime", str(deadline))
for _ in range(6):
    door.ws_note_miss()
again = [v for k, v in R.data.items() if k.endswith(":until")]
say(again == deadline, "knocking while shut cannot push the deadline further", str(again))
say(door.ws_wait_left() <= door.WS_LOCK_TIME, "and the wait never grows past the ceiling", str(door.ws_wait_left()))

fresh()
R.setex(door.ws_door_key() + ":until", 99999, int(time.time()) + 99999)
say(door.ws_wait_left() == door.WS_LOCK_CAP, "a runaway deadline is served capped", str(door.ws_wait_left()))

fresh()
R.setex(door.ws_door_key() + ":until", 99999, "banana")
say(door.ws_wait_left() == 0, "an unreadable deadline opens the door")
say(door.ws_door_key() + ":until" not in R.data, "and the bad key is thrown away")

fresh()
R.setex(door.ws_door_key() + ":until", 99999, int(time.time()) - 5)
say(door.ws_wait_left() == 0, "a deadline already past opens the door")

fresh()
door.ws_note_miss()
door.ws_note_miss()
door.ws_note_miss()
R.setex(door.ws_door_key() + ":shut", 600, 1)
door.ws_forget_misses()
say(not [k for k in R.data if k.startswith("watashi:door:")], "the right password clears every trace, old shape too", str(list(R.data)))

words = door.ws_locked_words(125)
say("2:05" in words, "the door says how long is left", words)
say("0:07" in door.ws_locked_words(7), "and under a minute reads as seconds", door.ws_locked_words(7))

print("-- 2. what a shut door answers ---------------------------------------")
view = door.LoginView()

fresh()
first = view.post()
say(getattr(first, "status_code", 0) == 401, "a single wrong key is still a plain 401", str(getattr(first, "status_code", None)))
say("Retry-After" not in getattr(first, "headers", {}), "and it carries no waiting time")
view.post()
third = view.post()
say(getattr(third, "status_code", 0) == 200, "the shut door answers with a page, not 429", str(getattr(third, "status_code", None)))
say(third.headers.get("Retry-After", "").isdigit(), "and tells the client how long to wait", third.headers.get("Retry-After", ""))
say(0 < int(third.headers.get("Retry-After", 0)) <= door.WS_LOCK_TIME, "the waiting time is inside the ceiling")
say(fl.RENDERED.get("lg_locked") is True, "the page knows the door is shut")
say(int(fl.RENDERED.get("lg_wait") or 0) > 0, "and hands the countdown a number", str(fl.RENDERED.get("lg_wait")))
say(any("0:" in str(t[0]) or ":" in str(t[0]) for t in hflask.FLASHED), "the visitor is told in words as well", str(hflask.FLASHED[-1:])[:70])

after = view.post()
say(getattr(after, "status_code", 0) == 200, "knocking again keeps getting the page")
data = door.ws_entrance_data(door.LoginForm())
say(data.get("lg_locked") is True and int(data.get("lg_wait") or 0) > 0, "a plain visit sees the same countdown", str(data.get("lg_wait")))

R.wipe()
data = door.ws_entrance_data(door.LoginForm())
say(data.get("lg_locked") is False and int(data.get("lg_wait") or 0) == 0, "an open door draws no clock")

say("429" not in live(body(LOGIN)), "no 429 is left anywhere in the entrance")

print("-- 3. the page itself -------------------------------------------------")
import jinja2  # noqa: E402

raw = body(PAGE)
say("{% endif %}}" not in raw, "the broken button tag is gone")
env = jinja2.Environment(loader=jinja2.DictLoader({"login.html": raw}), undefined=jinja2.ChainableUndefined, autoescape=True)
env.globals["_"] = lambda text: str(text)
env.globals["hurl_for"] = lambda *a, **k: "/somewhere"
env.globals["static_url_for"] = lambda **k: "/static/x"
env.globals["get_flashed_messages"] = lambda **k: [("danger", "locked 9:59")]
WORDS = {"open": "the door is open", "eye": "show", "hide": "hide"}


def draw(locked, wait):
    return env.get_template("login.html").render(
        lg_locked=locked, lg_wait=wait, lg_words=WORDS, lg_title="WATASHI", lg_lang="en", lg_dir="ltr")


try:
    shut = draw(True, 600)
    open_page = draw(False, 0)
    say(True, "the page renders in both states", "%d and %d bytes" % (len(shut), len(open_page)))
except Exception as problem:
    shut = open_page = ""
    say(False, "the page renders in both states", str(problem)[:110])

say('id="lg-go" disabled><i' in shut, "the shut page closes the button tag properly")
say('id="lg-go"><i' in open_page, "the open page closes the button tag too")
say("}<" not in shut and "}<" not in open_page, "no stray brace is left inside a tag")
say(shut.count('id="lg-clock"') == 1, "the shut page carries one clock")
say("var LOCK_LEFT = 600;" in shut, "the clock starts from the seconds left")
say("var LOCK_LEFT = 0;" in open_page, "and from zero when the door is open")
say("disabled" not in open_page.split('id="lg-go"')[1][:40], "the open page leaves the button alive")
say("go.disabled = false" in shut, "the countdown gives the button back at zero")

print("-- 4. why a subscription came out empty -------------------------------")
src = live(body(SHARED))
say("if noDomainProxies and ips and all([x in added_ip[key] for x in ips]):" in src, "an empty dns answer is no longer a duplicate")
say(src.count("def ws_sub_note(") == 1 and src.count("def ws_sub_reasons(") == 1, "the reasons are collected")
say("ws_sub_note(pinfo.get('msg'), proxy)" in src, "every rejected proxy leaves its reason")
say("if not allp:" in src and "ws_sub_complain(domains, disabled_proxies)" in src, "an empty link complains into the log")

ips = []
added = {"key": ["1.1.1.1"]}
old_says = all([x in added["key"] for x in ips])
new_says = bool(ips) and all([x in added["key"] for x in ips])
say(old_says is True and new_says is False, "the old expression really did drop everything here", "old=%s new=%s" % (old_says, new_says))
ips = ["1.1.1.1"]
say((bool(ips) and all([x in added["key"] for x in ips])) is True, "and a real duplicate is still skipped")

print("-- 5. the two new hands in the panel cli -----------------------------")
cli = body(CLI)
say("@ app.cli.command('sub-doctor')" in cli, "sub-doctor is registered")
say("@ app.cli.command('unlock-login')" in cli, "unlock-login is registered")
say("scan_iter(match='watashi:door:%s*' % who" in cli, "unlock-login clears only door keys")
say("with app.test_request_context('/')" in cli, "the doctor works inside a request, like the real link")
say("configs in link" in cli and "ws_sub_reasons()" in cli, "the doctor prints the count and the reasons")
say("missing from the database" in cli, "the doctor names the missing switch keys")
say("set_hconfig(key, True, child, commit=False)" in cli and cli.count("db.session.commit()") >= 1, "--fix writes the safe defaults once")
OFF = ("ssh_server_enable", "wireguard_enable", "tuic_enable", "hysteria_enable", "mieru_enable", "naive_enable",
       "amnezia_enable", "telegram_enable", "shadowsocks2022_enable", "ssfaketls_enable", "shadowtls_enable",
       "ssr_enable", "v2ray_enable", "http_proxy_enable")
heal = cli.split("WS_HEAL_ON = (")[1].split(")")[0] if "WS_HEAL_ON = (" in cli else ""
say(bool(heal) and not [name for name in OFF if name in heal], "the heal list touches nothing that needs a service", heal.replace("\n", " ")[:60])
say("vless_enable" in heal and "ws_enable" in heal and "reality_enable" in heal, "but it does cover what a working panel needs")

print("-- 6. the files themselves -------------------------------------------")
for path in (LOGIN, PAGE, SHARED, CLI):
    name = path.split("/")[-1]
    now = open(path, "rb").read()
    was = open(path + ".b52", "rb").read()
    say(now != was, "changed against its backup: " + name, "%d -> %d bytes" % (len(was), len(now)))
    say(b"\r\n" in now and now.replace(b"\r\n", b"").count(b"\n") == 0, "still a windows file: " + name)
for path in (LOGIN, SHARED, CLI):
    done = subprocess.run([sys.executable, "-m", "py_compile", path], capture_output=True)
    say(done.returncode == 0, "python still parses: " + path.split("/")[-1], done.stderr.decode()[:80])

print("FAILURES: %d %s" % (len(fails), fails))
