"""v12.2.51 checks, part 2: the view and the page itself.

flask is not installed in this sandbox, so the view is loaded against small
stand-ins for flask, flask_classful, flask_babel and the panel modules it
imports. That is honest about what is proven here: the logic of the view and
the page, not a running flask app.
"""

import importlib.util
import os
import sys

sys.path.insert(0, "/data/w")
import w50env as W

fails = []


def t(ok, label, extra=""):
    if not W.say(ok, label, extra):
        fails.append(label)


M51 = "/data/state/fixm51/"
P = "hiddify-panel/src/hiddifypanel/"
STUB = "/tmp/w51py"
H = W.H

STUBS = {
    "flask.py": '''
class _Resp:
    def __init__(self, body, mimetype=None, status=200):
        self.data = body
        self.mimetype = mimetype
        self.status = status


class _Logger:
    def __init__(self):
        self.errors = []

    def error(self, message):
        self.errors.append(str(message))


class _App:
    response_class = _Resp
    logger = _Logger()


class _Request:
    payload = None
    form = {}

    def get_json(self, silent=False):
        return self.payload


RENDERED = {}
current_app = _App()
request = _Request()


def render_template(name, **context):
    RENDERED.clear()
    RENDERED["name"] = name
    RENDERED.update(context)
    return "rendered " + name
''',
    "flask_classful.py": '''
class FlaskView(object):
    pass


def route(rule, **options):
    def wrap(function):
        function.ws_rule = rule
        function.ws_options = options
        return function
    return wrap
''',
    "flask_babel.py": "def gettext(text, **kwargs):\n    return text\n",
    "hiddifypanel/__init__.py": "",
    "hiddifypanel/auth.py": '''
def login_required(roles=None, **kwargs):
    def deco(function):
        return function
    deco.ws_roles = roles
    return deco
''',
    "hiddifypanel/models.py": "class Role:\n    super_admin = 'super_admin'\n    admin = 'admin'\n    agent = 'agent'\n    user = 'user'\n",
    "hiddifypanel/panel/__init__.py": "",
    "hiddifypanel/panel/run_commander.py": '''
CALLS = []


class Command:
    core = "core"


def commander(command, run_in_background=True, **kwargs):
    CALLS.append({"command": command, "background": run_in_background, "args": kwargs})
    if kwargs.get("name") == "boom":
        raise Exception("the commander is not reachable")
    return "xray is now 26.7.28\\n"
''',
}

for rel, body in STUBS.items():
    path = os.path.join(STUB, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "w").write(body)

W.build()
os.makedirs(H + "/common/cores", exist_ok=True)
open(H + "/common/cores/installed.db", "w").write("xray|26.7.28|1700000000\n")
W.latest_json("XTLS/Xray-core", "v26.7.28")
os.environ["HIDDIFY_CONFIG_PATH"] = H
os.environ["PATH"] = W.BIN + ":" + os.environ["PATH"]
sys.path.insert(0, STUB)
spec = importlib.util.spec_from_file_location("CoreAdmin", M51 + P + "panel/admin/CoreAdmin.py")
ca = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ca)
import flask as fl  # the stand-in
import hiddifypanel.panel.run_commander as rc  # the stand-in

print("-- 7. the page reads the real state of the server")
rows, error = ca.ws_core_json()
names = [r.get("name") for r in rows]
t(bool(rows) and not error, "the state is read without an error", error or "")
t("xray" in names and "singbox" in names, "every registered core is there", len(rows))
cores, error = ca.ws_cores()
xray = [c for c in cores if c["name"] == "xray"][0]
singbox = [c for c in cores if c["name"] == "singbox"][0]
t(xray.get("repo") == "XTLS/Xray-core", "the vendor of each core is shown", xray.get("repo"))
t(xray.get("installed") == "26.7.28", "the installed version is read", xray.get("installed"))
t(xray.get("off_tested") is True, "a version outside the tested range is flagged", xray.get("tested"))
t(not singbox.get("installed") and not singbox.get("off_tested"), "a core that is not installed is not flagged")
keep = ca.WS_CORE_MANAGER
ca.WS_CORE_MANAGER = "/tmp/w51/not-here.sh"
rows2, error2 = ca.ws_core_json()
t(rows2 == [] and bool(error2), "a server without the core manager gets a sentence, not a crash", error2)
ca.WS_CORE_MANAGER = keep

print("-- 8. nothing dangerous reaches the commander")
del rc.CALLS[:]
for action, name, version, label in (
    ("delete", "xray", "", "a made up action"),
    ("install", "xray;rm -rf /", "", "a name with a shell command in it"),
    ("install", "xray", "$(id)", "a version with a shell command in it"),
    ("install", "../../etc/passwd", "", "a name that walks out of the tree"),
    ("", "", "", "an empty request"),
):
    ok, text = ca.ws_ask(action, name, version)
    t(not ok and bool(text), "%s is refused" % label, text[:52])
t(rc.CALLS == [], "and none of them reached the commander", len(rc.CALLS))
ok, text = ca.ws_ask("upgrade", "xray", "")
t(ok and "26.7.28" in text, "a real request goes through and the answer comes back", text.strip()[:40])
t(rc.CALLS[-1]["args"] == {"action": "upgrade", "name": "xray", "version": ""}, "the commander is given separate words", rc.CALLS[-1]["args"])
t(rc.CALLS[-1]["background"] is False, "the page waits for the answer")
ok, text = ca.ws_ask("install", "boom", "1.2.3")
t(not ok and bool(text), "a commander that is not reachable is reported", text[:40])
t(bool(fl.current_app.logger.errors), "and written to the panel log", fl.current_app.logger.errors[-1][:40])

print("-- 9. the view answers the page")
view = ca.CoreAdmin()
t(ca.CoreAdmin.decorators[0].ws_roles == {"super_admin"}, "only a super admin can open the page", ca.CoreAdmin.decorators[0].ws_roles)
view.index()
ctx = fl.RENDERED
t(ctx.get("name") == "cores.html", "the page is the cores page", ctx.get("name"))
t(ctx["counts"]["installed"] == 1 and ctx["counts"]["off_tested"] == 1, "the counters add up", ctx["counts"])
t(ctx["counts"]["total"] == len(ctx["cores"]), "and the total is the number of rows", ctx["counts"]["total"])
answer = view.latest("not a core name")
t(answer.status == 400 and '"ok": false' in answer.data, "a silly core name gets a plain no", answer.status)
answer = view.latest("xray")
t('"latest": "26.7.28"' in answer.data, "the newest release is fetched on demand", answer.data[:60])
fl.request.payload = {"action": "upgrade", "name": "xray", "version": ""}
answer = view.change()
t(answer.status == 200 and '"ok": true' in answer.data, "a change comes back with its log", answer.status)
t('"cores"' in answer.data, "and with fresh rows for the table")
fl.request.payload = {"action": "burn", "name": "xray"}
answer = view.change()
t(answer.status == 400 and '"ok": false' in answer.data, "a bad change is answered with 400", answer.status)
t(ca.CoreAdmin.change.ws_options.get("methods") == ["POST"], "changes are only accepted as post", ca.CoreAdmin.change.ws_options)

print("-- 10. the page itself renders")
import jinja2

raw = open(M51 + P + "panel/admin/templates/cores.html", "rb").read().decode("utf-8")
layout = "{% block title %}{% endblock %}\n{% block header_actions %}{% endblock %}\n{% block body %}{% endblock %}"
env = jinja2.Environment(loader=jinja2.DictLoader({"theme_layout.html": layout, "cores.html": raw.replace("\r\n", "\n")}))
env.globals["_"] = lambda text: text
env.globals["hurl_for"] = lambda endpoint, **kw: "/admin/cores/" + endpoint.split(":")[-1] + ("/" + kw["name"] if kw.get("name") else "")
try:
    html = env.get_template("cores.html").render(cores=ctx["cores"], counts=ctx["counts"], core_error="")
    t(True, "the page renders")
except Exception as problem:
    html = ""
    t(False, "the page renders", str(problem)[:80])
t(html.count('<tr data-core="') == len(ctx["cores"]), "one row per core", html.count('<tr data-core="'))
t("cr-p-warn" in html, "the core off the tested range is painted amber")
t("/admin/cores/list" in html and "/admin/cores/change" in html and "/admin/cores/latest/NAME" in html, "the page knows all three addresses")
for word in ("Upgrade", "Pick a version", "Roll back", "Check for new releases"):
    t(word in html, "the %s button is there" % word.lower())
t("confirm(" not in html and "alert(" not in html, "no native dialog is used")
t("<select" not in html, "no native select is used")
t("cr-shade" in html and 'role="dialog"' in html, "the version box is our own modal")
for prop in ("border-block-end", "margin-block-end", "text-align: start", "padding-inline" if "padding-inline" in html else "inset: 0"):
    t(prop in html, "css uses %s" % prop)
t("margin-left" not in html and "padding-right" not in html and "border-bottom:" not in html, "and no left or right css is left behind")

print("-- 11. the menu and the registration")
layout_html = open(M51 + P + "templates/admin-layout.html", "rb").read().decode("utf-8")
t("admin.CoreAdmin:index" in layout_html, "the sidebar has a cores entry")
t(layout_html.index("admin.TunnelAdmin:index") < layout_html.index("admin.CoreAdmin:index"), "it sits next to the tunnel entry")
guard = layout_html.rfind("super_admin", 0, layout_html.index("admin.CoreAdmin:index"))
t(guard > 0, "and only a super admin sees it")
t("microchip" in layout_html, "it has its own icon")
init = open(M51 + P + "panel/admin/__init__.py", "rb").read().decode("utf-8")
t("from .CoreAdmin import CoreAdmin" in init, "the view is imported")
t('CoreAdmin.register(admin_bp, route_base="/cores")' in init, "and registered under /cores")

print("-- 12. what the round changed, next to what was there before")
for rel in ("common/commander.py", P + "panel/run_commander.py", P + "panel/admin/__init__.py", P + "templates/admin-layout.html"):
    new = open(M51 + rel, "rb").read()
    old = open(M51 + rel + ".b51", "rb").read()
    t(new != old, "changed: " + rel.split("/")[-1])
    t(b"v12.2.51" in new and b"v12.2.51" not in old, "marked as v12.2.51: " + rel.split("/")[-1])
    t(b"\r\n" in new and new.replace(b"\r\n", b"").count(b"\n") == 0, "line endings kept: " + rel.split("/")[-1])
for rel in (P + "panel/admin/CoreAdmin.py", P + "panel/admin/templates/cores.html"):
    raw = open(M51 + rel, "rb").read()
    t(b"\r\n" in raw, "a windows file like the rest of the panel: " + rel.split("/")[-1])
t(os.access(M51 + "common/bump_cores.sh", os.X_OK), "the bumper is executable")

print("FAILURES: %d %s" % (len(fails), fails))
