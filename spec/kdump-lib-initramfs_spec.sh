#!/bin/bash
Describe 'kdump-lib-initramfs'
	Include ./kdump-lib-initramfs.sh

	Describe 'Test kdump_get_conf_val'
		KDUMP_CONFIG_FILE=/tmp/kdump_shellspec_test.conf
		kdump_config() {
			%text
			#|default shell
			#|nfs my.server.com:/export/tmp # trailing comment
			#|		failure_action	 shell
			#|dracut_args --omit-drivers "cfg80211 snd" --add-drivers "ext2 ext3"
			#|sshkey /root/.ssh/kdump_id_rsa
			#|ssh user@my.server.com
			#|core_collector "makedumpfile -l --message-level 7 -d 31"
		}
		kdump_config >$KDUMP_CONFIG_FILE
		Context 'Given different cases'
			# Test the following cases:
			#  - there is trailing comment
			#  - there is space before the parameter
			#  - complicate value for dracut_args
			#  - Given two parameters, retrive one parameter that has value specified
			#  - Given two parameters (in reverse order), retrive one parameter that has value specified
			#  - values are enclosed in quotes
			Parameters
				"#1" nfs my.server.com:/export/tmp
				"#2" ssh user@my.server.com
				"#3" failure_action shell
				"#4" dracut_args '--omit-drivers "cfg80211 snd" --add-drivers "ext2 ext3"'
				"#5" 'ssh\|aaa' user@my.server.com
				"#6" 'aaa\|ssh' user@my.server.com
				"#7" core_collector "makedumpfile -l --message-level 7 -d 31"
			End

			It 'should handle all cases correctly'
				When call kdump_get_conf_val "$2"
				The output should equal "$3"
			End
		End

	End

	Describe 'Test get_mntpoint_from_target'
		findmnt() {
			if [[ "$7" == 'eng.redhat.com:/srv/[nfs]' ]]; then
				if [[ "$8" == "-f" ]]; then
					printf '/mnt\n'
				else
					printf '/mnt %s\n' "$7"
				fi
			elif [[ "$7" == '[2620:52:0:a1:217:38ff:fe01:131]:/srv/[nfs]' ]]; then
				if [[ "$8" == "-f" ]]; then
					printf '/mnt\n'
				else
					printf '/mnt %s\n' "$7"
				fi
			elif [[ "$7" == '/dev/mapper/rhel[disk]' ]]; then
				if [[ "$8" == "-f" ]]; then
					printf '/\n'
				else
					printf '/ %s\n' "$7"
				fi
			elif [[ "$7" == '/dev/vda4' ]]; then
				if [[ "$8" == "-f" ]]; then
					printf '/var\n'
				else
					printf '/var %s[/ostree/deploy/default/var]\n/sysroot %s\n' "$7" "$7"
				fi
			fi
		}

		Context 'Given different cases'
			# Test the following cases:
			#  - IPv6 NFS target
			#  - IPv6 NFS target also contain '[' in the export
			#  - local dumping target that has '[' in the name
			#  - has bind mint
			Parameters
				'eng.redhat.com:/srv/[nfs]' '/mnt'
				'[2620:52:0:a1:217:38ff:fe01:131]:/srv/[nfs]' '/mnt'
				'/dev/mapper/rhel[disk]' '/'
				'/dev/vda4' '/sysroot'
			End

			It 'should handle all cases correctly'
				When call get_mntpoint_from_target "$1"
				The output should equal "$2"
			End
		End

	End

End
