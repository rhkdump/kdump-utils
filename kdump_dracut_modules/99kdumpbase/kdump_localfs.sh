#!/bin/sh

. /lib/kdump-lib.sh
read_kdump_conf
set -x

# We have the root file system mounted under $NEWROOT, so copy 
# the vmcore there and call it a day
#
DATEDIR=`date +%d.%m.%y-%T`

mount -o remount,rw $NEWROOT/
mkdir -p $NEWROOT/$KDUMP_PATH/$DATEDIR
$CORE_COLLECTOR /proc/vmcore $NEWROOT/$KDUMP_PATH/$DATEDIR/vmcore
sync

do_default_action

