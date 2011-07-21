#!/bin/sh

set -x
# We have the root file system mounted under $NEWROOT, so copy 
# the vmcore there and call it a day
#
DATEDIR=`date +%d.%m.%y-%T`
mount -o remount,rw $NEWROOT/
mkdir -p $NEWROOT/var/crash/$DATEDIR
cp /proc/vmcore $NEWROOT/var/crash/$DATEDIR/vmcore
sync

# Once the copy is done, just reboot the system
reboot -f
