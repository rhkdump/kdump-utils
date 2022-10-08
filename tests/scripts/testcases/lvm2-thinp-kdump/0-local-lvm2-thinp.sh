on_build() {
	TEST_DIR_PREFIX=/tmp/lvm_test.XXXXXX
	# clear TEST_DIRs if any
	rm -rf ${TEST_DIR_PREFIX%.*}.*
	TEST_IMG="$(mktemp -d $TEST_DIR_PREFIX)/test.img"

	img_inst_pkg "lvm2"
	img_inst $TESTDIR/scripts/testcases/lvm2-thinp-kdump/lvm.conf  /etc/lvm/
	dd if=/dev/zero of=$TEST_IMG bs=300M count=1
	# The test.img will be /dev/sdb
	img_add_qemu_cmd "-hdb $TEST_IMG"
}

on_test() {
	VG=vg00
	LV_THINPOOL=thinpool
	LV_VOLUME=thinlv
	VMCORE_PATH=var/crash

	local boot_count=$(get_test_boot_count)

	if [ $boot_count -eq 1 ]; then

		vgcreate $VG /dev/sdb
		# Create a small thinpool which is definitely not enough for
		# vmcore, then create a thin volume which is definitely enough
		# for vmcore, so we can make sure thinpool should be autoextend
		# during runtime.
		lvcreate -L 10M -T $VG/$LV_THINPOOL
		lvcreate -V 300M -T $VG/$LV_THINPOOL -n $LV_VOLUME
		mkfs.ext4 /dev/$VG/$LV_VOLUME
		mount /dev/$VG/$LV_VOLUME /mnt
		mkdir -p /mnt/$VMCORE_PATH

		cat << EOF > /etc/kdump.conf
ext4 /dev/$VG/$LV_VOLUME
path /$VMCORE_PATH
core_collector makedumpfile -l --message-level 7 -d 31
EOF
		kdumpctl start || test_failed "Failed to start kdump"

		sync

		echo 1 > /proc/sys/kernel/sysrq
		echo c > /proc/sysrq-trigger

	elif [ $boot_count -eq 2 ]; then
		mount /dev/$VG/$LV_VOLUME /mnt
		if has_valid_vmcore_dir /mnt/$VMCORE_PATH; then
			test_passed
		else
			test_failed "Vmcore missing"
		fi

		shutdown -h 0
	else
		test_failed "Unexpected reboot"
	fi
}
