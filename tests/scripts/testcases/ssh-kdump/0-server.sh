#!/usr/bin/env sh

# Executed before VM starts
on_build() {
	img_add_qemu_cmd "-nic socket,listen=:8010,mac=52:54:00:12:34:56"

	img_run_cmd "echo root:fedora | chpasswd"
	img_run_cmd 'sed -i "s/^.*PasswordAuthentication .*\$/PasswordAuthentication yes/"  /etc/ssh/sshd_config'
	img_run_cmd 'sed -i "s/^.*PermitRootLogin .*\$/PermitRootLogin yes/"  /etc/ssh/sshd_config'
	img_run_cmd "systemctl enable sshd"

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
}

# Executed when VM boots
on_test() {
	while true; do
		if has_valid_vmcore_dir /var/crash; then
			test_passed
		fi

		sleep 1
	done
}
