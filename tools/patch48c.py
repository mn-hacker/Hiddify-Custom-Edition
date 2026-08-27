"""watashi v12.2.48 - part 3: two buttons on the actions page.

The owner asked for a "send a test notification" action. Until now the only way
to learn whether the telegram bot worked was to wait for a real user to hit 80%
of their traffic - and with the dead token found in part 2, that message never
came, so there was no way to tell the difference between "nobody reached 80%"
and "the bot is broken".

Added:
  * POST backup_now         -> writes a backup right now and sends it out
  * POST test_notification  -> one short message to every admin on telegram
plus their two cards in ac_jobs_list(), so they appear on the actions page with
the same confirm dialog as every other job.
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


rel = P + "panel/admin/Actions.py"
bring(rel)
text, crlf = load(rel)
if MARK in text:
    print("Actions.py already carries the mark")
else:
    back(rel)
    views = '''
    # ''' + MARK + ''': the owner needs a way to prove the telegram side works
    # without waiting for a real user to reach their limit.
    @login_required(roles={Role.super_admin, Role.custom})
    @route('backup_now', methods=['POST'])
    def backup_now(self):
        """Write a backup right now, whatever the interval says."""
        try:
            from hiddifypanel.panel.cli import backup_task
            report = backup_task(force=True) or {}
            if report.get('status') == 'ok':
                told = _('The backup was written. %(n)s admin(s) received it on Telegram.', n=report.get('sent', 0))
                kind = 'success'
            else:
                told = _('The backup did not run: %(why)s', why=str(report.get('reason', 'unknown')))
                kind = 'error'
        except Exception as problem:
            print('the backup could not be written', problem)
            told = _('The backup could not be written. Please look at the log.')
            kind = 'error'
        return render_template("result.html",
                               out_type=kind,
                               out_msg=told,
                               log_file_url=None)

    @login_required(roles={Role.super_admin, Role.custom})
    @route('test_notification', methods=['POST'])
    def test_notification(self):
        """Send one short Telegram message, so the bot can be proved at once."""
        try:
            from hiddifypanel.panel.user_notifications import ws_send_test_notification
            report = ws_send_test_notification()
            if report.get('admins'):
                told = _('A test message was sent to %(n)s admin(s).', n=report['admins'])
                kind = 'success'
            else:
                told = _('Nothing was sent: %(why)s', why='; '.join(report.get('errors') or ['unknown']))
                kind = 'error'
        except Exception as problem:
            print('the test notification failed', problem)
            told = _('The test message could not be sent. Please look at the log.')
            kind = 'error'
        return render_template("result.html",
                               out_type=kind,
                               out_msg=told,
                               log_file_url=None)


def ac_usage_size(size):'''
    text = swap(text, "\n\ndef ac_usage_size(size):", views, "Actions.py: the two views")
    cards = '''    jobs.append({
        'key': 'backupnow',
        'group': 'daily',
        'icon': 'fa-download',
        'tone': 'green',
        'name': _('Back up now'),
        'desc': _('Writes a fresh backup of the database and sends it to every admin who connected the Telegram bot. The automatic backup follows the hours you chose in the Telegram settings.'),
        'tag': _('Safe'),
        'tag_kind': 'safe',
        'note': '',
        'btn': _('Back up'),
        'btn_icon': 'fa-download',
        'btn_kind': 'green',
        'method': 'post',
        'url': ac_url('backup_now'),
        'ask': _('Write a backup now?'),
        'body': _('Nothing on the server changes. A json file is written into the backup folder.'),
        'effects': [
            _('A json backup is written.'),
            _('Admins with Telegram receive the file.'),
            _('Only the newest 48 backup files are kept.'),
        ],
        'ok': _('Yes, back up'),
        'danger': False,
    })
    jobs.append({
        'key': 'testnotify',
        'group': 'watch',
        'icon': 'fa-paper-plane',
        'tone': 'cyan',
        'name': _('Send a test notification'),
        'desc': _('Sends one short Telegram message to every admin who connected the bot, so you can see whether the notifications really work.'),
        'tag': _('Only looks'),
        'tag_kind': 'safe',
        'note': _('Open the bot and press start first, otherwise Telegram has nobody to send to.'),
        'btn': _('Send the test'),
        'btn_icon': 'fa-paper-plane',
        'btn_kind': 'ghost',
        'method': 'post',
        'url': ac_url('test_notification'),
        'ask': _('Send a test message now?'),
        'body': _('One message is sent. Nothing on the server changes.'),
        'effects': [
            _('The bot is woken with the saved token.'),
            _('Every admin with Telegram gets one message.'),
        ],
        'ok': _('Yes, send'),
        'danger': False,
    })
    return jobs
'''
    text = swap(text, "    return jobs\n", cards, "Actions.py: the two cards")
    save(rel, text, crlf)

try:
    py_compile.compile(M + rel, cfile="/tmp/w48.pyc", doraise=True)
    print("compiles Actions.py")
except Exception as e:
    fails.append("Actions.py does not compile: %s" % e)

print("FAILURES: %d %s" % (len(fails), fails))
