#!/bin/bash
# watashi v12.3.40dev: the old project name was taken out of this file (names, paths and links only)

if [[ "$VER" != "" ]];then
    set -- $VER  $@

fi

echo "$0 input params are $@"


if [[ " $@ " != *"--no-gui"* ]] &&  [[ "$0" == "bash" ]]; then
    echo "This script is deprecated! Please use the following command"
    echo ""
    echo "bash <(curl https://panel.watashi.cyou/$1)"
    echo ""
    exit 1
fi

echo "Downloading '$@'"

# watashi v12.3.40dev: a "v8" argument used to hand the server over to the
# installer of the project this one was forked from, a version years old.
# That branch is gone; a v8 tag is refused by the version check below.

# watashi v12.3.40dev: releases from before 12.3.40 keep their files under the
# project's old names, so the files this script fetches do not exist in them
# and their install would not know the folders of this one.
ws_tag_before_rename() {
    local v=${1#v}
    [ -n "$v" ] && [ "$v" != "12.3.40" ] &&
        [ "$(printf '%s\n%s\n' "$v" "12.3.40" | sort -V | head -n 1)" = "$v" ]
}


mkdir -p /tmp/watashi/
chmod 600 /tmp/watashi/
rm -rf /tmp/watashi/*


branch="${1:-release}"

if [[ "$branch" == v* ]]; then
    # If input starts with 'v', treat it as a tag
    if ws_tag_before_rename "$branch"; then
        echo "$branch is from before the project took the Watashi name and cannot be installed with this script." >&2
        echo "Nothing was changed." >&2
        exit 1
    fi
    base_url="https://raw.githubusercontent.com/mn-hacker/Watashi-Manager/refs/tags/$branch/"
elif [[ "$branch" == "beta" ]]; then
    # Fetch latest pre-release tag from GitHub API
    beta_tag=$(curl -sL "https://api.github.com/repos/mn-hacker/Watashi-Manager/releases" | grep -o '"tag_name": *"[^"]*b[^"]*"' | head -1 | cut -d'"' -f4)
    if [[ -n "$beta_tag" ]] && ws_tag_before_rename "$beta_tag"; then
        echo "The latest pre-release ($beta_tag) is from before the rename, using main"
        beta_tag=""
    fi
    if [[ -n "$beta_tag" ]]; then
        echo "Found latest pre-release: $beta_tag"
        base_url="https://raw.githubusercontent.com/mn-hacker/Watashi-Manager/refs/tags/$beta_tag/"
    else
        echo "No pre-release found, using main branch"
        base_url="https://raw.githubusercontent.com/mn-hacker/Watashi-Manager/refs/heads/main/"
    fi
elif [[ "$branch" == "dev" ]]; then
    # watashi dev-channel: use latest dev tag release zip (like beta), not a branch
    # (the repo has no dev branch; branch tarballs also lack submodules)
    dev_tag=$(curl -sL "https://api.github.com/repos/mn-hacker/Watashi-Manager/tags" | jq -r '([.[].name | select(contains("dev"))] | first) // empty' 2>/dev/null)
    if [[ -n "$dev_tag" ]] && ws_tag_before_rename "$dev_tag"; then
        echo "The latest dev release ($dev_tag) is from before the rename, using main"
        dev_tag=""
    fi
    if [[ -n "$dev_tag" ]]; then
        echo "Found latest dev release: $dev_tag"
        base_url="https://raw.githubusercontent.com/mn-hacker/Watashi-Manager/refs/tags/$dev_tag/"
    else
        echo "No dev release found yet, falling back to main"
        base_url="https://raw.githubusercontent.com/mn-hacker/Watashi-Manager/refs/heads/main/"
    fi
else
    # Otherwise, use main branch
    base_url="https://raw.githubusercontent.com/mn-hacker/Watashi-Manager/refs/heads/main/"
fi
# watashi v12.2.130i: the installer used to arrive alone. utils.sh then looked for
# the terminal skin in /opt (still empty on a bare server) and beside itself
# in /tmp/watashi (where nobody had put it), found nothing, and the whole
# first install was drawn in the plain old look. The skin comes along now.
# watashi v12.3.40dev: watashi_legacy.sh comes along too, the installer needs
# it to move a server off the old name before it touches anything. curl -f,
# because a missing file used to be saved as GitHub's "404: Not Found" page
# and then run as a script. WATASHI_BOOT_DIR takes the files from a folder on
# the disk instead (offline installs and tests).
WS_BOOT_FILES="common/watashi_installer.sh common/utils.sh common/watashi_tui.sh common/watashi_progress.py common/logo.ico common/watashi_legacy.sh"
for ws_file in $WS_BOOT_FILES; do
    if [ -n "$WATASHI_BOOT_DIR" ]; then
        cp -f "$WATASHI_BOOT_DIR/$ws_file" "/tmp/watashi/$(basename "$ws_file")" 2>/dev/null
    else
        curl -sfL -o "/tmp/watashi/$(basename "$ws_file")" "$base_url/$ws_file"
    fi
done
# the three the installer cannot start without
for ws_file in watashi_installer.sh utils.sh watashi_legacy.sh; do
    if [ ! -s "/tmp/watashi/$ws_file" ]; then
        echo "$ws_file could not be downloaded, nothing was installed"
        exit 1
    fi
done
if [ ! -s /tmp/watashi/watashi_tui.sh ]; then
    echo "note: the terminal skin could not be downloaded, the plain look will be used"
fi
chmod 700 /tmp/watashi/*

/tmp/watashi/watashi_installer.sh $@
