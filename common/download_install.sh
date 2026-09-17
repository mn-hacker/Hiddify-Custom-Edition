#!/bin/sh
if [ "$(id -u)" -ne 0 ]; then
    echo 'This script must be run by root' >&2
    exit 1
fi

checkOS() {
    # List of supported distributions
    #supported_distros=("Ubuntu" "Debian" "Fedora" "CentOS" "Arch")
    supported_distros=("Ubuntu")
    # Get the distribution name and version
    if [[ -f "/etc/os-release" ]]; then
        source "/etc/os-release"
        distro_name=$NAME
        distro_version=$VERSION_ID
    else
        echo "Unable to determine distribution."
        exit 1
    fi
    # Check if the distribution is supported
    if [[ " ${supported_distros[@]} " =~ " ${distro_name} " ]]; then
        echo "Your Linux distribution is ${distro_name} ${distro_version}"
        : #no-op command
    else
        # Print error message in red
        echo -e "\e[31mYour Linux distribution (${distro_name} ${distro_version}) is not currently supported.\e[0m"
        exit 1
    fi
    
    # This script only works on Ubuntu 22 and above
    if [ "$(uname)" == "Linux" ]; then
        version_info=$(lsb_release -rs | cut -d '.' -f 1)
        # Check if it's Ubuntu and version is below 22
        if [ "$(lsb_release -is)" == "Ubuntu" ] && [ "$version_info" -lt 22 ]; then
            echo "This script only works on Ubuntu 22 and above"
            exit
        fi
    fi
}
checkOS

# TODO: this commands are declared in hiddify-panel/install.sh, we don't need them here?!
#localectl set-locale LANG=C.UTF-8 >/dev/null 2>&1
#su hiddify-panel -c update-locale LANG=C.UTF-8 >/dev/null 2>&1

export DEBIAN_FRONTEND=noninteractive
export USE_VENV=true

echo "we are going to download needed files:)"
# watashi v12.2.130g: a bare server used to be handed the upstream project.
# The repository, the folder and the panel all come from us now.
GITHUB_REPOSITORY=hiddify-manager
GITHUB_USER=mn-hacker
GITHUB_PROJECT=Hiddify-Custom-Edition
GITHUB_BRANCH_OR_TAG=main
INSTALL_DIR=/opt/hiddify-manager

# if [ ! -d "/opt/$GITHUB_REPOSITORY" ];then
apt update
#apt upgrade -y
#apt -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" upgrade

apt install -y curl unzip
mkdir -p $INSTALL_DIR
cd $INSTALL_DIR
# watashi v12.2.130g: our newest release, not a version frozen years ago
curl -fL -o $GITHUB_REPOSITORY.zip https://github.com/$GITHUB_USER/$GITHUB_PROJECT/releases/latest/download/$GITHUB_REPOSITORY.zip
if [ ! -s $GITHUB_REPOSITORY.zip ]; then
    echo "the manager could not be downloaded, nothing was installed"
    exit 1
fi
unzip -o $GITHUB_REPOSITORY.zip > /dev/null
rm $GITHUB_REPOSITORY.zip
# a release asset may hold one top folder; the files belong here
if [ ! -f install.sh ]; then
    inner=$(find . -maxdepth 2 -name install.sh -printf "%h\n" 2>/dev/null | head -n 1)
    if [ -n "$inner" ] && [ "$inner" != "." ]; then
        cp -a "$inner"/. . && rm -rf "$inner"
    fi
fi
if [ ! -f install.sh ]; then
    echo "the downloaded manager has no install.sh, nothing was installed"
    exit 1
fi
rm -f xray/configs/*.json
rm -f singbox/configs/*.json
source $INSTALL_DIR/common/utils.sh
install_python
install_pypi_package pip==24.0
# watashi v12.2.130g: the panel that ships with this manager, never PyPI
ws_install_panel_from_source
bash install.sh --no-gui
# exit 0
# fi

sed -i "s|/opt/$GITHUB_REPOSITORY/menu.sh||g" ~/.bashrc
sed -i "s|cd /opt/$GITHUB_REPOSITORY/||g" ~/.bashrc
echo "/opt/$GITHUB_REPOSITORY/menu.sh" >>~/.bashrc
echo "cd /opt/$GITHUB_REPOSITORY/" >>~/.bashrc
if [ "$CREATE_EASYSETUP_LINK" == "true" ];then
    cd /opt/$GITHUB_REPOSITORY/hiddify-panel
    hiddify-panel-cli set-setting --key create_easysetup_link --val True
fi

hiddify-panel-cli set-setting --key auto_update --val False

read -p "Press any key to go  to menu" -n 1 key
cd /opt/$GITHUB_REPOSITORY
bash menu.sh
