

class CoreAdmin(FlaskView):
    """Cores: what is installed, what was tested, and the buttons to change it."""

    decorators = [login_required({Role.super_admin})]

    def index(self):
        cores, error = ws_cores()
        counts = {
            'total': len(cores),
            'installed': sum(1 for c in cores if c.get('installed')),
            'missing': sum(1 for c in cores if not c.get('installed')),
            'off_tested': sum(1 for c in cores if c.get('off_tested')),
        }
        return render_template('cores.html', cores=cores, counts=counts, core_error=error)

    def _json(self, payload, code=200):
        return app.response_class(json.dumps(payload), mimetype='application/json', status=code)

    @route('list')
    def list_cores(self):
        """The same table, for the page to refresh itself without a reload."""
        cores, error = ws_cores()
        return self._json({'ok': not error, 'cores': cores, 'error': error})

    @route('latest/<name>')
    def latest(self, name):
        """Ask the vendor what the newest release is. This one touches the
        network, so the page asks for it per core and only when told to."""
        if not WS_NAME_RE.match(name or ''):
            return self._json({'ok': False, 'error': _('That core name does not look like a core name.')}, 400)
        try:
            out = subprocess.check_output(
                ['bash', WS_CORE_MANAGER, 'latest', name],
                stderr=subprocess.DEVNULL,
                timeout=WS_READ_TIMEOUT,
            ).decode('utf-8', 'replace').strip()
        except Exception as problem:
            app.logger.error(f'the latest version of {name} could not be read: {problem}')
            return self._json({'ok': False, 'error': _('The vendor could not be reached.')})
        if not out or not WS_VERSION_RE.match(out):
            return self._json({'ok': False, 'error': _('The vendor did not name a version.')})
        return self._json({'ok': True, 'name': name, 'latest': out})

    @route('change', methods=['POST'])
    def change(self):
        """Install, upgrade, downgrade, roll back or prune one core."""
        data = request.get_json(silent=True) or request.form or {}
        action = str(data.get('action', '')).strip()
        name = str(data.get('name', '')).strip()
        version = str(data.get('version', '')).strip()
        ok, text = ws_ask(action, name, version)
        cores, _error = ws_cores()
        return self._json({'ok': ok, 'log': text, 'cores': cores}, 200 if ok else 400)
