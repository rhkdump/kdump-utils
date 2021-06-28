#!/bin/sh
export PATH=/usr/bin:/usr/sbin
export SYSTEMD_IN_INITRD=lenient

[ -e /proc/mounts ] ||
	(mkdir -p /proc && mount -t proc -o nosuid,noexec,nodev proc /proc)

grep -q '^sysfs /sys sysfs' /proc/mounts ||
	(mkdir -p /sys && mount -t sysfs -o nosuid,noexec,nodev sysfs /sys)

grep -q '^none / ' /proc/mounts || grep -q '^rootfs / ' /proc/mounts && ROOTFS_IS_RAMFS=1

if [ -f /proc/device-tree/rtas/ibm,kernel-dump ] || [ -f /proc/device-tree/ibm,opal/dump/mpipl-boot ]; then
	mkdir /newroot
	mount -t ramfs ramfs /newroot

	if [ $ROOTFS_IS_RAMFS ]; then
		for FILE in $(ls -A /fadumproot/); do
			mv /fadumproot/$FILE /newroot/
		done
		exec switch_root /newroot /init
	else
		mkdir /newroot/sys /newroot/proc /newroot/dev /newroot/run /newroot/oldroot

		grep -q '^devtmpfs /dev devtmpfs' /proc/mounts && mount --move /dev /newroot/dev
		grep -q '^tmpfs /run tmpfs' /proc/mounts && mount --move /run /newroot/run
		mount --move /sys /newroot/sys
		mount --move /proc /newroot/proc

		cp --reflink=auto --sparse=auto --preserve=mode,timestamps,links -dfr /fadumproot/. /newroot/
		cd /newroot && pivot_root . oldroot

		loop=1
		while [ $loop ]; do
			unset loop
			while read -r _ mp _; do
				case $mp in
				/oldroot/*) umount -d "$mp" && loop=1 ;;
				esac
			done </proc/mounts
		done
		umount -d -l oldroot

		exec /init
	fi
else
	exec /init.dracut
fi
