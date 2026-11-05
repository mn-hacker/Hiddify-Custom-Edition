# watashi v12.3.40dev: the old project name was taken out of this file (names, paths and links only)
# bash download_wgcf.sh
source /opt/watashi-manager/common/package_manager.sh
install_package wireguard-tools
download_package wgcf wgcf
if [ "$?" == "0"  ] || ! is_installed ./wgcf; then
    chmod +x wgcf || exit 1
    set_installed_version wgcf
fi
