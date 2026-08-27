#!/bin/bash
cd $(dirname -- "$0")
source cert_utils.sh
# watashi v12.2.49: this path is a deliberate request from the panel, so it
# ignores the cooldown that protects the scheduled runs.
export WS_SSL_FORCE="${WS_SSL_FORCE:-1}"
#./lib/acme.sh --register-account -m my@example.com
get_cert $1
