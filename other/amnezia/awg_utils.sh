# watashi v12.3.40dev: the old project name was taken out of this file (names, paths and links only)
# watashi: the separate AmneziaWG system v12.2.62
#
# AmneziaWG is run by its own daemon here, not inside the sing-box core. The
# core is meant to come from its own upstream repository one day, and upstream
# sing-box has no "awg" endpoint type at all, so this tunnel has to be able to
# stand on its own feet.
#
# Nothing in this file starts or stops anything. It only names things, so that
# install.sh, run.sh and disable.sh can never drift apart on a path or a unit.

SERVER_AWG_NIC=watashi-awg
AWG_DIR=/etc/amnezia/amneziawg
AWG_CONF="$AWG_DIR/$SERVER_AWG_NIC.conf"
AWG_UNIT="awg-quick@$SERVER_AWG_NIC"
AWG_LOG=/opt/watashi-manager/log/system/amnezia.log

# awg-quick keeps wg-quick's rule for interface names:
#     ^[a-zA-Z0-9_=+.-]{1,15}$
# "watashi-awg" is 11 characters and the dash is inside that set, so the name
# is also safe as a systemd instance in awg-quick@watashi-awg.service, where
# systemd hands it to the unit as %i without touching the dash.
ws_awg_name_ok() {
    printf '%s' "$SERVER_AWG_NIC" | grep -Eq '^[a-zA-Z0-9_=+.-]{1,15}$'
}

# amneziawg-tools installs both "awg" and "awg-quick". A userspace build
# answers to the same two names once it is on the path, so one test covers
# either way of getting it onto the machine.
ws_awg_ready() {
    command -v awg >/dev/null 2>&1 && command -v awg-quick >/dev/null 2>&1
}

# watashi v12.3.35dev: the amneziawg kernel module did not build on Ubuntu 26.04.
# Its compat/compat.h maps setup_udp_tunnel_sock() and udp_tunnel_sock_release()
# to the old "struct socket *" API for every kernel below 7.1.5 (upstream
# 0bcc6df), but Ubuntu backported half of that change into its own 7.0.0-42:
# setup_udp_tunnel_sock() already takes "struct sock *" there while
# udp_tunnel_sock_release() still takes "struct socket *". No version check can
# be right for that kernel, so the build died with -Wincompatible-pointer-types
# and left amneziawg-dkms half-configured in dpkg, which made every later
# apt-get install on the box fail as well.
#
# This reads the real header of the running kernel and drops only the compat
# define whose function already has the new signature, then lets dpkg finish
# the configure step. It does nothing when the module is already installed,
# when the header is not there, or when compat.h no longer carries the define
# (an upstream fix), so it is safe to run on every install.
ws_awg_heal_dkms() {
    local kver="${WS_AWG_KVER:-$(uname -r)}"
    command -v dkms >/dev/null 2>&1 || return 0
    dkms status -m amneziawg -k "$kver" 2>/dev/null | grep -q ': installed' && return 0
    local hdr="/usr/src/linux-headers-$kver/include/net/udp_tunnel.h"
    local src
    src=$(ls -d /usr/src/amneziawg-* 2>/dev/null | sort -V | tail -n 1)
    [ -f "$hdr" ] && [ -f "$src/compat/compat.h" ] || return 0
    local changed=0
    if grep -Eq 'setup_udp_tunnel_sock\(struct net \*net, struct sock \*sk' "$hdr" \
        && grep -q '^#define setup_udp_tunnel_sock(' "$src/compat/compat.h"; then
        sed -i '/^#define setup_udp_tunnel_sock(/d' "$src/compat/compat.h"
        changed=1
    fi
    if grep -Eq 'udp_tunnel_sock_release\(struct sock \*sk' "$hdr" \
        && grep -q '^#define udp_tunnel_sock_release(' "$src/compat/compat.h"; then
        sed -i '/^#define udp_tunnel_sock_release(/d' "$src/compat/compat.h"
        changed=1
    fi
    [ "$changed" = 1 ] || return 0
    ws_awg_say "the amneziawg module does not fit the udp tunnel api of kernel $kver, adjusting its compat header and building it again"
    DEBIAN_FRONTEND=noninteractive dpkg --configure -a >/dev/null 2>&1
    if dkms status -m amneziawg -k "$kver" 2>/dev/null | grep -q ': installed'; then
        ws_awg_say "the amneziawg module is built for kernel $kver now"
    else
        ws_awg_say "the amneziawg module still does not build for kernel $kver, see $(ls -d /var/lib/dkms/amneziawg/*/build 2>/dev/null | tail -n 1)/make.log"
    fi
    return 0
}

# H1..H4 are the four packet type numbers AmneziaWG writes instead of the ones
# WireGuard uses. Plain WireGuard uses 1, 2, 3 and 4, so any value below 5
# leaves the packet header exactly as recognisable as it was.
ws_awg_headers_disguised() {
    local h
    for h in "$1" "$2" "$3" "$4"; do
        case "$h" in
            '' | *[!0-9]*) return 1 ;;
        esac
        [ "$h" -ge 5 ] || return 1
    done
}

ws_awg_say() {
    echo "amnezia: $*"
    mkdir -p "$(dirname "$AWG_LOG")" >/dev/null 2>&1
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >>"$AWG_LOG" 2>/dev/null || true
}
