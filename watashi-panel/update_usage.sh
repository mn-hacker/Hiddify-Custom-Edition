#!/bin/bash
# watashi v12.3.40dev: the old project name was taken out of this file (names, paths and links only)

cd $(dirname -- "$0")
source /opt/watashi-manager/common/utils.sh
NAME="update_usage"
function main() {
    echo "trying to update usage"
    
    
    watashi-http-api admin/update_user_usage/
    if [ "$?" != 0 ] && [ -z $(pgrep -f 'watashipanel update-usage') ]; then
        watashi-panel-cli "update-usage"
    fi
    

}

set_lock $NAME
main |& tee -a ../log/system/update_usage.log
remove_lock $NAME