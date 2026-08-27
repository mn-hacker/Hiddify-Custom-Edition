"""v12.2.51: the core page in the panel.

Finding: v12.2.50 gave the manager a real core engine, but nothing in the panel
could reach it. Changing a core still meant editing common/packages.lock by hand
over ssh, which is exactly why the panel was still pinned to Xray 26.3.27 while
the vendor was on 26.7.28. There was also no way for the owner to hand that job
to the people who run their own servers.

This round adds the page, the root path it needs (commander), and the script
that pins a new release with a real sha256.
"""
import os
import py_compile
import shutil
import subprocess

SRC = "/data/state/src3/"
P = "hiddify-panel/src/hiddifypanel/"
M = "/data/state/fixm51/"
MARK = "watashi v12.2.51"
fails = []


def check(ok, label):
    print("%s %s" % ("OK  " if ok else "BAD ", label))
    if not ok:
        fails.append(label)


def bring(rel):
    dst = M + rel
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    if not os.path.exists(dst):
        shutil.copy2(SRC + rel, dst)
    b = dst + ".b51"
    if not os.path.exists(b):
        shutil.copy2(dst, b)
    return dst


def load(path):
    with open(path, "rb") as f:
        raw = f.read()
    crlf = b"\r\n" in raw
    return raw.decode("utf-8").replace("\r\n", "\n"), crlf


def save(path, text, crlf):
    if crlf:
        text = text.replace("\n", "\r\n")
    with open(path, "wb") as f:
        f.write(text.encode("utf-8"))


def swap(text, old, new, label):
    if new in text:
        check(True, label + " (already there)")
        return text
    check(text.count(old) == 1, label + " anchor")
    return text.replace(old, new, 1)


def read_chunks(names):
    out = ""
    for n in names:
        with open("/data/w/" + n, "r", encoding="utf-8") as f:
            out += f.read()
    return out


# ---------------------------------------------------------------- new files
os.makedirs(M + P + "panel/admin/templates", exist_ok=True)
os.makedirs(M + "common", exist_ok=True)

core_admin = read_chunks(["ca51_a.py", "ca51_b.py"])
save(M + P + "panel/admin/CoreAdmin.py", core_admin, True)
check("class CoreAdmin" in core_admin and "ws_ask" in core_admin, "CoreAdmin.py written")

head = read_chunks(["ch51_a.html"])
mid = read_chunks(["ch51_b.html"]).replace("</script>\n{% endblock %}\n", "")
tail = read_chunks(["ch51_c.html"])
template = head + mid + tail
check(template.count("{% endblock %}") == 3, "the template closes every block once")
check("confirm(" not in template and "alert(" not in template, "no native dialogs on the page")
save(M + P + "panel/admin/templates/cores.html", template, True)

bump = read_chunks(["bc51.sh"])
save(M + "common/bump_cores.sh", bump, False)
os.chmod(M + "common/bump_cores.sh", 0o755)

# ------------------------------------------------------- commander (as root)
p = bring("common/commander.py")
text, crlf = load(p)
text = swap(
    text,
    "    get_cert = os.path.join(HIDDIFY_DIR, 'acme.sh/get_cert.sh')\n",
    "    get_cert = os.path.join(HIDDIFY_DIR, 'acme.sh/get_cert.sh')\n"
    "    # watashi v12.2.51: the core page needs one root path, and this is it\n"
    "    core = os.path.join(HIDDIFY_DIR, 'common/core_manager.sh')\n",
    "commander knows the core manager",
)
text = swap(
    text,
    "@cli.command('truncate')",
    """# watashi v12.2.51: the only root door the core page has. Everything that
# arrives here is checked again, so a broken form in the panel cannot turn into
# a shell command.
WS_CORE_ACTIONS = ('install', 'upgrade', 'downgrade', 'rollback', 'prune')


def is_core_name_valid(name: str) -> bool:
    return bool(re.match(r'^[a-z0-9][a-z0-9._-]{0,39}$', name or ''))


def is_core_version_valid(version: str) -> bool:
    return bool(re.match(r'^[0-9][0-9A-Za-z.+_-]{0,39}$', version or ''))


@cli.command('core')
@click.option('--action', '-a', type=str, help='install, upgrade, downgrade, rollback or prune', required=True)
@click.option('--name', '-n', type=str, help='The core to work on', required=True)
@click.option('--version', '-v', type=str, help='The version to install', default='')
def core(action: str, name: str, version: str):
    assert action in WS_CORE_ACTIONS, f"Error: {action} is not a core action"
    assert is_core_name_valid(name), f"Error: Invalid core name passed to the core command: {name}"
    assert not version or is_core_version_valid(version), f"Error: Invalid version passed to the core command: {version}"
    cmd = ['bash', Command.core.value, action, name]
    if version:
        cmd.append(version)
    run(cmd)


@cli.command('truncate')""",
    "commander has a core command",
)
save(p, text, crlf)

# ------------------------------------------------------ the panel side of it
p = bring(P + "panel/run_commander.py")
text, crlf = load(p)
text = swap(
    text,
    "    truncate = 'truncate'\n",
    "    truncate = 'truncate'\n    core = 'core'  # watashi v12.2.51\n",
    "run_commander knows the core command",
)
text = swap(
    text,
    "    elif command == Command.truncate:",
    """    elif command == Command.core:
        # watashi v12.2.51: install, upgrade, downgrade, rollback or prune one core
        action = str(kwargs.get('action', ''))
        name = str(kwargs.get('name', ''))
        version = str(kwargs.get('version', ''))
        if not action or not name:
            raise Exception("Invalid input: action and name are required for the core command")
        base_cmd.extend(['core', '--action', action, '--name', name])
        if version:
            base_cmd.extend(['--version', version])
    elif command == Command.truncate:""",
    "run_commander builds the core command",
)
save(p, text, crlf)

# --------------------------------------------------------------- registration
p = bring(P + "panel/admin/__init__.py")
text, crlf = load(p)
text = swap(
    text,
    "    from .QuickSetup import QuickSetup\n",
    "    from .QuickSetup import QuickSetup\n"
    "    # watashi v12.2.51: the cores page\n"
    "    from .CoreAdmin import CoreAdmin\n",
    "__init__ imports CoreAdmin",
)
text = swap(
    text,
    "    Backup.register(admin_bp)\n",
    "    Backup.register(admin_bp)\n    CoreAdmin.register(admin_bp, route_base=\"/cores\")\n",
    "__init__ registers CoreAdmin",
)
save(p, text, crlf)

# ----------------------------------------------------------------- the menu
p = bring(P + "templates/admin-layout.html")
text, crlf = load(p)
text = swap(
    text,
    """          {{ render_nav_item('admin.TunnelAdmin:index',icon('solid','network-wired','nav-icon')+ _('Tunnel'),
          _use_li=True) }}
""",
    """          {{ render_nav_item('admin.TunnelAdmin:index',icon('solid','network-wired','nav-icon')+ _('Tunnel'),
          _use_li=True) }}
          {# watashi v12.2.51: the cores page #}
          {{ render_nav_item('admin.CoreAdmin:index',icon('solid','microchip','nav-icon')+ _('Cores'),
          _use_li=True) }}
""",
    "the menu has a cores entry",
)
save(p, text, crlf)

# ------------------------------------------------------------------- syntax
for rel in (
    "common/commander.py",
    P + "panel/run_commander.py",
    P + "panel/admin/__init__.py",
    P + "panel/admin/CoreAdmin.py",
):
    try:
        py_compile.compile(M + rel, doraise=True, cfile="/tmp/p51.pyc")
        check(True, "python syntax: " + rel)
    except Exception as problem:
        check(False, "python syntax: %s (%s)" % (rel, problem))

rc = subprocess.run(["bash", "-n", M + "common/bump_cores.sh"], capture_output=True)
check(rc.returncode == 0, "bash syntax: common/bump_cores.sh %s" % rc.stderr.decode()[:120])

for rel in ("common/commander.py", P + "panel/run_commander.py", P + "panel/admin/__init__.py", P + "templates/admin-layout.html"):
    with open(M + rel, "rb") as f:
        raw = f.read()
    check(b"\r\n" in raw, "line endings kept: " + rel)

print("FAILURES: %d %s" % (len(fails), fails))
