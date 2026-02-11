source /opt/hiddify-manager/common/package_manager.sh

echo "telegram proxy install.sh $*"
systemctl kill mtproxy.service >/dev/null 2>&1
systemctl disable mtproxy.service >/dev/null 2>&1

# sudo add-apt-repository -y ppa:longsleep/golang-backports
# sudo apt update
# apt install -y make golang

# wget -q --show-progress -c https://go.dev/dl/go1.19.linux-$pkg.tar.gz
# tar -xf go1.19.linux-amd64.tar.gz
# export PATH=$(pwd)/go/bin:$PATH

download_package mtproxygo mtg-linux.tar.gz
tar -xf mtg-linux.tar.gz || exit 1
# remove old dir if exists
rm -rf mtg-linux
# find the directory extracted
DIR=$(ls -d mtg-*/ 2>/dev/null || ls -d mtg*/ 2>/dev/null | head -n 1)
if [ -z "$DIR" ]; then
    echo "ERROR: Could not find extracted directory for mtg"
    ls -l
    exit 1
fi
mv "$DIR/mtg" mtg || { echo "ERROR: mtg binary not found in $DIR"; exit 2; }
set_installed_version mtproxygo
# export GOPATH=/opt/hiddify-manager/other/telegram/tgo/go/
# export GOCACHE=/opt/hiddify-manager/other/telegram/tgo/gocache/
# git clone https://github.com/9seconds/mtg/

# if [ ! -f mtg/mtg ];then
#     echo "error in installation of telegram"
#     cd mtg

#     make

# fi
