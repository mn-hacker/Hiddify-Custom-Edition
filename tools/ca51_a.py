"""Watashi v12.2.51: the core page.

The panel used to have no idea which version of Xray or sing-box it was
running, and the only way to change a core was to edit packages.lock by hand
and run the installer over ssh. This page reads the state from
common/core_manager.sh and asks it, through the commander, to install, upgrade,
downgrade or roll back a core.

Reading is done in this process because it only looks at files. Anything that
writes goes through sudo common/commander.py, which validates its own input
again, so a broken form on this page can never turn into a shell command.
"""
import json
import os
import re
import subprocess

from flask import render_template, request
from flask_classful import FlaskView, route
from flask_babel import gettext as _
from flask import current_app as app

from hiddifypanel.auth import login_required
from hiddifypanel.models import Role
from hiddifypanel.panel.run_commander import commander, Command

WS_MANAGER_DIR = os.environ.get('HIDDIFY_CONFIG_PATH', '/opt/hiddify-manager')
WS_CORE_MANAGER = os.path.join(WS_MANAGER_DIR, 'common/core_manager.sh')
WS_CORE_REGISTRY = os.path.join(WS_MANAGER_DIR, 'common/core_registry.conf')
WS_NAME_RE = re.compile(r'^[a-z0-9][a-z0-9._-]{0,39}$')
WS_VERSION_RE = re.compile(r'^[0-9][0-9A-Za-z.+_-]{0,39}$')
WS_WRITE_ACTIONS = ('install', 'upgrade', 'downgrade', 'rollback', 'prune')
WS_READ_TIMEOUT = 25


def ws_core_json():
    """What every registered core is doing right now. Never raises."""
    if not os.path.exists(WS_CORE_MANAGER):
        return [], _('The core manager is not installed on this server yet.')
    try:
        out = subprocess.check_output(
            ['bash', WS_CORE_MANAGER, 'json'],
            stderr=subprocess.DEVNULL,
            timeout=WS_READ_TIMEOUT,
        ).decode('utf-8', 'replace')
        rows = json.loads(out)
        if not isinstance(rows, list):
            return [], _('The core manager gave an answer this page cannot read.')
        return rows, ''
    except subprocess.TimeoutExpired:
        return [], _('The core manager did not answer in time.')
    except Exception as problem:
        app.logger.error(f'the core list could not be read: {problem}')
        return [], _('The core list could not be read. Look at log/system/core_manager.log.')


def ws_registry_extras():
    """The bits of the registry the json output does not carry: repository and
    the range of versions this panel was actually tested against."""
    extras = {}
    try:
        with open(WS_CORE_REGISTRY, 'r', encoding='utf-8', errors='replace') as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith('#'):
                    continue
                parts = line.split('|')
                if len(parts) < 10:
                    continue
                extras[parts[0]] = {
                    'repo': parts[1],
                    'tested_min': parts[8],
                    'tested_max': parts[9],
                }
    except FileNotFoundError:
        pass
    except Exception as problem:
        app.logger.error(f'the core registry could not be read: {problem}')
    return extras


def ws_cores():
    """The table this page draws."""
    rows, error = ws_core_json()
    extras = ws_registry_extras()
    for row in rows:
        extra = extras.get(row.get('name', ''), {})
        row['repo'] = extra.get('repo', '')
        row['tested_min'] = extra.get('tested_min', '')
        row['tested_max'] = extra.get('tested_max', row.get('tested', ''))
        row['off_tested'] = bool(row.get('installed')) and row.get('installed') != row.get('tested')
    return rows, error


def ws_ask(action, name, version=''):
    """Hand a change to the commander. Returns (ok, text)."""
    if action not in WS_WRITE_ACTIONS:
        return False, _('That is not something this page can do.')
    if not WS_NAME_RE.match(name or ''):
        return False, _('That core name does not look like a core name.')
    if version and not WS_VERSION_RE.match(version):
        return False, _('That version does not look like a version.')
    try:
        out = commander(Command.core, run_in_background=False,
                        action=action, name=name, version=version) or ''
        return True, out.strip()[-4000:]
    except subprocess.CalledProcessError as problem:
        text = (problem.output or b'').decode('utf-8', 'replace') if isinstance(problem.output, bytes) else str(problem.output)
        return False, text.strip()[-4000:] or _('The core manager refused this change.')
    except Exception as problem:
        app.logger.error(f'the core change failed: {problem}')
        return False, str(problem)[-400:]
