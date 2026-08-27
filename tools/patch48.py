"""watashi v12.2.48 - part 1: the automatic backup finally obeys the panel.

The finding, proved by reading the unit file:

  hiddify-panel-background-tasks.service runs
      python -c "from hiddifypanel.base import create_app; app=create_app();
                 celery=app.extensions['celery']; celery.worker_main([... '--beat' ...])"

so the live schedule comes from celery.init_app(app), NOT from init_app_no_flask.
And init_app had the backup pinned to crontab(hour="*/6", minute="0").
That is exactly the owner's report: whatever you choose in the panel, the backup
still arrives every 6 hours. init_app_no_flask (used only by apps/celery_app.py)
did read backup_interval, but only once at start up, and its 1/6/12 special
cases produced uneven schedules for every other number.

The fix: both paths wake the task every hour at :30, and backup_task decides for
itself - at run time - whether enough hours have passed. Changing the setting in
the panel now takes effect on the next hour, with no restart.

Also here: a backup memory (redis + the files themselves), pruning of old backup
files (nothing ever deleted them), a real SQL filter for admins with a telegram
id, and a CLI command to send a test notification.
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
    """Copy a file from the reference tree into the working tree, byte for byte."""
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


def swap(text, old, new, label):
    n = text.count(old)
    if n != 1:
        fails.append("%s: anchor found %d times" % (label, n))
        return text
    return text.replace(old, new)


def cut(text, start, end, new, label):
    i = text.find(start)
    j = text.find(end, i + 1) if i >= 0 else -1
    if i < 0 or j < 0:
        fails.append("%s: slice not found" % label)
        return text
    return text[:i] + new + text[j:]


# ---------------------------------------------------------------- 1. celery.py
rel = P + "celery.py"
bring(rel)
text, crlf = load(rel)
if MARK in text:
    print("celery.py already carries the mark")
else:
    back(rel)
    hourly = (
        '    celery_app.add_periodic_task(\n'
        '        crontab(minute="30"),\n'
        '        backup_task.s(),\n'
        '        name="backup_task"\n'
        '    )\n'
    )
    text = swap(
        text,
        '    # Backup task - runs every 6 hours by default\n'
        '    # Note: backup_interval config is read at task execution time, not here\n'
        '    # to avoid calling hconfig() outside app context\n'
        '    celery_app.add_periodic_task(\n'
        '        crontab(hour="*/6", minute="0"),\n'
        '        backup_task.s(),\n'
        '        name="backup_task"\n'
        '    )\n',
        '    # ' + MARK + ': this is the schedule that really runs, because the\n'
        '    # background tasks service starts create_app(). It was pinned to\n'
        '    # hour="*/6", which is why the interval chosen in the panel changed\n'
        '    # nothing. The task is woken every hour now and decides for itself,\n'
        '    # from ConfigEnum.backup_interval, whether this hour is a backup hour.\n'
        + hourly,
        "celery.py: the live backup schedule",
    )
    text = cut(
        text,
        '    # Get backup interval from config (default 6 hours, 0 = disabled)',
        '    # User notification task - runs every hour',
        '    # ' + MARK + ': the 1/6/12 special cases read the interval once at\n'
        '    # start up and produced uneven hours for every other number. One\n'
        '    # hourly wake up, and the task itself keeps the time.\n'
        + hourly + '\n',
        "celery.py: the no-flask backup schedule",
    )
    save(rel, text, crlf)

# ------------------------------------------------------------------- 2. cli.py
rel = P + "panel/cli.py"
bring(rel)
text, crlf = load(rel)
if MARK in text:
    print("cli.py already carries the mark")
else:
    back(rel)
    new_block = '''from celery import shared_task

# ''' + MARK + ''': the interval the owner picks in the panel is honoured here, at
# run time, instead of being baked into the celery schedule at start up.
WS_BACKUP_LAST_KEY = "ws:backup:last-run"
WS_BACKUP_KEEP = 48


def ws_backup_interval() -> int:
    """Hours between two automatic backups. 0 means the owner switched it off."""
    try:
        value = int(str(hconfig(ConfigEnum.backup_interval) or "6").strip())
    except (ValueError, TypeError):
        value = 6
    if value <= 0:
        return 0
    return min(720, max(1, value))


def ws_backup_last_run() -> float:
    """Unix time of the last backup. Redis first, then the files themselves."""
    try:
        from hiddifypanel.cache import redis_client
        raw = redis_client.get(WS_BACKUP_LAST_KEY)
        if raw:
            return float(raw)
    except Exception:
        pass
    newest = 0.0
    try:
        for name in os.listdir('backup'):
            if name.endswith('.json'):
                newest = max(newest, os.path.getmtime(os.path.join('backup', name)))
    except Exception:
        pass
    return newest


def ws_backup_mark_run(when: float) -> None:
    try:
        from hiddifypanel.cache import redis_client
        redis_client.set(WS_BACKUP_LAST_KEY, str(when))
    except Exception as e:
        logger.warning(f"watashi: the backup time could not be remembered in redis ({e})")


def ws_prune_backups(keep: int = WS_BACKUP_KEEP) -> int:
    """Nothing ever removed these, so a long lived panel filled its disk."""
    removed = 0
    try:
        files = [os.path.join('backup', n) for n in os.listdir('backup') if n.endswith('.json')]
        files.sort(key=os.path.getmtime, reverse=True)
        for old in files[keep:]:
            try:
                os.remove(old)
                removed += 1
            except Exception as e:
                logger.warning(f"watashi: an old backup could not be removed ({e})")
    except Exception:
        pass
    return removed


def backup():
    """The manual backup from the command line. It never waits for the clock."""
    print(backup_task(force=True))


def test_notification():
    """Send one test message, so the owner can see whether the bot really works."""
    from hiddifypanel.panel.user_notifications import ws_send_test_notification
    print(json.dumps(ws_send_test_notification(), indent=2, default=str))


@shared_task(ignore_result=True)
def backup_task(force: bool = False):
    interval = ws_backup_interval()
    now = datetime.datetime.now().timestamp()
    if not force:
        if interval == 0:
            logger.info("watashi: the automatic backup is switched off (backup_interval=0)")
            return {'status': 'skipped', 'reason': 'disabled'}
        last = ws_backup_last_run()
        waited = now - last
        # five minutes of slack, so a task that wakes at :30:02 is not pushed a whole hour back
        if last and waited < interval * 3600 - 300:
            due_in = (interval * 3600 - waited) / 3600
            logger.info(f"watashi: the next backup is due in {due_in:.1f} hour(s) (every {interval}h)")
            return {'status': 'skipped', 'reason': 'too early', 'hours_waited': round(waited / 3600, 2)}
    dbdict = hiddify.dump_db_to_dict()
    os.makedirs('backup', exist_ok=True)
    dst = f'backup/{datetime.datetime.now().strftime("%Y_%m_%d__%H_%M_%S")}.json'
    with open(dst, 'w', encoding='utf-8') as fp:
        json.dump(dbdict, fp, indent=2, sort_keys=True, default=str)
    print(dst)
    ws_backup_mark_run(now)
    pruned = ws_prune_backups()
    sent = 0
    if hconfig(ConfigEnum.telegram_bot_token):
        from hiddifypanel.panel.user_notifications import ws_ensure_bot
        from hiddifypanel.panel.commercial.telegrambot import bot
        ws_ensure_bot()
        # AdminUser.telegram_id is not None was plain python, always True, never SQL
        for admin in db.session.query(AdminUser).filter(
                AdminUser.mode == AdminMode.super_admin,
                AdminUser.telegram_id.isnot(None),
                AdminUser.telegram_id != 0).all():
            caption = ("Backup \\n" + admin_links())
            with open(dst, 'rb') as document:
                try:
                    bot.send_document(admin.telegram_id, document, visible_file_name=dst.replace("backup/", ""), caption=caption[:1000])
                    sent += 1
                except Exception as e:
                    logger.exception(e)
    logger.info(f"watashi: a backup was written to {dst}; it went to {sent} admin(s); {pruned} old file(s) removed")
    return {'status': 'ok', 'file': dst, 'sent': sent, 'pruned': pruned}


'''
    text = cut(text, "from celery import shared_task", "def all_configs():", new_block, "cli.py: the backup task")
    text = swap(
        text,
        "for command in [hysteria_domain_port, tuic_domain_port, init_db, drop_db, all_configs, update_usage, admin_links, admin_path, backup, downgrade]:",
        "for command in [hysteria_domain_port, tuic_domain_port, init_db, drop_db, all_configs, update_usage, admin_links, admin_path, backup, test_notification, downgrade]:",
        "cli.py: the command list",
    )
    save(rel, text, crlf)

# ------------------------------------------------------------ 3. config_enum.py
rel = P + "models/config_enum.py"
bring(rel)
text, crlf = load(rel)
if "backup_interval = _StrConfigDscr(ConfigCategory.telegram_bot, hide_in_virtual_child=True)" in text:
    print("config_enum.py already carries the mark")
else:
    back(rel)
    text = swap(
        text,
        "    backup_interval = _StrConfigDscr(ConfigCategory.telegram_bot, ApplyMode.apply_config, hide_in_virtual_child=True)  # Needs restart to apply",
        "    backup_interval = _StrConfigDscr(ConfigCategory.telegram_bot, hide_in_virtual_child=True)  # " + MARK + ": read at run time, no restart needed",
        "config_enum.py: backup_interval apply mode",
    )
    save(rel, text, crlf)

# ----------------------------------------------------------- 4. SettingAdmin.py
rel = P + "panel/admin/SettingAdmin.py"
bring(rel)
text, crlf = load(rel)
if MARK in text:
    print("SettingAdmin.py already carries the mark")
else:
    back(rel)
    text = swap(
        text,
        '    "backup_interval": "7",',
        '    "backup_interval": "6",  # ' + MARK + ': init_db seeds 6, so the box agrees now',
        "SettingAdmin.py: the backup default",
    )
    save(rel, text, crlf)

# ------------------------------------------------------------------- 5. compile
for rel in [P + "celery.py", P + "panel/cli.py", P + "models/config_enum.py", P + "panel/admin/SettingAdmin.py"]:
    try:
        py_compile.compile(M + rel, cfile="/tmp/w48.pyc", doraise=True)
        print("compiles %s" % rel.split("/")[-1])
    except Exception as e:
        fails.append("%s does not compile: %s" % (rel, e))

print("FAILURES: %d %s" % (len(fails), fails))
