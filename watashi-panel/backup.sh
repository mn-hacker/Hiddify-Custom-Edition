#!/bin/bash
# watashi v12.3.40dev: the old project name was taken out of this file (names, paths and links only)
cd $( dirname -- "$0"; )
source /opt/watashi-manager/common/utils.sh

# watashi v12.2.130x: called with --if-due, the panel decides from backup_interval
# whether this hour is a backup hour. Without it, a backup is taken now.
if [[ " $@ " == *" --if-due "* ]]; then
    export WS_BACKUP_IF_DUE=1
fi

function main(){
    activate_python_venv
    watashi-panel-cli backup
}
main |& tee -a ../log/system/backup.log