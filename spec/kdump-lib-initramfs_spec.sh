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
		}
		kdump_config >$KDUMP_CONFIG_FILE
		Context 'Given different cases'
			# Test the following cases:
			#  - there is trailing comment
			#  - there is space before the parameter
			#  - complicate value for dracut_args
			#  - Given two parameters, retrive one parameter that has value specified
			#  - Given two parameters (in reverse order), retrive one parameter that has value specified
			Parameters
				"#1" nfs my.server.com:/export/tmp
				"#2" ssh user@my.server.com
				"#3" failure_action shell
				"#4" dracut_args '--omit-drivers "cfg80211 snd" --add-drivers "ext2 ext3"'
				"#5" 'ssh\|aaa' user@my.server.com
				"#6" 'aaa\|ssh' user@my.server.com
			End

			It 'should handle all cases correctly'
				When call kdump_get_conf_val "$2"
				The output should equal "$3"
			End
		End

	End

End
