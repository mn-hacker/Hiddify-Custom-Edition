# watashi v12.2.103: the mieru server, installed like every other core.
#
# The binary is not shipped in this package. core_manager.sh downloads the
# version core_registry.conf blesses and verifies it against packages.lock,
# exactly as it does for xray, sing-box and mtg, so mieru cannot drift onto an
# untested build behind our back.
source /opt/hiddify-manager/common/utils.sh

# watashi v12.2.113: the unit file has to exist before core_manager.sh is
# asked to install mita. cm_activate() ends with "systemctl restart
# watashi-mita.service" and reports failure when the unit does not come up;
# on a first install our symlink was still made *after* that call, so systemd
# had no watashi-mita.service to restart and every single install printed
# "ERROR: watashi-mita.service did not come up with mita 3.36.1" followed by
# "watashi: mita could not be installed, mieru stays off" - while the binary
# was in fact on the disk. Linking first makes the restart inside
# core_manager.sh the real start of the daemon.
mkdir -p /opt/hiddify-manager/log/system

# watashi v12.2.114: mita refuses to run without a system account called
# mita. The daemon chowns its own rpc socket to that account and dies when it
# is missing:
#   FATAL update server unix domain socket permission failed:
#   getUid("mita") failed: user: unknown user mita
# The official .deb/.rpm create the group and the account in their postinst -
# the upstream install guide even tells you to run "usermod -a -G mita $USER"
# afterwards - but we install the bare binary through core_manager.sh, so
# nobody ever created it and the unit crash-looped with status=1/FAILURE on
# every start. The account is created here, with no shell and no home, and
# only when it is not there already.
if ! getent group mita >/dev/null 2>&1; then
    groupadd --system mita 2>/dev/null || true
fi
if ! getent passwd mita >/dev/null 2>&1; then
    # watashi v12.2.130aa: /nonexistent is the usual home of a service account, but
    # the tools on ubuntu 24.04 print 'info: The home dir /nonexistent you
    # specified can't be accessed' about it, and on a clean install that
    # line reads like a fault. A real directory that nobody can enter says
    # the same thing without the complaint.
    install -d -m 0750 -o root -g root /var/lib/mita >/dev/null 2>&1 || true
    useradd --system --gid mita --no-create-home --home-dir /var/lib/mita \
        --shell /usr/sbin/nologin --comment "Watashi mieru server" mita >/dev/null 2>&1 ||
        useradd -r -g mita -M -d /var/lib/mita -s /bin/false mita >/dev/null 2>&1 || true
    chown mita:mita /var/lib/mita >/dev/null 2>&1 || true
fi
if ! getent passwd mita >/dev/null 2>&1; then
    echo "watashi: the mita system account could not be created, mieru cannot start"
fi

chmod 600 *.service* 2>/dev/null || true
# watashi v12.2.130k: this was a symlink into /opt/hiddify-manager. A purge removes
# that folder and leaves an enabled unit aimed at a file that is gone, which is
# why systemd repeated "Failed to open /etc/systemd/system/watashi-mita.service:
# No such file or directory" long after the panel was uninstalled. A copy has no
# such tail. 644 because systemd reads it and 600 buys nothing here.
# watashi v12.2.130k: a box installed before this round still has the old symlink
# here, and that link points back at this very file, so cp said "are the same
# file" and stopped. Removing the destination first handles the old link, a
# dangling link left by a purge, and a stale copy alike.
rm -f /etc/systemd/system/watashi-mita.service
cp -f watashi-mita.service /etc/systemd/system/watashi-mita.service
chmod 644 /etc/systemd/system/watashi-mita.service
systemctl daemon-reload 2>/dev/null || true
# a unit left in failed state by an earlier round refuses to start again
# until its counter is cleared, and that is exactly the state the panel was
# showing as "watashi-mita failed".
systemctl reset-failed watashi-mita.service 2>/dev/null || true

CM_SH=/opt/hiddify-manager/common/core_manager.sh
if [ -f "$CM_SH" ]; then
    # watashi v12.2.111: this said "default mita", and that verb only
    # prints the version core_registry.conf blesses; it downloads
    # nothing. The binary therefore never arrived and other/mieru/run.sh
    # answered "the mita binary is not on the disk, mieru was not
    # started" on every apply, which is exactly what the install log
    # shows. "install" is the verb that downloads, checks the sha256
    # against packages.lock and activates. It is asked only when the
    # binary is missing, so an apply on a healthy box downloads nothing.
    if [ ! -x /opt/hiddify-manager/other/mieru/mita ]; then
        bash $CM_SH install mita || echo "watashi: mita could not be installed, mieru stays off"
    fi
fi

if [ ! -x /opt/hiddify-manager/other/mieru/mita ]; then
    echo "watashi: the mita binary is not on the disk, nothing was enabled"
    exit 0
fi

# watashi v12.2.113: the link and the daemon-reload moved above, before the
# core_manager call. Only the enable is left here, so a reboot brings the
# daemon back without waiting for the next apply_configs.
# watashi v12.2.130k: enable only put it in the boot list, so on a box where the
# download had failed earlier mita stayed dead until the next apply_configs and
# the panel simply showed "inactive" with nothing explaining why.
systemctl enable watashi-mita.service >/dev/null 2>&1 || true
if ! systemctl start watashi-mita.service >/dev/null 2>&1; then
    echo "watashi: mita did not start, mieru stays off. see log/system/mieru.err.log"
fi
