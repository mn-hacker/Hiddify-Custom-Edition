#!/bin/bash

if [[ "$VER" != "" ]];then
    set -- $VER  $@

fi

echo "$0 input params are $@"


if [[ " $@ " != *"--no-gui"* ]] &&  [[ "$0" == "bash" ]]; then
    echo "This script is deprecated! Please use the following command"
    echo ""
    echo "bash <(curl https://i.hiddify.com/$1)"
    echo ""
    exit 1
fi

echo "Downloading '$@'"

if [[ " $@ " == *" v8 "* ]]; then
    sudo bash -c "$(curl -sLfo- https://raw.githubusercontent.com/hiddify/hiddify-config/main/common/download_install.sh)"
    exit $?
fi


mkdir -p /tmp/hiddify/
chmod 600 /tmp/hiddify/
rm -rf /tmp/hiddify/*


branch="${1:-release}"

if [[ "$branch" == v* ]]; then
    # If input starts with 'v', treat it as a tag
    base_url="https://raw.githubusercontent.com/mn-hacker/Hiddify-Custom-Edition/refs/tags/$branch/"
elif [[ "$branch" == "beta" ]]; then
    # Fetch latest pre-release tag from GitHub API
    beta_tag=$(curl -sL "https://api.github.com/repos/mn-hacker/Hiddify-Custom-Edition/releases" | grep -o '"tag_name": *"[^"]*b[^"]*"' | head -1 | cut -d'"' -f4)
    if [[ -n "$beta_tag" ]]; then
        echo "Found latest pre-release: $beta_tag"
        base_url="https://raw.githubusercontent.com/mn-hacker/Hiddify-Custom-Edition/refs/tags/$beta_tag/"
    else
        echo "No pre-release found, using main branch"
        base_url="https://raw.githubusercontent.com/mn-hacker/Hiddify-Custom-Edition/refs/heads/main/"
    fi
elif [[ "$branch" == "dev" ]]; then
    # If input is 'dev', use dev branch
    base_url="https://raw.githubusercontent.com/mn-hacker/Hiddify-Custom-Edition/refs/heads/dev/"
else
    # Otherwise, use main branch
    base_url="https://raw.githubusercontent.com/mn-hacker/Hiddify-Custom-Edition/refs/heads/main/"
fi
curl -sL -o /tmp/hiddify/hiddify_installer.sh $base_url/common/hiddify_installer.sh
curl -sL -o /tmp/hiddify/utils.sh $base_url/common/utils.sh
chmod 700 /tmp/hiddify/*

/tmp/hiddify/hiddify_installer.sh $@
