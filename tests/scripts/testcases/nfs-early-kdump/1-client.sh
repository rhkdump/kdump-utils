# Executed before VM starts
on_build() {
	img_inst_pkg "nfs-utils"
	img_add_qemu_cmd "-nic socket,connect=127.0.0.1:8010,mac=52:54:00:12:34:57"
}

on_test() {
	local boot_count=$(get_test_boot_count)
	local nfs_server=192.168.77.1
	local earlykdump_path="/usr/lib/dracut/modules.d/99earlykdump/early-kdump.sh"
	local tmp_file="/tmp/.tmp-file"

	if [[ ! -f $earlykdump_path ]]; then
		test_failed "early-kdump.sh not exist!"
	fi

	if [ $boot_count -eq 1 ]; then
		cat << EOF > /etc/kdump.conf
nfs $nfs_server:/srv/nfs
core_collector makedumpfile -l --message-level 7 -d 31
final_action poweroff
EOF

		while ! ping -c 1 $nfs_server -W 1; do
			sleep 1
		done

		kdumpctl start \
			|| test_failed "Failed to start kdump"
		grubby --update-kernel=ALL --args=rd.earlykdump

		cat << EOF > $tmp_file
echo 1 > /proc/sys/kernel/sysrq
echo c > /proc/sysrq-trigger
EOF
		sed -i "/early_kdump_load$/r $tmp_file" $earlykdump_path
		dracut -f --add earlykdump
		kdumpctl restart \
			|| test_failed "Failed to start earlykdump"

		sync
		reboot
	else
		test_failed "Unexpected reboot"
	fi
}
