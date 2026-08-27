"""watashi v12.2.48 - part 2: the telegram notifications actually reach people.

The finding, proved by reading the code:

  restapi/v1/tgbot.py:35   bot = telebot.TeleBot("1:2", ...)
                     :36   bot.username = ''

The TeleBot object is born with the placeholder token "1:2" and only becomes
real when register_bot() is called. register_bot() is called from QuickSetup,
from SettingAdmin and from cli.backup_task - never from the notification task.
So inside the celery worker every bot.send_message() went to Telegram with a
dead token and answered 404 Unauthorized. The exception was swallowed per user,
the flags were never set, and the log said nothing useful. That is the whole of
"the advanced telegram notification does not work".

Also here:
  * a user whose subscription ends today (remaining_days == 0) got no warning,
    because the test was 0 < remaining_days.
  * the 80% flag was cleared at a hard coded 50%, which is wrong when the owner
    warns at 30%.
  * the task returned counters that nobody could see (ignore_result=True); now
    one summary line goes into the log.
  * a test notification, for the panel button and for the command line.
  * an alarm when the v12.2.47 usage heartbeat goes stale, so a frozen
    accounting is reported instead of staying silent.
  * float(bytes) would have thrown in the new backup memory: redis hands back
    bytes, not str.
"""
import os
import shutil
import py_compile

SRC = "/data/state/src3/"
M = "/data/state/fixm/"
P = "hiddify-panel/src/hiddifypanel/"
MARK = "watashi v12.2.48"
fails = []


def bring(rel):
    dst = M + rel
    if not os.path.exists(dst):
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copyfile(SRC + rel, dst)
        print("brought %-58s %d B" % (rel, os.path.getsize(dst)))
    return dst


def load(rel):
    with open(M + rel, "r", encoding="utf-8", newline="") as f:
        raw = f.read()
    return raw.replace("\r\n", "\n"), ("\r\n" in raw)


def save(rel, text, crlf):
    if crlf:
        text = text.replace("\n", "\r\n")
    with open(M + rel, "w", encoding="utf-8", newline="") as f:
        f.write(text)
    print("saved   %-58s %d B" % (rel, os.path.getsize(M + rel)))


def back(rel):
    b = M + rel + ".b48"
    if not os.path.exists(b):
        shutil.copyfile(M + rel, b)


def swap(text, old, new, label, times=1):
    n = text.count(old)
    if n != times:
        fails.append("%s: anchor found %d times, wanted %d" % (label, n, times))
        return text
    return text.replace(old, new)


# ------------------------------------------------- 1. cli.py: redis gives bytes
rel = P + "panel/cli.py"
text, crlf = load(rel)
if "isinstance(raw, bytes)" in text:
    print("cli.py already decodes redis bytes")
else:
    text = swap(text,
                "            return float(raw)",
                "            return float(raw.decode() if isinstance(raw, bytes) else raw)",
                "cli.py: redis hands back bytes")
    save(rel, text, crlf)

# ----------------------------------------------------- 2. user_notifications.py
rel = P + "panel/user_notifications.py"
bring(rel)
text, crlf = load(rel)
if MARK in text:
    print("user_notifications.py already carries the mark")
else:
    back(rel)
    text = swap(
        text,
        '    if not hconfig(ConfigEnum.telegram_bot_token):\n'
        '        return {"status": "skipped", "reason": "No Telegram bot token configured"}\n',
        '    if not hconfig(ConfigEnum.telegram_bot_token):\n'
        '        return {"status": "skipped", "reason": "No Telegram bot token configured"}\n'
        '\n'
        '    # ' + MARK + ': tgbot.py builds the bot with the placeholder token "1:2"\n'
        '    # and only the web views ever called register_bot(). In this worker the\n'
        '    # token was dead, so every send answered 404 and nobody was notified.\n'
        '    if not ws_ensure_bot():\n'
        '        logger.error("watashi: the telegram bot could not be woken, so no notification was sent")\n'
        '        return {"status": "skipped", "reason": "the bot could not be woken with the saved token"}\n'
        '\n'
        '    # while we are awake once an hour anyway, check that the usage\n'
        '    # accounting is still ticking (the v12.2.47 heartbeat).\n'
        '    ws_usage_heartbeat_alarm()\n',
        "user_notifications.py: wake the bot",
    )
    text = swap(
        text,
        "                    if user.is_active and 0 < user.remaining_days <= notify_expiry_days:",
        "                    # " + MARK + ": 0 < ... skipped the very last day, the day\n"
        "                    # the warning matters most.\n"
        "                    if user.is_active and 0 <= user.remaining_days <= notify_expiry_days:",
        "user_notifications.py: the last day counts too",
    )
    text = swap(
        text,
        "                        if usage_percent < 50:  # Reset when below 50%",
        "                        # " + MARK + ": a hard 50% was wrong for an owner who\n"
        "                        # warns at 30%; the gap follows the setting now.\n"
        "                        if usage_percent < max(10, notify_usage_percent - 30):",
        "user_notifications.py: the reset threshold",
    )
    text = swap(
        text,
        "        db.session.commit()\n",
        "        db.session.commit()\n"
        "        logger.info(\n"
        "            \"watashi: notifications sent - expiry {}, usage {}, finished {}; \"\n"
        "            \"errors {}; telegram users {}\".format(\n"
        "                results[\"expiry_notifications\"], results[\"usage_notifications\"],\n"
        "                results[\"finished_notifications\"], len(results[\"errors\"]),\n"
        "                len(users_with_telegram)))\n",
        "user_notifications.py: a summary in the log",
    )
    text = swap(
        text,
        "        msg += Usage.get_usage_msg(user.uuid)",
        "        msg += ws_usage_block(user)",
        "user_notifications.py: a safe usage block",
        times=3,
    )
    helpers = '''

# ---------------------------------------------------------------------------
# ''' + MARK + ''' helpers
# ---------------------------------------------------------------------------


def ws_ensure_bot() -> bool:
    """Make sure the TeleBot in THIS process carries the real token.

    tgbot.py builds the object with the placeholder token "1:2"; register_bot()
    is what turns it into a real bot. The web side calls that, the celery worker
    never did. We call it here without touching the webhook, because the webhook
    belongs to the web side.
    """
    try:
        from hiddifypanel.panel.commercial.telegrambot import bot, register_bot
    except Exception as e:
        logger.error(f"watashi: the telegram bot module could not be loaded ({e})")
        return False
    token = hconfig(ConfigEnum.telegram_bot_token)
    if not token:
        return False
    if bot.token != token or not bot.username:
        register_bot()
    if bot.token != token:
        bot.token = token
    return bool(bot.token) and bot.token != "1:2"


def ws_usage_block(user) -> str:
    """The usage summary, with a plain fallback.

    Usage.get_usage_msg() needs a domain and an app context; on a fresh panel it
    raises IndexError on Domain.get_domains()[0] and took the whole notification
    down with it. A short line is better than no message at all.
    """
    try:
        from hiddifypanel.panel.commercial.telegrambot import Usage
        return Usage.get_usage_msg(user.uuid)
    except Exception as e:
        logger.warning(f"watashi: the usage message could not be built for {user.uuid} ({e})")
        try:
            return "{:.2f} GB / {:.2f} GB".format(user.current_usage_GB, user.usage_limit_GB)
        except Exception:
            return ""


def ws_notify_admins(text: str) -> int:
    """One short message to every super admin who connected the bot."""
    if not ws_ensure_bot():
        return 0
    sent = 0
    try:
        from hiddifypanel.models import AdminUser, AdminMode
        from hiddifypanel.panel.commercial.telegrambot import bot
        for admin in db.session.query(AdminUser).filter(
                AdminUser.mode == AdminMode.super_admin,
                AdminUser.telegram_id.isnot(None),
                AdminUser.telegram_id != 0).all():
            try:
                bot.send_message(admin.telegram_id, text)
                sent += 1
            except Exception as e:
                logger.error(f"watashi: an admin could not be reached on telegram ({e})")
    except Exception as e:
        logger.exception(f"watashi: the admin notification failed ({e})")
    return sent


def ws_usage_heartbeat_alarm(max_missed: int = 10) -> bool:
    """Report a frozen usage accounting instead of staying silent.

    v12.2.47 stamps ws:usage:last-run on every usage run. If that stamp is far
    older than the configured interval, nobody is being counted and nobody is
    being cut off, while people keep downloading.
    """
    try:
        from hiddifypanel.panel import usage as ws_usage
        from hiddifypanel.cache import redis_client
        raw = redis_client.get(ws_usage.WS_LAST_RUN_KEY)
        if not raw:
            return False
        last = float(raw.decode() if isinstance(raw, bytes) else raw)
        interval = ws_usage.ws_usage_interval()
        idle = datetime.datetime.now().timestamp() - last
        if idle > max(600, interval * max_missed):
            logger.error(f"watashi: the usage accounting has not run for {idle / 60:.0f} minute(s)")
            ws_notify_admins(
                "\\u26a0\\ufe0f Watashi: the usage accounting has not run for "
                f"{idle / 60:.0f} minutes. Please check hiddify-panel-background-tasks.")
            return True
    except Exception as e:
        logger.warning(f"watashi: the usage heartbeat could not be read ({e})")
    return False


def ws_send_test_notification(uuid: str = None) -> dict:
    """Send one test message, so the bot can be proved without waiting for 80%.

    Used by the "Send a test notification" button on the actions page and by
    `hiddify-panel-cli test-notification`.
    """
    out = {"bot": False, "admins": 0, "user": None, "errors": []}
    if not hconfig(ConfigEnum.telegram_bot_token):
        out["errors"].append("no telegram bot token is saved")
        return out
    if not ws_ensure_bot():
        out["errors"].append("the bot could not be woken with the saved token")
        return out
    out["bot"] = True
    when = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    text = f"Watashi test notification\\n{when}\\nThe telegram notifications are working."
    if uuid:
        user = User.by_uuid(uuid)
        if not user:
            out["errors"].append("no user has that uuid")
        elif not user.telegram_id:
            out["errors"].append("that user has not connected the bot")
        else:
            try:
                from hiddifypanel.panel.commercial.telegrambot import bot
                bot.send_message(user.telegram_id, text + "\\n\\n" + ws_usage_block(user))
                out["user"] = user.name
            except Exception as e:
                out["errors"].append(str(e))
    out["admins"] = ws_notify_admins(text)
    if not out["admins"] and not out["user"]:
        out["errors"].append("nobody has connected the bot yet: open the bot and press start")
    return out
'''
    text = text.rstrip("\n") + "\n" + helpers
    save(rel, text, crlf)

# ------------------------------------------------------------- 3. compile check
for rel in [P + "panel/cli.py", P + "panel/user_notifications.py"]:
    try:
        py_compile.compile(M + rel, cfile="/tmp/w48.pyc", doraise=True)
        print("compiles %s" % rel.split("/")[-1])
    except Exception as e:
        fails.append("%s does not compile: %s" % (rel, e))

print("FAILURES: %d %s" % (len(fails), fails))
