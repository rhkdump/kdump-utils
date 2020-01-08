#!/bin/sh

# only wait if it's kdump kernel
if [ -f /etc/fadump.initramfs ] && [ ! -f /proc/device-tree/rtas/ibm,kernel-dump ]; then
    exit 0
fi

. /lib/dracut-lib.sh
. /lib/kdump-lib-initramfs.sh

# For SSH/NFS target, need to wait for the network to setup
if is_nfs_dump_target; then
    get_host_ip
    exit $?
fi

if is_ssh_dump_target; then
    get_host_ip
    exit $?
fi

# No need to wait for dump target
exit 0
