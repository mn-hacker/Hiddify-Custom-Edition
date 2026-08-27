"""
watashi v12.2.47 - part 3: the reset flag that was accepted and then dropped.

Finding: panel/usage.py calls user_driver.get_users_usage(reset=True), and
user_driver.get_users_usage(reset=True) never passed reset to any driver. Every
driver therefore always drained the counters, so any future "just look at the
counters" caller would silently destroy the traffic it only wanted to read.
The flag is honoured now, and a driver that does not understand it keeps its old
behaviour instead of raising TypeError (only singbox_api ships in this package;
xray/ssh/wireguard keep their current signature on the server).
"""
import os
import shutil

M = "/data/state/fixm/"
SUFFIX = ".b47"
fails = []


def say(ok, label, extra=""):
    print("%s %-58s %s" % ("OK  " if ok else "BAD ", label, extra))
    if not ok:
        fails.append(label)


def load(path):
    with open(path, "r", encoding="utf-8", newline="") as f:
        raw = f.read()
    return raw.replace("\r\n", "\n"), ("\r\n" in raw)


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


HELPER = '''def ws_call_get_all_usage(driver, reset: bool):
    """Ask a driver for its counters, honouring reset when it can.

    watashi v12.2.47: reset used to stop right here, so every driver always
    drained. Drivers that declare the argument get it; the rest keep draining,
    which is what the panel wants anyway, and we say so in the log.
    """
    import inspect
    try:
        if 'reset' in inspect.signature(driver.get_all_usage).parameters:
            return driver.get_all_usage(reset=reset)
    except (TypeError, ValueError):
        pass
    if not reset:
        logger.debug(f'{driver.__class__.__name__} cannot read its counters without resetting them')
    return driver.get_all_usage()


'''

print("-- 1. drivers/user_driver.py")
p = M + "hiddify-panel/src/hiddifypanel/drivers/user_driver.py"
text, crlf = load(p)
if "ws_call_get_all_usage" in text:
    say(True, "user_driver.py already forwards reset", "nothing to do")
else:
    backup(p)
    text = swap(text, "def get_users_usage(reset=True):", HELPER + "def get_users_usage(reset=True):",
                "user_driver.py: the forwarding helper")
    text = swap(text, "            all_usage = driver.get_all_usage()",
                "            all_usage = ws_call_get_all_usage(driver, reset)",
                "user_driver.py: reset reaches the drivers")
    save(p, text, crlf)
    print("     size %d bytes, crlf=%s" % (os.path.getsize(p), crlf))

print("-- 2. drivers/singbox_api.py")
p = M + "hiddify-panel/src/hiddifypanel/drivers/singbox_api.py"
text, crlf = load(p)
if "def get_all_usage(self, reset" in text:
    say(True, "singbox_api.py already takes reset", "nothing to do")
else:
    backup(p)
    text = swap(text,
                "    def get_all_usage(self):\n        xray_client = self.get_singbox_client()\n        usages = xray_client.stats_query('user', reset=True)",
                "    def get_all_usage(self, reset: bool = True):\n"
                "        # watashi v12.2.47: reset=False lets a caller read the counters\n"
                "        # without draining them. The usage task still drains, as it must.\n"
                "        xray_client = self.get_singbox_client()\n"
                "        usages = xray_client.stats_query('user', reset=reset)",
                "singbox_api.py: get_all_usage honours reset")
    save(p, text, crlf)
    print("     size %d bytes, crlf=%s" % (os.path.getsize(p), crlf))

print("FAILURES: %d %s" % (len(fails), fails))
