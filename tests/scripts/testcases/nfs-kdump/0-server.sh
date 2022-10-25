#!/usr/bin/env sh

# Executed before VM starts
on_build() {
	img_inst_pkg "nfs-utils dnsmasq"

	img_run_cmd "mkdir -p /srv/nfs/var/crash"
	img_run_cmd "echo /srv/nfs 192.168.77.1/24\(rw,async,insecure,no_root_squash\) > /etc/exports"
	img_run_cmd "systemctl enable nfs-server"

	img_run_cmd "touch /etc/systemd/resolved.conf"
	img_run_cmd "echo DNSStubListener=no >> /etc/systemd/resolved.conf"

	img_run_cmd "echo interface=eth0 > /etc/dnsmasq.conf"
	img_run_cmd "echo dhcp-authoritative >> /etc/dnsmasq.conf"
	img_run_cmd "echo dhcp-range=192.168.77.50,192.168.77.100,255.255.255.0,12h >> /etc/dnsmasq.conf"
	img_run_cmd "systemctl enable dnsmasq"

	img_run_cmd 'echo [connection] > /etc/NetworkManager/system-connections/eth0.nmconnection'
	img_run_cmd 'echo type=ethernet >> /etc/NetworkManager/system-connections/eth0.nmconnection'
	img_run_cmd 'echo interface-name=eth0 >> /etc/NetworkManager/system-connections/eth0.nmconnection'
	img_run_cmd 'echo [ipv4] >> /etc/NetworkManager/system-connections/eth0.nmconnection'
	img_run_cmd 'echo address1=192.168.77.1/24 >> /etc/NetworkManager/system-connections/eth0.nmconnection'
	img_run_cmd 'echo method=manual >> /etc/NetworkManager/system-connections/eth0.nmconnection'
	img_run_cmd 'chmod 600 /etc/NetworkManager/system-connections/eth0.nmconnection'

	img_add_qemu_cmd "-nic socket,listen=:8010,mac=52:54:00:12:34:56"
}

# Executed when VM boots
on_test() {
	while true; do
		if has_valid_vmcore_dir /srv/nfs/var/crash; then
			# Wait a few seconds so client finish it's work to generate a full log
			sleep 5

			test_passed
		fi

		sleep 1
	done
}
