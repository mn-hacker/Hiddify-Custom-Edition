#!/bin/bash
# watashi v12.2.50: the core manager.
#
# every core of this panel (xray, sing-box, mtg, wgcf, ssh-liberty-bridge,
# v2ray-plugin) used to be installed by its own script with its own habits.
# none of them kept the previous binary, so a bad release left a dead service
# and nothing to go back to, and download_package copied an unverified file
# straight over the live binary before it checked the hash.
#
# this file is the single place that knows how to fetch, verify, stage, probe,
# activate, roll back and prune a core:
#
#   bash common/core_manager.sh status
#   bash common/core_manager.sh install xray 26.7.28
#   bash common/core_manager.sh rollback xray
#   bash common/core_manager.sh json

WS_ROOT=${WS_ROOT:-/opt/hiddify-manager}
CM_DIR=${CM_DIR:-$WS_ROOT/common}
CM_REGISTRY=${CM_REGISTRY:-$CM_DIR/core_registry.conf}
CM_LOCK=${CM_LOCK:-$CM_DIR/packages.lock}
CM_STORE=${CM_STORE:-$CM_DIR/cores}
CM_DB=${CM_DB:-$CM_STORE/installed.db}
CM_KEEP=${CM_KEEP:-2}
CM_GH_API=${CM_GH_API:-https://api.github.com}
CM_GH_DL=${CM_GH_DL:-https://github.com}
CM_LOG=${CM_LOG:-$WS_ROOT/log/system/core_manager.log}
CM_ALLOW_UNPINNED=${CM_ALLOW_UNPINNED:-0}
CM_PROBE_WAIT=${CM_PROBE_WAIT:-2}

mkdir -p "$CM_STORE" 2>/dev/null
mkdir -p "$(dirname "$CM_LOG")" 2>/dev/null
touch "$CM_DB" 2>/dev/null

# progress goes to stderr on purpose: stdout of cm_download and cm_stage is the
# path of the file they produced, and a chatty stdout would poison it.
cm_log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') | $*" >>"$CM_LOG" 2>/dev/null
    echo "$*" >&2
}

cm_err() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') | ERROR | $*" >>"$CM_LOG" 2>/dev/null
    echo "ERROR: $*" >&2
}

cm_arch() {
    case "$(uname -m)" in
    x86_64 | amd64) echo amd64 ;;
    aarch64 | arm64) echo arm64 ;;
    *) echo "" ;;
    esac
}

# one registry line; comments and blank lines are ignored
cm_row() {
    grep -v '^[[:space:]]*#' "$CM_REGISTRY" 2>/dev/null | awk -F'|' -v n="$1" '$1==n {print; exit}'
}

cm_field() {
    echo "$1" | awk -F'|' -v i="$2" '{print $i}'
}

cm_cores() {
    grep -v '^[[:space:]]*#' "$CM_REGISTRY" 2>/dev/null | awk -F'|' 'NF>=10 {print $1}'
}

# what the record says. the record only knows the versions this manager put
# there itself.
cm_recorded() {
    awk -F'|' -v n="$1" '$1==n {v=$2} END {print v}' "$CM_DB" 2>/dev/null
}

# watashi v12.2.82: ask the binary that is actually live. every core installed
# by the old per core scripts, which is all of them on an existing server, has
# no row in installed.db, so the panel page said "not installed" about six
# cores that were running the whole time. this is quiet on purpose: no log line
# and no stderr, because it runs once per core on every page load.
cm_disk_version() {
    local name=$1 bin cmd out
    bin=$(cm_target "$name")
    if [ ! -x "$bin" ]; then return 1; fi
    cmd=$(cm_field "$(cm_row "$name")" 8)
    if [ -z "$cmd" ] || [ "$cmd" = "-" ]; then return 1; fi
    cmd=${cmd//@BIN@/$bin}
    out=$(eval "$cmd" 2>/dev/null | head -1)
    if [ -z "$out" ]; then return 1; fi
    echo "$out" | grep -oE '[0-9]+[.][0-9]+([.][0-9A-Za-z_+-]+)*' | head -1
}

# is there a binary at all, even one that will not name its version
cm_present() {
    if [ -f "$(cm_target "$1")" ]; then echo true; else echo false; fi
}

cm_installed() {
    local v
    v=$(cm_recorded "$1")
    if [ -n "$v" ]; then
        echo "$v"
        return 0
    fi
    cm_disk_version "$1" 2>/dev/null
}

# where the version came from, so the page can be honest about it
cm_source() {
    if [ -n "$(cm_recorded "$1")" ]; then
        echo record
    elif [ -n "$(cm_disk_version "$1" 2>/dev/null)" ]; then
        echo disk
    else
        echo none
    fi
}

cm_record() {
    local name=$1 version=$2
    mkdir -p "$CM_STORE/$name"
    grep -v "^$name|" "$CM_DB" 2>/dev/null >"$CM_DB.tmp"
    echo "$name|$version|$(date +%s)" >>"$CM_DB.tmp"
    mv "$CM_DB.tmp" "$CM_DB"
    echo "$version|$(date +%s)" >>"$CM_STORE/$name/history"
}

cm_tested() {
    cm_field "$(cm_row "$1")" 10
}

cm_unit() {
    local u
    u=$(cm_field "$(cm_row "$1")" 7)
    if [ "$u" = "-" ]; then u=""; fi
    echo "$u"
}

cm_target() {
    echo "$WS_ROOT/$(cm_field "$(cm_row "$1")" 6)"
}

# watashi v12.2.82: the stable line of this core, and the channel it follows.
# the panel has a beta channel of its own (package_mode) and it never reached
# the cores; what did reach them was the tested pin, and in v12.2.75 that pin
# was moved to a version the vendor publishes as a pre-release. so: stable is
# what this manager installs when nobody names a version, and a test build is
# only ever installed by a hand typing it.
cm_stable() {
    cm_field "$(cm_row "$1")" 11
}

cm_channel() {
    local c
    c=$(cm_field "$(cm_row "$1")" 12)
    if [ -z "$c" ] || [ "$c" = "-" ]; then c=stable; fi
    echo "$c"
}

# what upgrade installs when it is not told a version
cm_default_version() {
    local v=""
    if [ "$(cm_channel "$1")" = "stable" ]; then v=$(cm_stable "$1"); fi
    if [ -z "$v" ]; then v=$(cm_tested "$1"); fi
    echo "$v"
}

cm_newer() {
    printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1
}

# is what is running past the stable line this panel trusts
cm_is_pre() {
    local inst stable
    inst=$(cm_installed "$1")
    stable=$(cm_stable "$1")
    if [ -z "$inst" ] || [ -z "$stable" ] || [ "$inst" = "$stable" ]; then
        echo false
        return 0
    fi
    if [ "$(cm_newer "$inst" "$stable")" = "$inst" ]; then echo true; else echo false; fi
}

# the newest release the vendor calls stable. releases/latest never answers
# with a pre-release, which is exactly why this is the default door.
cm_latest() {
    local repo tag
    repo=$(cm_field "$(cm_row "$1")" 2)
    if [ -z "$repo" ]; then return 1; fi
    tag=$(curl -fsSL --connect-timeout 10 "$CM_GH_API/repos/$repo/releases/latest" 2>/dev/null | grep -m1 '"tag_name"' | cut -d'"' -f4)
    if [ -z "$tag" ]; then return 1; fi
    echo "${tag#v}"
}

# watashi v12.2.82: only asked for by hand. the vendor of xray marks nearly
# every release as a pre-release, so this is the only way to reach them, and
# it is never the default.
cm_latest_pre() {
    local repo tag
    repo=$(cm_field "$(cm_row "$1")" 2)
    if [ -z "$repo" ]; then return 1; fi
    tag=$(curl -fsSL --connect-timeout 10 "$CM_GH_API/repos/$repo/releases?per_page=8" 2>/dev/null | grep -m1 '"tag_name"' | cut -d'"' -f4)
    if [ -z "$tag" ]; then return 1; fi
    echo "${tag#v}"
}

cm_asset() {
    local row idx
    row=$(cm_row "$1")
    if [ -z "$row" ]; then return 1; fi
    case "$3" in
    amd64) idx=4 ;;
    arm64) idx=5 ;;
    *) return 1 ;;
    esac
    cm_field "$row" "$idx" | sed "s/@V@/$2/g"
}

cm_url() {
    local repo asset
    repo=$(cm_field "$(cm_row "$1")" 2)
    asset=$(cm_asset "$1" "$2" "$3") || return 1
    echo "$CM_GH_DL/$repo/releases/download/v$2/$asset"
}

cm_sha() {
    sha256sum "$1" 2>/dev/null | awk '{print $1}'
}

# the pinned hash for exactly this name, version and arch
cm_lock_hash() {
    awk -F'|' -v n="$1" -v v="$2" -v a="$3" '$1==n && $2==v && $3==a {print $5; exit}' "$CM_LOCK" 2>/dev/null
}

cm_pin() {
    local name=$1 version=$2 arch=$3 url=$4 hash=$5
    if grep -q "^$name|$version|$arch|" "$CM_LOCK" 2>/dev/null; then return 0; fi
    echo "$name|$version|$arch|$url|$hash" >>"$CM_LOCK"
    cm_log "pinned $name $version $arch with sha256 $hash"
}

# download into the version store, never next to the live binary
cm_download() {
    local name=$1 version=$2 arch dir asset url want got
    arch=$(cm_arch)
    if [ -z "$arch" ]; then
        cm_err "unsupported architecture $(uname -m)"
        return 1
    fi
    asset=$(cm_asset "$name" "$version" "$arch")
    if [ -z "$asset" ]; then
        cm_err "$name is not in the registry"
        return 1
    fi
    url=$(cm_url "$name" "$version" "$arch")
    dir="$CM_STORE/$name/$version"
    mkdir -p "$dir"
    if [ ! -s "$dir/$asset" ]; then
        cm_log "fetching $name $version ($arch) from $url"
        if ! curl -fsSL --connect-timeout 15 -o "$dir/$asset.part" "$url"; then
            cm_err "could not download $url"
            rm -f "$dir/$asset.part"
            return 2
        fi
        mv "$dir/$asset.part" "$dir/$asset"
    fi
    got=$(cm_sha "$dir/$asset")
    want=$(cm_lock_hash "$name" "$version" "$arch")
    if [ -n "$want" ]; then
        if [ "$want" != "$got" ]; then
            cm_err "sha256 mismatch for $name $version: expected $want, got $got"
            rm -f "$dir/$asset"
            return 3
        fi
        cm_log "sha256 verified for $name $version"
    elif [ "$CM_ALLOW_UNPINNED" = "1" ]; then
        cm_pin "$name" "$version" "$arch" "$url" "$got"
    else
        cm_err "$name $version is not pinned in packages.lock. re-run with CM_ALLOW_UNPINNED=1 to accept sha256 $got"
        return 4
    fi
    echo "$dir/$asset"
}

# unpack whatever shape the release has into one predictable binary
cm_stage() {
    local name=$1 version=$2 archive=$3 dir kind binname out found
    kind=$(cm_field "$(cm_row "$name")" 3)
    binname=$(basename "$(cm_target "$name")")
    dir="$CM_STORE/$name/$version"
    out="$dir/bin/$binname"
    mkdir -p "$dir/bin" "$dir/work"
    rm -rf "$dir/work"/* 2>/dev/null
    case "$kind" in
    bin)
        cp -f "$archive" "$out"
        ;;
    zip)
        if ! unzip -o -q "$archive" -d "$dir/work"; then
            cm_err "could not unzip $archive"
            return 1
        fi
        ;;
    tgz)
        if ! tar -xf "$archive" -C "$dir/work" 2>/dev/null; then
            cm_err "could not untar $archive"
            return 1
        fi
        ;;
    *)
        cm_err "unknown package kind '$kind' for $name"
        return 1
        ;;
    esac
    if [ "$kind" != "bin" ]; then
        # watashi: find the binary by name instead of guessing the directory
        # shape. the old singbox installer used [ -d "sing-box-"* ], which is a
        # bash error the moment that glob matches more than one thing.
        found=$(find "$dir/work" -type f -name "$binname" -print -quit 2>/dev/null)
        if [ -z "$found" ]; then
            found=$(find "$dir/work" -type f -name "$binname"'*' -print -quit 2>/dev/null)
        fi
        if [ -z "$found" ]; then
            found=$(find "$dir/work" -maxdepth 3 -type f -perm -u+x -print -quit 2>/dev/null)
        fi
        if [ -z "$found" ]; then
            cm_err "no binary named $binname inside $archive"
            return 1
        fi
        cp -f "$found" "$out"
    fi
    chmod +x "$out" 2>/dev/null
    rm -rf "$dir/work" 2>/dev/null
    echo "$out"
}

# does this binary actually run on this machine?
cm_probe() {
    local name=$1 bin=$2 cmd out rc
    cmd=$(cm_field "$(cm_row "$name")" 8)
    if [ -z "$cmd" ] || [ "$cmd" = "-" ]; then
        if [ -x "$bin" ]; then return 0; fi
        return 1
    fi
    cmd=${cmd//@BIN@/$bin}
    out=$(eval "$cmd" 2>&1)
    rc=$?
    if [ $rc -ne 0 ] || [ -z "$out" ]; then
        cm_err "$name did not answer '$cmd'"
        return 1
    fi
    echo "$out" | head -1
    return 0
}

cm_unit_ok() {
    local unit=$1
    if [ -z "$unit" ]; then return 0; fi
    if systemctl is-active --quiet "$unit.service" 2>/dev/null; then return 0; fi
    return 1
}

# put a staged version in place, and undo it the moment it does not work
cm_activate() {
    local name=$1 version=$2 force=$3 bin target unit prev binname
    binname=$(basename "$(cm_target "$name")")
    bin="$CM_STORE/$name/$version/bin/$binname"
    target=$(cm_target "$name")
    unit=$(cm_unit "$name")
    prev=$(cm_installed "$name")
    if [ ! -f "$bin" ]; then
        cm_err "$name $version is not staged"
        return 1
    fi
    if [ "$force" != "force" ] && ! cm_probe "$name" "$bin" >/dev/null; then
        cm_err "$name $version does not run here, nothing was changed"
        return 2
    fi

    # watashi: keep whatever is live right now, so there is always something to
    # go back to. this is the part that did not exist before v12.2.50.
    if [ -f "$target" ] && [ -n "$prev" ] && [ ! -f "$CM_STORE/$name/$prev/bin/$binname" ]; then
        mkdir -p "$CM_STORE/$name/$prev/bin"
        cp -f "$target" "$CM_STORE/$name/$prev/bin/$binname"
    fi

    mkdir -p "$(dirname "$target")"
    if ! cp -f "$bin" "$target.cmnew"; then return 1; fi
    chmod +x "$target.cmnew"
    mv -f "$target.cmnew" "$target"
    cm_record "$name" "$version"
    cm_log "$name is now $version"

    if [ -n "$unit" ]; then
        systemctl restart "$unit.service" 2>/dev/null
        sleep "$CM_PROBE_WAIT"
        if ! cm_unit_ok "$unit"; then
            cm_err "$unit.service did not come up with $name $version"
            if [ "$force" != "force" ] && [ -n "$prev" ] && [ "$prev" != "$version" ]; then
                cm_log "rolling $name back to $prev"
                cm_activate "$name" "$prev" force
                return 3
            fi
            return 3
        fi
    fi
    return 0
}

cm_install() {
    local name=$1 version=$2 archive bin rc
    if [ -z "$(cm_row "$name")" ]; then
        cm_err "$name is not a known core"
        return 1
    fi
    if [ -z "$version" ] || [ "$version" = "tested" ]; then
        version=$(cm_default_version "$name")  # watashi v12.2.82: stable unless the registry says otherwise
    elif [ "$version" = "latest" ]; then
        version=$(cm_latest "$name")
        if [ -z "$version" ]; then
            cm_err "could not ask $name for its latest version"
            return 1
        fi
    fi
    if [ -z "$version" ]; then
        cm_err "no version to install for $name"
        return 1
    fi
    archive=$(cm_download "$name" "$version")
    rc=$?
    if [ $rc -ne 0 ]; then return $rc; fi
    bin=$(cm_stage "$name" "$version" "$archive")
    if [ -z "$bin" ]; then return 1; fi
    cm_activate "$name" "$version"
    rc=$?
    if [ $rc -ne 0 ]; then return $rc; fi
    cm_prune "$name"
    return 0
}

cm_rollback() {
    local name=$1 cur prev binname
    cur=$(cm_installed "$name")
    binname=$(basename "$(cm_target "$name")")
    prev=$(awk -F'|' '{print $1}' "$CM_STORE/$name/history" 2>/dev/null | grep -v "^$cur\$" | tail -1)
    if [ -z "$prev" ]; then
        cm_err "no previous version of $name is kept"
        return 1
    fi
    if [ ! -f "$CM_STORE/$name/$prev/bin/$binname" ]; then
        cm_err "the kept copy of $name $prev is missing"
        return 1
    fi
    cm_log "rolling $name back from ${cur:-unknown} to $prev"
    cm_activate "$name" "$prev" force
}

# keep the version in use plus CM_KEEP older ones
cm_prune() {
    local name=$1 cur d v keep
    cur=$(cm_installed "$name")
    keep=$(awk -F'|' '{print $1}' "$CM_STORE/$name/history" 2>/dev/null | tac | awk '!seen[$0]++' | head -n "$((CM_KEEP + 1))")
    for d in "$CM_STORE/$name"/*/; do
        if [ ! -d "$d" ]; then continue; fi
        v=$(basename "$d")
        if [ "$v" = "$cur" ]; then continue; fi
        if ! echo "$keep" | grep -qx "$v"; then
            rm -rf "$d"
            cm_log "removed the kept copy of $name $v"
        fi
    done
}

cm_status() {
    local name inst tested unit state
    printf '%-20s %-14s %-14s %-9s %s\n' CORE INSTALLED TESTED SERVICE PATH
    for name in $(cm_cores); do
        inst=$(cm_installed "$name")
        tested=$(cm_tested "$name")
        unit=$(cm_unit "$name")
        if [ -z "$unit" ]; then
            state="-"
        elif cm_unit_ok "$unit"; then
            state=active
        else
            state=down
        fi
        printf '%-20s %-14s %-14s %-9s %s\n' "$name" "${inst:-unknown}" "$(cm_default_version "$name")" "$state" "$(cm_target "$name")"  # watashi v12.2.82
    done
}

# what the panel page will read
cm_json() {
    local name inst tested unit active utd first=1 stable channel pre present source want
    printf '['
    for name in $(cm_cores); do
        inst=$(cm_installed "$name")
        tested=$(cm_tested "$name")
        unit=$(cm_unit "$name")
        # watashi v12.2.82: four fields the page never had. without them it
        # could only guess, and it guessed "not installed" six times.
        stable=$(cm_stable "$name")
        channel=$(cm_channel "$name")
        pre=$(cm_is_pre "$name")
        present=$(cm_present "$name")
        source=$(cm_source "$name")
        want=$(cm_default_version "$name")
        if [ -z "$unit" ]; then
            active=null
        elif cm_unit_ok "$unit"; then
            active=true
        else
            active=false
        fi
        # being ahead of the stable line is not being behind it
        if [ -n "$inst" ] && { [ "$inst" = "$want" ] || [ "$pre" = true ]; }; then utd=true; else utd=false; fi
        if [ $first -eq 0 ]; then printf ','; fi
        first=0
        printf '{"name":"%s","installed":"%s","tested":"%s","stable":"%s","channel":"%s","pre":%s,"present":%s,"source":"%s","unit":"%s","path":"%s","active":%s,"uptodate":%s}' "$name" "$inst" "$tested" "$stable" "$channel" "$pre" "$present" "$source" "$unit" "$(cm_target "$name")" "$active" "$utd"
    done
    printf ']\n'
}

cm_verify() {
    local list=$1 name bin rc=0
    if [ -z "$list" ]; then list=$(cm_cores); fi
    for name in $list; do
        bin=$(cm_target "$name")
        if [ ! -f "$bin" ]; then
            echo "missing  $name  $bin"
            rc=1
        elif cm_probe "$name" "$bin" >/dev/null; then
            echo "ok       $name  $(cm_installed "$name")"
        else
            echo "broken   $name  $bin"
            rc=1
        fi
    done
    return $rc
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    case "$1" in
    list) cm_cores ;;
    status) cm_status ;;
    json) cm_json ;;
    latest) cm_latest "$2" ;;
    latest-pre) cm_latest_pre "$2" ;;  # watashi v12.2.82
    stable) cm_stable "$2" ;;
    channel) cm_channel "$2" ;;
    default) cm_default_version "$2" ;;
    installed) cm_installed "$2" ;;
    tested) cm_tested "$2" ;;
    install | upgrade | downgrade) cm_install "$2" "$3" ;;
    rollback) cm_rollback "$2" ;;
    prune)
        if [ -n "$2" ]; then
            cm_prune "$2"
        else
            for c in $(cm_cores); do cm_prune "$c"; done
        fi
        ;;
    verify) cm_verify "$2" ;;
    *)
        echo "usage: $0 {list|status|json|latest|latest-pre|stable|channel|default|installed|tested|install|upgrade|downgrade|rollback|prune|verify} [core] [version]"
        exit 1
        ;;
    esac
fi
