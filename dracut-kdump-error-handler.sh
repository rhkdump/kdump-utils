#!/bin/sh

. /lib/kdump-lib-initramfs.sh

set -o pipefail
export PATH=$PATH:$KDUMP_SCRIPT_DIR

get_kdump_confs
do_default_action
do_final_action
