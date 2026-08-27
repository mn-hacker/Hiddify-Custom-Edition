"""
watashi v12.2.47 - part 1 of 2: usage accounting that cannot lose bytes.

Findings, all read from the real files:

1. panel/usage.py: the redis lock was commented out, so two overlapping runs
   both drained the cores (draining resets their counters) and one of the two
   batches could be dropped -> "the user still has 30GB of their internet
   package but the config says 50GB is gone" (and the mirror case, overage).
2. panel/usage.py: a drained batch lived only in local variables. Any error
   between the drain and CALL add_usage_json deleted that traffic for good.
   A small redis journal now holds the batch until the database takes it.
3. panel/usage.py: a user who runs out of quota while idle never appears in
   the usage list again, so a cut-off that failed once was never retried.
4. panel/usage.py: apply-users could be started many times per minute; each
   start regenerates every config and reloads the cores. Now debounced.
5. celery.py: the poll interval was hard coded to 60s in both entry points.
   It reads ConfigEnum.usage_update_interval now (10..600s, default 30).
"""
import os
import shutil

SRC = "/data/state/src3/"
M = "/data/state/fixm/"
SUFFIX = ".b47"
MARK = "watashi v12.2.47"

fails = []


def say(ok, label, extra=""):
    print("%s %-58s %s" % ("OK  " if ok else "BAD ", label, extra))
    if not ok:
        fails.append(label)


def bring(rel):
    dst = M + rel
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    if not os.path.exists(dst):
        shutil.copy2(SRC + rel, dst)
        print("     brought %s" % rel)
    return dst


def load(path):
    with open(path, "r", encoding="utf-8", newline="") as f:
        raw = f.read()
    crlf = "\r\n" in raw
    return raw.replace("\r\n", "\n"), crlf


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


HELPERS = '''
# ------------------------------------------------------------ watashi v12.2.47
# get_users_usage() drains the cores, and draining resets their counters. From
# that moment the only copy of those bytes lives in this process, so a failed
# database write used to throw them away: the user kept browsing and the panel
# never learned about the traffic. Every drained batch is written to a small
# redis journal first and cleared only after the database has taken it.
WS_PENDING_KEY = "ws:usage:pending"
WS_LAST_RUN_KEY = "ws:usage:last-run"
WS_APPLY_KEY = "ws:usage:apply-users"
WS_DEFAULT_INTERVAL = 30
_ws_mem_pending: Dict[str, int] = {}


def ws_usage_interval() -> int:
    """Seconds between two usage polls. Owner configurable, clamped to 10..600."""
    try:
        value = int(hconfig(ConfigEnum.usage_update_interval) or WS_DEFAULT_INTERVAL)
    except Exception:
        value = WS_DEFAULT_INTERVAL
    return min(600, max(10, value))


def ws_load_pending() -> Dict[str, int]:
    """Bytes drained by an earlier run that the database has not taken yet."""
    try:
        raw = cache.redis_client.get(WS_PENDING_KEY)
        if raw:
            return {str(u): int(v) for u, v in json.loads(raw).items() if int(v) > 0}
    except Exception as e:
        logger.warning(f"watashi: cannot read the usage journal ({e}); using the in-process copy")
        return dict(_ws_mem_pending)
    return {}


def ws_save_pending(pending: Dict[str, int]) -> None:
    _ws_mem_pending.clear()
    _ws_mem_pending.update(pending)
    try:
        if pending:
            cache.redis_client.set(WS_PENDING_KEY, json.dumps(pending))
        else:
            cache.redis_client.delete(WS_PENDING_KEY)
    except Exception as e:
        logger.warning(f"watashi: cannot write the usage journal ({e}); memory copy only")


def ws_apply_users_once(min_gap: int = 20) -> None:
    """apply-users rebuilds every config and reloads the cores, so it must not be
    started twice in the same breath when several users run out together."""
    try:
        if not cache.redis_client.set(WS_APPLY_KEY, "1", nx=True, ex=min_gap):
            logger.info("watashi: apply-users was just started; not starting a second one")
            return
    except Exception:
        pass
    hiddify.quick_apply_users()
'''

NEW_TASKS = '''@shared_task(ignore_result=True)
def update_local_usage():
    lock_key = "lock-update-local-usage"
    have_lock = True
    try:
        have_lock = bool(cache.redis_client.set(lock_key, "locked", nx=True, ex=max(120, ws_usage_interval() * 4)))
    except Exception as e:
        # a redis hiccup must never stop the accounting, or nobody gets cut off
        logger.warning(f"watashi: the usage lock is unavailable ({e}); running without it")
    if not have_lock:
        return {"msg": "last update task is not finished yet."}
    try:
        return update_local_usage_not_lock()
    except Exception as e:
        logger.exception("Exception in update usage")
        return {"msg": f"Exception in update usage: {e}"}
    finally:
        # watashi v12.2.47: the lock is released here instead of being left
        # behind with a fixed 60s life, which used to block the next run
        # whenever the interval was shorter than that.
        import time as _time
        try:
            cache.redis_client.delete(lock_key)
            cache.redis_client.set(WS_LAST_RUN_KEY, int(_time.time()), ex=86400)
        except Exception:
            pass


def update_local_usage_not_lock():
    # 1. drain the cores; their counters are zero now, so these bytes are only here
    res = user_driver.get_users_usage(reset=True)
    fresh = {uuid: int(uinfo.get("usage") or 0) for uuid, uinfo in res.items() if (uinfo.get("usage") or 0) > 0}

    # 2. add whatever an earlier run drained but could not store
    merged = ws_load_pending()
    for uuid, value in fresh.items():
        merged[uuid] = merged.get(uuid, 0) + value

    # 3. journal first, database second
    if merged:
        ws_save_pending(merged)
        logger.debug(f"watashi: {len(merged)} users and {sum(merged.values())} bytes are waiting for the database")

    stored = {"done": False}

    def _stored():
        stored["done"] = True
        ws_save_pending({})

    result = add_users_usage_new(
        [{"uuid": uuid, "usage": value} for uuid, value in merged.items()],
        child_id=0,
        on_usage_committed=_stored,
    )
    if merged and not stored["done"]:
        logger.error("watashi: the usage was not stored; it stays in the journal for the next run")
    return result


'''

SWEEP = '''    # watashi v12.2.47: a user who runs out of quota while idle never shows up
    # in usage_map again, and a cut-off that failed once was never retried. Sweep
    # the core user list against the database so nobody keeps a finished package.
    try:
        core_only = [uuid for uuid, on in before_enabled_users.items() if on and uuid not in all_users_uuids]
        if core_only:
            for user in db.session.query(User).filter(User.uuid.in_(core_only)).all():
                if not user.is_active:
                    logger.info(f"watashi: cutting off {user.uuid}, its package is finished")
                    user_driver.remove_client(user)
                    apply_changes = True
    except Exception:
        logger.exception("watashi: the idle cut-off sweep failed")

    if apply_changes:
        ws_apply_users_once()

    return {"status": 'success', "comments": usages, "date": hutils.convert.time_to_json(cur_time)}'''

OLD_APPLY = '''    if apply_changes:
        hiddify.quick_apply_users()

    return {"status": 'success', "comments": usages, "date": hutils.convert.time_to_json(cur_time)}'''

OLD_CALL = '''    db_execute("CALL add_usage_json(:usage_data,:cur_time)", usage_data=json.dumps(usages),cur_time=cur_time.strftime('%Y-%m-%d %H:%M:%S'), commit=True)'''

NEW_CALL = '''    # watashi v12.2.47: nothing to store is not an error, and the journal may be
    # cleared only after the database has really taken the bytes.
    if usages:
        db_execute("CALL add_usage_json(:usage_data,:cur_time)", usage_data=json.dumps(usages),cur_time=cur_time.strftime('%Y-%m-%d %H:%M:%S'), commit=True)
    if on_usage_committed is not None:
        try:
            on_usage_committed()
        except Exception:
            logger.exception("watashi: could not clear the usage journal")'''

OLD_CELERY = '''    from hiddifypanel.panel import usage
    celery_app.add_periodic_task(60.0, usage.update_local_usage.s(), name='update usage')'''

NEW_CELERY = '''    from hiddifypanel.panel import usage
    # watashi v12.2.47: the cut-off can never be faster than this poll, so 60s
    # hard coded meant a user could burn several GB between two polls. The owner
    # sets it in the panel now (ConfigEnum.usage_update_interval, 10..600s).
    ws_interval = float(usage.WS_DEFAULT_INTERVAL)
    try:
        ws_interval = float(usage.ws_usage_interval())
    except Exception as e:
        logger.warning(f"watashi: cannot read usage_update_interval ({e}); staying at {ws_interval:.0f}s")
    logger.info(f"watashi: the usage task runs every {ws_interval:.0f} seconds")
    celery_app.add_periodic_task(ws_interval, usage.update_local_usage.s(), name='update usage')'''

# ----------------------------------------------------------------- usage.py
print("-- 1. panel/usage.py")
p = bring("hiddify-panel/src/hiddifypanel/panel/usage.py")
text, crlf = load(p)
if MARK in text:
    say(True, "usage.py is already patched", "nothing to do")
else:
    backup(p)
    text = swap(text, "to_gig_d = 1024**3\n", "to_gig_d = 1024**3\n" + HELPERS, "usage.py: journal helpers")
    head = "@shared_task(ignore_result=True)\ndef update_local_usage():"
    tail = "def add_users_usage_uuid("
    if text.count(head) == 1 and text.count(tail) == 1 and text.index(head) < text.index(tail):
        text = text[:text.index(head)] + NEW_TASKS + text[text.index(tail):]
        say(True, "usage.py: both usage tasks rewritten")
    else:
        say(False, "usage.py: both usage tasks rewritten", "anchors not unique")
    text = swap(text,
                "def add_users_usage_new(usages: list[dict], child_id, sync=False):",
                "def add_users_usage_new(usages: list[dict], child_id, sync=False, on_usage_committed=None):",
                "usage.py: commit callback in the signature")
    text = swap(text, OLD_CALL, NEW_CALL, "usage.py: the db call reports success")
    text = swap(text, OLD_APPLY, SWEEP, "usage.py: idle sweep and debounced apply")
    save(p, text, crlf)
    print("     size %d bytes, crlf=%s" % (os.path.getsize(p), crlf))

# ----------------------------------------------------------------- celery.py
print("-- 2. celery.py")
p = bring("hiddify-panel/src/hiddifypanel/celery.py")
text, crlf = load(p)
if MARK in text:
    say(True, "celery.py is already patched", "nothing to do")
else:
    backup(p)
    text = swap(text, OLD_CELERY, NEW_CELERY, "celery.py: interval from the settings", count=2)
    save(p, text, crlf)
    print("     size %d bytes, crlf=%s" % (os.path.getsize(p), crlf))

print("FAILURES: %d %s" % (len(fails), fails))
