#!/opt/watashi-manager/.venv313/bin/python
# watashi v12.3.40dev: the old project name was taken out of this file (names, paths and links only)
from urllib.parse import urlparse
import click
import os
from strenum import StrEnum
import subprocess
import re
import shutil  # watashi v12.3.38dev: finds systemd-run for the long jobs

WATASHI_DIR = '/opt/watashi-manager/'


class Command(StrEnum):
    '''The value of each command refers to the command shell file'''
    apply = os.path.join(WATASHI_DIR, 'apply_configs.sh')
    install = os.path.join(WATASHI_DIR, 'install.sh')
    # reinstall = os.path.join(WATASHI_DIR,'reinstall.sh')
    update = os.path.join(WATASHI_DIR, 'update.sh')
    status = os.path.join(WATASHI_DIR, 'status.sh')
    restart_services = os.path.join(WATASHI_DIR, 'restart.sh')
    temporary_short_link = os.path.join(WATASHI_DIR, 'nginx/add2shortlink.sh')
    temporary_access = os.path.join(
        WATASHI_DIR, 'watashi-panel/temporary_access.sh')
    update_usage = os.path.join(WATASHI_DIR, 'watashi-panel/update_usage.sh')
    get_cert = os.path.join(WATASHI_DIR, 'acme.sh/get_cert.sh')
    # watashi v12.2.51: the core page needs one root path, and this is it
    core = os.path.join(WATASHI_DIR, 'common/core_manager.sh')
    # apply-users command is actually "install.sh apply_users"
    apply_users = os.path.join(WATASHI_DIR, 'install.sh')
    install_rathole = os.path.join(WATASHI_DIR, 'other/rathole/install_rathole.sh')
    uninstall_rathole = os.path.join(WATASHI_DIR, 'other/rathole/uninstall_rathole.sh')
    create_tunnel = os.path.join(WATASHI_DIR, 'other/rathole/create_tunnel.sh')
    delete_tunnel = os.path.join(WATASHI_DIR, 'other/rathole/delete_tunnel.sh')
    control_tunnel = os.path.join(WATASHI_DIR, 'other/rathole/control_tunnel.sh')
    # watashi v12.2.129: the only root door the nodes page has
    node = os.path.join(WATASHI_DIR, 'other/warp/node.sh')
    # watashi v12.2.130an: everything the panel needs in order to say where the
    # amnezia packets stop, read in one place.
    amnezia_status = os.path.join(WATASHI_DIR, 'other/amnezia/status.sh')
    id = 'id'


def run(cmd: list[str]):
    subprocess.run(cmd, shell=False, check=True)


# watashi v12.3.38dev: install, apply, update and restart-services all stop or
# restart watashi-panel on their way. Started straight from here they lived in
# the panel's own cgroup (the panel runs this file through sudo), so that stop
# took them down too: the update died halfway, nothing started the panel
# again, and the install was cut off right after its "Finished" line. Each of
# them now runs as its own transient systemd unit that a panel stop or restart
# cannot reach. The unit name is fixed per log file, so systemd itself refuses
# a second copy while one is still running, and the very last line of the log
# tells the result page how the job really ended.
JOB_LOGS = {
    'install': 'log/system/0-install.log',  # apply writes here too
    'update': 'log/system/update.log',
    'restart': 'log/system/restart.log',
    'custom': 'log/system/custom-inbounds.log',  # watashi v12.3.41dev: the Inbounds page
}
# sudo has already reduced the environment to a safe set; these are the parts
# of it the scripts got before, a transient unit would start without them.
JOB_ENV = ('PATH', 'HOME', 'USER', 'LOGNAME', 'SHELL', 'MAIL', 'TERM', 'TZ',
           'LANG', 'LANGUAGE', 'SUDO_USER', 'SUDO_UID', 'SUDO_GID', 'SUDO_COMMAND')
JOB_ENV_PREFIX = ('LC_', 'WATASHI_')
# "$@" is the job itself, so none of its arguments ever passes through a shell.
JOB_WRAP = ('name=$1; log=$2; shift 2; "$@"; rc=$?; '
            'if [ "$rc" -eq 0 ]; then end=done; else end=failed; fi; '
            'printf "\\nwatashi-job: %s %s (code %s)\\n" "$name" "$end" "$rc" >>"$log"; '
            'exit "$rc"')
# watashi v12.3.39dev: the same, for a script that only prints and keeps no log of its
# own (acme.sh/get_cert.sh): everything it says goes into the job log.
JOB_WRAP_CAPTURE = JOB_WRAP.replace('"$@"; rc=$?;', '"$@" >>"$log" 2>&1 </dev/null; rc=$?;', 1)


def job_unit(name: str) -> str:
    return f'watashi-job-{name}.service'


def job_running(name: str) -> bool:
    try:
        return subprocess.run(['systemctl', 'is-active', '--quiet', job_unit(name)],
                              capture_output=True).returncode == 0
    except Exception:
        return False


def run_job(name: str, cmd: list[str], log: str = '', capture: bool = False, detach: bool = False):
    # watashi v12.3.39dev: log, capture and detach serve the certificate jobs: one log
    # per domain, written by the job itself, and never waited for.
    log = os.path.join(WATASHI_DIR, log or JOB_LOGS[name])
    os.makedirs(os.path.dirname(log), exist_ok=True)
    job = ['/bin/bash', '-c', JOB_WRAP_CAPTURE if capture else JOB_WRAP, 'watashi-job', name, log, *cmd]
    launcher = shutil.which('systemd-run')
    if not launcher or not os.path.isdir('/run/systemd/system'):
        # no systemd to hand the job to (docker): it runs right here, as before
        if detach:
            subprocess.Popen(job, cwd=WATASHI_DIR, start_new_session=True, stdin=subprocess.DEVNULL,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return
        run(job)
        return
    if job_running(name):
        print(f'the {name} job is already running ({job_unit(name)}), it is not started twice')
        raise SystemExit(3)
    launch = [launcher, '--quiet', '--collect', f'--unit={job_unit(name)}',
              f'--description=Watashi {name} job', '-p', f'WorkingDirectory={WATASHI_DIR}']
    for key, value in os.environ.items():
        if (key in JOB_ENV or key.startswith(JOB_ENV_PREFIX)) and '\n' not in value:
            launch.append(f'--setenv={key}={value}')
    run([*launch, *job])


@click.group(chain=True)
def cli():
    pass


@cli.command('id')
def id():
    out = subprocess.check_output(['id'])
    print(out.decode())


@cli.command('apply')
def apply():
    cmd = [Command.apply.value, '--no-gui']
    run_job('install', cmd)  # watashi v12.3.38dev: same log and lock as install


@cli.command('install')
def install():
    cmd = [Command.install.value, '--no-gui']
    run_job('install', cmd)  # watashi v12.3.38dev


# @cli.command('reinstall')
# def reinstall():
#     cmd = [Command.reinstall.value]
#     run(cmd)


@cli.command('update')
def update():
    cmd = [Command.update.value, '--no-gui']
    run_job('update', cmd)  # watashi v12.3.38dev


@cli.command('restart-services')
def restart_services():
    cmd = [Command.restart_services.value, '--no-gui']
    run_job('restart', cmd)  # watashi v12.3.38dev


@cli.command('status')
def status():
    cmd = [Command.status.value, '--no-gui']
    run(cmd)


def add_temporary_short_link_assert_input(url: str, slug: str) -> None:
    '''Returns None if everything is valid otherwise returns an error'''

    assert url, f"Error: Invalid value for '--url' / '-u': \"\" is not a valid url"

    assert urlparse(url), f"Error: Invalid value for '--url' / '-u': {url} is an invalid url"

    assert slug, f"Error: Invalid value for '-slug' / '-s': \"\" is not a valid slug"

    assert slug.isalnum(), f"Error: Invalid value for '-slug' / '-s': \"\" is not a alphanumeric"

    assert is_valid_url(url), f"Error: Invalid character in url: {url}"

    # don't need to sanitize slug but we do for good (we are not lucky)
    assert is_valid_slug(slug), f"Error: Invalid character in slug: {slug}"


def is_valid_url(url) -> bool:
    if not urlparse(url):
        return False

    pattern = r"^[a-zA-Z0-9:/@.-]+$"
    return bool(re.match(pattern, url))


def is_valid_slug(slug) -> bool:
    pattern = r"^[a-zA-Z0-9\-]+$"
    return bool(re.match(pattern, slug))


@cli.command('temporary-short-link')
@click.option('--url', '-u', type=str, help='The url that is going to be short', required=True)
@click.option('--slug', '-s', type=str, help='The secret code', required=True)
@click.option('--period', '-p', type=int, help='The time period that link remains active', required=False)
def add_temporary_short_link(url: str, slug: str, period: int):
    # validate inputs
    add_temporary_short_link_assert_input(url, slug)

    cmd = [Command.temporary_short_link.value, url, slug, str(period)]

    run(cmd)


# @cli.command('temporary-access')
# @click.option('--port', '-p', type=int, help='The port that is going to be open', required=True)
# def add_temporary_access(port: int):
#     cmd = [Command.temporary_access.value, str(port)]
#     run(cmd)


def is_domain_valid(d):
    pattern = r"^[a-zA-Z0-9\-.]+$"
    return bool(re.match(pattern, d))


# watashi v12.3.39dev: a certificate request is a job of its own now, one per domain.
# It ran inside the panel's cgroup before, so restarting the panel cut it off
# halfway, and it printed into the panel journal, where the admin never saw
# it. Each domain has its own unit and its own log, which the domain card
# reads back, and systemd refuses a second request for a domain whose first
# one is still running.
CERT_JOB_LOG = 'log/system/cert-{}.log'
CERT_DOMAIN = re.compile(r'^(?=.{1,253}$)[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$')


@cli.command('get-cert')
@click.option('--domain', '-d', type=str, help='The domain that needs certificate', required=True)
@click.option('--force', is_flag=True, default=False,
              help='Ask for a new certificate even when the current one is still valid')
def get_cert(domain: str, force: bool):
    if not domain:
        return
    assert is_domain_valid(domain), f"Error: Invalid domain passed to the get_cert command: {domain}"
    assert CERT_DOMAIN.match(domain), f"Error: Invalid domain passed to the get_cert command: {domain}"
    name = f'cert-{domain}'
    if job_running(name):
        print(f'a certificate request for {domain} is already running ({job_unit(name)})')
        raise SystemExit(3)
    log = CERT_JOB_LOG.format(domain)
    path = os.path.join(WATASHI_DIR, log)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w') as fh:
        fh.write('watashi-cert: {} start{}\n'.format(domain, ' force' if force else ''))
    # watashi v12.3.39dev: through bash, so a copy that lost its exec bit (a zip
    # made on windows) still runs instead of failing with code 126.
    cmd = ['/bin/bash', Command.get_cert.value, domain]
    if force:
        cmd.append('--force')
    run_job(name, cmd, log=log, capture=True, detach=True)


@cli.command('update-usage')
def update_usage():
    cmd = [Command.update_usage.value]
    run(cmd)


@cli.command('apply-users')
def apply_users():
    cmd = [Command.apply_users.value, 'apply_users', '--no-gui']
    run(cmd)


def ws_tunnel_transfer(tool: str, nic: str) -> str:
    """Read a wireguard style transfer table without taking the caller down.

    watashi v12.2.64: check_output raises the moment the tool is missing or the
    interface is not up, and the driver that asked for it turns that into a
    failed usage run for every other driver in the same batch. A tunnel that is
    not running is not an error, it is simply nothing to report.
    """
    try:
        out = subprocess.check_output([tool, 'show', nic, 'transfer'], stderr=subprocess.DEVNULL)
    except (FileNotFoundError, PermissionError, subprocess.CalledProcessError):
        return ''
    return out.decode(errors='replace')


@cli.command('update-wg-usage')
def update_wg_usage():
    print(ws_tunnel_transfer('wg', 'watashiwg'))


@cli.command('update-awg-usage')
def update_awg_usage():
    # watashi v12.2.64: the separate AmneziaWG system of v12.2.62 runs on its
    # own interface, named once in other/amnezia/awg_utils.sh. Its bytes never
    # reach the sing-box core, so they have to be read straight off awg.
    print(ws_tunnel_transfer('awg', 'watashi-awg'))


@cli.command('amnezia-status')
def amnezia_status():
    # watashi v12.2.130an: status.sh only looks and always exits 0, so run() with
    # check=True is safe here.
    run([Command.amnezia_status.value])


@cli.command('install-rathole')
def install_rathole():
    cmd = [Command.install_rathole.value]
    run(cmd)


@cli.command('uninstall-rathole')
def uninstall_rathole():
    cmd = [Command.uninstall_rathole.value]
    run(cmd)


@cli.command('create-tunnel')
@click.option('--type', '-t', type=str, help='Tunnel type: iran or kharej', required=True)
@click.option('--tunnel-port', '-p', type=str, help='Tunnel port', required=True)
@click.option('--config-ports', '-c', type=str, help='Config ports (comma-separated)', required=True)
@click.option('--token', '-k', type=str, help='Authentication token', required=True)
@click.option('--server-ip', '-s', type=str, help='Server IP (required for kharej)', default='')
@click.option('--transport', type=str, help='Transport type', default='tcp')
@click.option('--nodelay', type=str, help='TCP nodelay', default='true')
@click.option('--heartbeat', type=str, help='Heartbeat', default='true')
@click.option('--ipv6', type=str, help='Use IPv6', default='false')
def create_tunnel(type, tunnel_port, config_ports, token, server_ip, transport, nodelay, heartbeat, ipv6):
    cmd = [Command.create_tunnel.value, type, tunnel_port, config_ports, token]
    if server_ip:
        cmd.append(f'server_ip={server_ip}')
    cmd.append(f'transport={transport}')
    cmd.append(f'nodelay={nodelay}')
    cmd.append(f'heartbeat={heartbeat}')
    cmd.append(f'ipv6={ipv6}')
    run(cmd)


@cli.command('delete-tunnel')
@click.option('--type', '-t', type=str, help='Tunnel type: iran or kharej', required=True)
@click.option('--tunnel-port', '-p', type=str, help='Tunnel port', required=True)
def delete_tunnel(type, tunnel_port):
    cmd = [Command.delete_tunnel.value, type, tunnel_port]
    run(cmd)


@cli.command('control-tunnel')
@click.option('--action', '-a', type=str, help='Action: start, stop, restart, status, enable, disable', required=True)
@click.option('--type', '-t', type=str, help='Tunnel type: iran or kharej', required=True)
@click.option('--tunnel-port', '-p', type=str, help='Tunnel port', required=True)
def control_tunnel(action, type, tunnel_port):
    cmd = [Command.control_tunnel.value, action, type, tunnel_port]
    run(cmd)


# watashi v12.2.51: the only root door the core page has. Everything that
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
    # watashi v12.2.76: the three actions that download are allowed to write
    # down the sha256 of what they just fetched. core_manager refuses an
    # unpinned version by default, which is right for an unattended run and
    # wrong here: this door is only opened by a super admin pressing a button,
    # and the download is still verified, staged, tried, and rolled back if the
    # service does not come back. without this, every new upstream release dies
    # with 'not pinned in packages.lock' and the page can never leave the old
    # pin. rollback and prune are left out because they never fetch anything.
    if action in ('install', 'upgrade', 'downgrade'):
        os.environ['CM_ALLOW_UNPINNED'] = '1'
    run(cmd)


# watashi v12.2.129: the nodes page. Reading the state of a node and changing
# it both need root, so everything the page asks for arrives here and is
# checked again. The node scripts check the same values a third time, because
# the page is not the only thing that may ever call them.
# watashi v12.2.129.3: job only reads the job file, so it is as harmless as
# show and the panel may ask for it before every write.
WS_NODE_ACTIONS = ('show', 'job', 'on', 'off', 'change-ip', 'set')
WS_NODE_KEYS = ('MODE', 'COUNTRY', 'IPV', 'SCAN', 'DNS', 'TEST_URL')
WS_NODE_VALUE_RE = re.compile(r'^[A-Za-z0-9:/._@?&=%+-]{1,120}$')


@cli.command('node')
@click.option('--action', '-a', type=str, help='show, job, on, off, change-ip or set', required=True)
@click.option('--key', '-k', type=str, help='The engine setting to write', default='')
@click.option('--value', '-v', type=str, help='The value to write', default='')
def node(action: str, key: str, value: str):
    assert action in WS_NODE_ACTIONS, f"Error: {action} is not a node action"
    cmd = ['bash', Command.node.value, action]
    if action == 'set':
        assert key in WS_NODE_KEYS, f"Error: {key} is not a node setting"
        assert WS_NODE_VALUE_RE.match(value or ''), f"Error: Invalid value passed to the node command"
        cmd.extend([key, value])
    run(cmd)


# watashi v12.3.41dev: the Inbounds page of the advanced mode.
#   test    a candidate file of hand built inbounds (stdin) is tried with the
#           real xray binary next to every other xray config of this server,
#           before the panel keeps the row
#   apply   the saved rows are put on the server (xray/custom_apply.sh), as a job
#           of its own; a second apply while one runs asks it for another round
#   status  how the last apply ended, whether one runs, and the end of its log
WS_CUSTOM_ACTIONS = ('test', 'test-singbox', 'apply', 'retry', 'status')  # watashi v12.3.42dev: test-singbox
WS_CUSTOM_FILE = '05_inbounds_90_custom.json'
WS_CUSTOM_TAG_RE = re.compile(r'^custom-[0-9]{1,9}$')
WS_CUSTOM_CERT_RE = re.compile(r'^/opt/watashi-manager/ssl/[A-Za-z0-9._-]{1,253}$')
WS_CUSTOM_MAX = 262144
WS_CUSTOM_STATUS = os.path.join(WATASHI_DIR, 'log/custom_inbounds.status')
WS_CUSTOM_PENDING = os.path.join(WATASHI_DIR, 'log/custom_inbounds.pending')
# watashi v12.3.42dev: the sing-box side of the Inbounds page.
#   test-singbox  a candidate file of hand built sing-box inbounds (stdin) is
#                 checked by the real sing-box next to every other sing-box
#                 config of this server. ShadowTLS is two inbounds, custom-N and
#                 its inner custom-N-in, and the only one that may hand its
#                 connections on (detour), to its own inner inbound only.
WS_SB_CUSTOM_TAG_RE = re.compile(r'^custom-[0-9]{1,9}(-in)?$')
WS_SB_CUSTOM_TYPES = ('hysteria2', 'tuic', 'anytls', 'naive', 'shadowtls', 'shadowsocks', 'snell')
# a hand built inbound takes the panel's certificate of a domain and nothing
# else: no certificate of its own, no ACME, no client certificates to read
WS_SB_CUSTOM_FORBIDDEN = ('acme', 'certificate', 'key', 'client_certificate', 'client_certificate_path',
                          'client_certificate_public_key_sha256')
# Hysteria2 may look like a site, but never serve a folder of this server
WS_SB_MASQUERADE_RE = re.compile(r'^https?://[^\s"]{1,250}$')


def ws_custom_candidate(text: str) -> dict:
    """The candidate, checked again here: the panel is not trusted to have."""
    import json
    assert len(text) <= WS_CUSTOM_MAX, "Error: the candidate is too large"
    data = json.loads(text)
    assert isinstance(data, dict) and set(data) <= {'inbounds'}, "Error: the candidate is not an inbounds file"
    inbounds = data.get('inbounds') or []
    assert isinstance(inbounds, list) and len(inbounds) <= 100, "Error: the candidate has too many inbounds"

    def walk(node):
        if isinstance(node, dict):
            for key, value in node.items():
                assert key != 'fallbacks', "Error: fallbacks are not allowed in a hand built inbound"
                if key in ('certificateFile', 'keyFile'):
                    assert isinstance(value, str) and WS_CUSTOM_CERT_RE.match(value) and '..' not in value, \
                        "Error: a certificate of a hand built inbound has to be one of the panel's certificates"
                walk(value)
        elif isinstance(node, list):
            for value in node:
                walk(value)

    for inbound in inbounds:
        assert isinstance(inbound, dict), "Error: an inbound is not an object"
        assert WS_CUSTOM_TAG_RE.match(str(inbound.get('tag', ''))), "Error: a hand built inbound is tagged custom-<number>"
        walk(inbound)
    return data


def ws_sb_custom_candidate(text: str) -> dict:
    """watashi v12.3.42dev: a sing-box candidate, checked again here: the panel
    is not trusted to have."""
    import json
    assert len(text) <= WS_CUSTOM_MAX, "Error: the candidate is too large"
    data = json.loads(text)
    assert isinstance(data, dict) and set(data) <= {'inbounds'}, "Error: the candidate is not an inbounds file"
    inbounds = data.get('inbounds') or []
    assert isinstance(inbounds, list) and len(inbounds) <= 100, "Error: the candidate has too many inbounds"
    tags = [str(one.get('tag', '')) if isinstance(one, dict) else '' for one in inbounds]
    assert len(set(tags)) == len(tags), "Error: two hand built inbounds have the same tag"

    def walk(node):
        if isinstance(node, dict):
            for key, value in node.items():
                assert key not in WS_SB_CUSTOM_FORBIDDEN, f"Error: {key} is not allowed in a hand built inbound"
                if key in ('certificate_path', 'key_path'):
                    assert isinstance(value, str) and WS_CUSTOM_CERT_RE.match(value) and '..' not in value, \
                        "Error: a certificate of a hand built inbound has to be one of the panel's certificates"
                if key == 'masquerade':
                    assert isinstance(value, str) and WS_SB_MASQUERADE_RE.match(value), \
                        "Error: masquerade can only be the http:// or https:// address of a site"
                walk(value)
        elif isinstance(node, list):
            for value in node:
                walk(value)

    for inbound in inbounds:
        assert isinstance(inbound, dict), "Error: an inbound is not an object"
        tag = str(inbound.get('tag', ''))
        assert WS_SB_CUSTOM_TAG_RE.match(tag), "Error: a hand built inbound is tagged custom-<number>"
        assert inbound.get('type') in WS_SB_CUSTOM_TYPES, "Error: this inbound type cannot be built by hand"
        if 'detour' in inbound:
            assert inbound.get('type') == 'shadowtls' and inbound['detour'] == tag + '-in' and inbound['detour'] in tags, \
                "Error: only ShadowTLS hands its connections on, and only to its own inner inbound"
        walk(inbound)
    return data


def ws_sb_name_inbounds(text: str, folder: str) -> str:
    """watashi v12.3.42dev: sing-box names an inbound by its place in the merged
    config (inbound[12]) or in its file (inbounds[0]); the tag says which one."""
    import json
    merged, per_file = [], {}
    for name in sorted(os.listdir(folder)):
        if not name.endswith('.json'):
            continue
        try:
            with open(os.path.join(folder, name)) as handle:
                found = json.load(handle).get('inbounds') or []
            tags = [str(one.get('tag') or '') if isinstance(one, dict) else '' for one in found]
        except Exception:
            return text  # a file it cannot read would shift every place after it
        per_file[name] = tags
        merged.extend(tags)

    def whole(match):
        place = int(match.group(1))
        return f'inbound[{merged[place]}]' if place < len(merged) and merged[place] else match.group(0)

    def in_file(match):
        tags = per_file.get(os.path.basename(match.group(1))) or []
        place = int(match.group(2))
        return f'{match.group(1)}: inbounds[{tags[place]}]' if place < len(tags) and tags[place] else match.group(0)

    text = re.sub(r'inbound\[(\d+)\]', whole, text)
    return re.sub(r'(\S+\.json): inbounds\[(\d+)\]', in_file, text)


@cli.command('custom-inbounds')
# watashi v12.3.42dev: test-singbox tries the sing-box rows with sing-box itself
@click.option('--action', '-a', type=str, help='test, test-singbox, apply, retry or status', required=True)
def custom_inbounds(action: str):
    import json
    import tempfile
    import glob
    assert action in WS_CUSTOM_ACTIONS, f"Error: {action} is not an action of custom-inbounds"
    if action == 'test':
        data = ws_custom_candidate(click.get_text_stream('stdin').read(WS_CUSTOM_MAX + 1))
        configs = os.path.join(WATASHI_DIR, 'xray/configs')
        with tempfile.TemporaryDirectory(prefix='watashi-custom-') as tmp:
            for one in glob.glob(os.path.join(configs, '*.json')):
                if os.path.basename(one) != WS_CUSTOM_FILE:
                    shutil.copy(one, tmp)
            with open(os.path.join(tmp, WS_CUSTOM_FILE), 'w') as handle:
                json.dump(data, handle)
            done = subprocess.run([os.path.join(WATASHI_DIR, 'xray/bin/xray'), 'run', '-test', '-confdir', tmp],
                                  capture_output=True, text=True, timeout=60)
        print((done.stdout or '') + (done.stderr or ''))
        raise SystemExit(0 if done.returncode == 0 else 1)
    if action == 'test-singbox':
        # watashi v12.3.42dev: the same for a sing-box candidate, with sing-box check
        data = ws_sb_custom_candidate(click.get_text_stream('stdin').read(WS_CUSTOM_MAX + 1))
        configs = os.path.join(WATASHI_DIR, 'singbox/configs')
        with tempfile.TemporaryDirectory(prefix='watashi-custom-') as tmp:
            for one in glob.glob(os.path.join(configs, '*.json')):
                if os.path.basename(one) != WS_CUSTOM_FILE:
                    shutil.copy(one, tmp)
            with open(os.path.join(tmp, WS_CUSTOM_FILE), 'w') as handle:
                json.dump(data, handle)
            done = subprocess.run([os.path.join(WATASHI_DIR, 'singbox/sing-box'), 'check', '-C', tmp],
                                  capture_output=True, text=True, timeout=60, cwd=tmp)
            said = (done.stdout or '') + (done.stderr or '')
            if done.returncode != 0:
                said = ws_sb_name_inbounds(said, tmp)
        print(said)
        raise SystemExit(0 if done.returncode == 0 else 1)
    if action in ('apply', 'retry'):
        # retry: the inbounds the last apply took out get another chance
        # (the "Try again" of the Inbounds page), see xray/custom_apply.sh
        if job_running('install') or job_running('update'):
            print('an install, apply or update is running; it puts the inbounds on the server as well')
            raise SystemExit(4)
        if job_running('custom'):
            # the running job looks for this file when it is done and goes again
            with open(WS_CUSTOM_PENDING, 'w') as handle:
                handle.write('retry' if action == 'retry' else '1')
            print('an apply of the inbounds is running, it goes once more when it is done')
            return
        # one log per apply, so the page shows this one and the file never grows
        log = os.path.join(WATASHI_DIR, JOB_LOGS['custom'])
        os.makedirs(os.path.dirname(log), exist_ok=True)
        with open(log, 'w') as handle:
            handle.write('')
        run_job('custom', ['bash', os.path.join(WATASHI_DIR, 'xray/custom_apply.sh')] + (['--retry'] if action == 'retry' else []),
                capture=True, detach=True)
        print('started')
        return
    # status
    out = {'running': job_running('custom'), 'busy': job_running('install') or job_running('update'),
           'status': {}, 'log': ''}
    try:
        with open(WS_CUSTOM_STATUS) as handle:
            out['status'] = json.load(handle)
    except (OSError, ValueError):
        pass
    try:
        with open(os.path.join(WATASHI_DIR, JOB_LOGS['custom']), errors='replace') as handle:
            out['log'] = ''.join(handle.readlines()[-60:])
    except OSError:
        pass
    print(json.dumps(out))


@cli.command('truncate')
@click.option('--file', '-f', type=str, help='The log file to truncate', required=True)
def truncate(file: str):
    # Security check: only allow files in log/system/
    log_dir = os.path.join(WATASHI_DIR, 'log/system')
    file_path = os.path.join(log_dir, f"{file}.log")
    
    # Resolve absolute path and ensure it starts with log_dir
    # Note: realpath resolves symlinks, abspath doesn't. 
    # Since we construct the path using WATASHI_DIR/log/system, it should be safe unless file contains ..
    if ".." in file or "/" in file:
        raise Exception("Access denied")

    # Ensure directory exists
    os.makedirs(log_dir, exist_ok=True)

    # watashi v12.3.38dev: a job that is still running keeps writing to this
    # file (a second click on the same button). Emptying it would only cut off
    # what that job already wrote, and the page would show half a log.
    for name, owned in JOB_LOGS.items():
        if os.path.basename(owned) == f"{file}.log" and job_running(name):
            print(f"{file}.log belongs to the {name} job, which is still running, so it is left as it is")
            return

    # Truncate
    with open(file_path, 'w') as f:
        f.write("")
    
    # Set permissions so watashi-panel can write to it
    import shutil
    try:
        shutil.chown(file_path, user='watashi-panel', group='watashi-panel')
    except Exception as e:
        print(f"Failed to chown {file_path}: {e}")


# ============================================================
# Connection-limit firewall enforcement
# ============================================================
# The watashi-panel process is unprivileged and cannot touch the firewall, so it
# writes the set of IPs that must be blocked to a handoff file and asks us (root,
# via sudo) to reconcile a dedicated iptables/ip6tables chain with that list.
# This is the step that actually drops traffic from over-limit clients (works
# for every protocol: xray, singbox, wireguard, ...).
CONNLIMIT_CHAIN = "WATASHI_CONNLIMIT"
CONNLIMIT_FILE = os.path.join(WATASHI_DIR, 'log/connlimit_blocked_ips.txt')


def _connlimit_sync_one(binary: str, desired: set):
    """Idempotently reconcile a single firewall family (iptables or ip6tables)
    so that exactly the IPs in ``desired`` are dropped via CONNLIMIT_CHAIN.

    CRITICAL: the jump to our chain MUST sit at position 1 in INPUT.
    common/run.sh uses ``iptables -I`` (insert at top) for ESTABLISHED,RELATED
    accept rules every time apply_configs runs.  If those rules end up above our
    chain, already-open TCP sessions from blocked IPs are accepted before they
    reach our DROP rules and the block has no effect.  We therefore unconditionally
    delete + re-insert our jump on every sync cycle.
    """
    # Skip silently if this firewall binary isn't available on the host.
    if subprocess.run([binary, '-V'], capture_output=True).returncode != 0:
        return

    # 1. Ensure the chain exists.
    if subprocess.run([binary, '-n', '-L', CONNLIMIT_CHAIN], capture_output=True).returncode != 0:
        subprocess.run([binary, '-N', CONNLIMIT_CHAIN], check=False)

    # 2. ALWAYS re-position the jump at INPUT position 1.
    #    Delete first (ignore error if it doesn't exist), then insert at 1.
    subprocess.run([binary, '-D', 'INPUT', '-j', CONNLIMIT_CHAIN],
                   capture_output=True)  # may fail — fine
    subprocess.run([binary, '-I', 'INPUT', '1', '-j', CONNLIMIT_CHAIN], check=False)

    # 3. Read the rules currently in the chain.
    out = subprocess.run([binary, '-S', CONNLIMIT_CHAIN], capture_output=True, text=True).stdout or ""
    current = set()
    for line in out.splitlines():
        m = re.match(r'-A\s+%s\s+-s\s+(\S+)\s+-j\s+DROP' % re.escape(CONNLIMIT_CHAIN), line.strip())
        if m:
            current.add(m.group(1).split('/')[0])  # strip /32 or /128 mask

    # 4. Add the rules that should exist but don't.
    for ip in desired - current:
        subprocess.run([binary, '-A', CONNLIMIT_CHAIN, '-s', ip, '-j', 'DROP'], check=False)
        # Kill existing conntrack entries so ESTABLISHED sessions are broken
        # immediately (even before the next packet triggers our DROP rule).
        subprocess.run(['conntrack', '-D', '-s', ip], capture_output=True)

    # 5. Remove rules that should no longer exist (expired / unblocked).
    for ip in current - desired:
        subprocess.run([binary, '-D', CONNLIMIT_CHAIN, '-s', ip, '-j', 'DROP'], check=False)


@cli.command('connlimit-sync')
def connlimit_sync():
    """Reconcile the firewall with the connection-limit blocked-IP list."""
    import ipaddress
    desired_v4, desired_v6 = set(), set()
    if os.path.exists(CONNLIMIT_FILE):
        with open(CONNLIMIT_FILE) as f:
            for line in f:
                ip = line.strip()
                if not ip:
                    continue
                try:
                    obj = ipaddress.ip_address(ip)  # injection-safe: only clean IPs pass
                except ValueError:
                    continue
                (desired_v4 if obj.version == 4 else desired_v6).add(ip)

    _connlimit_sync_one('iptables', desired_v4)
    _connlimit_sync_one('ip6tables', desired_v6)
    print(f"connlimit-sync: enforcing {len(desired_v4)} IPv4 + {len(desired_v6)} IPv6 block(s).")


if __name__ == "__main__":
    cli()
