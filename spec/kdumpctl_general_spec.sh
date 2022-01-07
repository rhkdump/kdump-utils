#!/bin/bash
Describe 'kdumpctl'
	Include ./kdumpctl

	Describe 'get_grub_kernel_boot_parameter()'
		grubby() {
			%text
			#|index=1
			#|kernel="/boot/vmlinuz-5.14.14-200.fc34.x86_64"
			#|args="crashkernel=11M nvidia-drm.modeset=1 crashkernel=100M ro rhgb quiet crcrashkernel=200M crashkernel=32T-64T:128G,64T-102400T:180G fadump=on"
			#|root="UUID=45fdf703-3966-401b-b8f7-cf056affd2b0"
		}
		DUMMY_PARAM=/boot/vmlinuz

		Context "when given a kernel parameter in different positions"
			# Test the following cases:
			#  - the kernel parameter in the end
			#  - the kernel parameter in the first
			#  - the kernel parameter is crashkernel (suffix of crcrashkernel)
			#  - the kernel parameter that does not exist
			#  - the kernel parameter doesn't have a value
			Parameters
				# parameter          answer
				fadump               on
				nvidia-drm.modeset   1
				crashkernel          32T-64T:128G,64T-102400T:180G
				aaaa                 ""
				ro                   ""
			End

			It 'should retrieve the value succesfully'
				When call get_grub_kernel_boot_parameter "$DUMMY_PARAM" "$2"
				The output should equal "$3"
			End
		End

		It 'should retrive the last value if multiple <parameter=value> entries exist'
			When call get_grub_kernel_boot_parameter "$DUMMY_PARAM" crashkernel
			The output should equal '32T-64T:128G,64T-102400T:180G'
		End

		It 'should fail when called with kernel_path=ALL'
			When call get_grub_kernel_boot_parameter ALL ro
			The status should be failure
			The error should include "kernel_path=ALL invalid"
		End
	End

	Describe 'get_dump_mode_by_fadump_val()'

		Context 'when given valid fadump values'
			Parameters
				"#1" on fadump
				"#2" nocma fadump
				"#3" "" kdump
				"#4" off kdump
			End
			It "should return the dump mode correctly"
				When call get_dump_mode_by_fadump_val "$2"
				The output should equal "$3"
				The status should be success
			End
		End

		It 'should complain given invalid fadump value'
			When call get_dump_mode_by_fadump_val /boot/vmlinuz
			The status should be failure
			The error should include 'invalid fadump'
		End

	End

	Describe "read_proc_environ_var()"
		environ_test_file=$(mktemp -t spec_test_environ_test_file.XXXXXXXXXX)
		cleanup() {
			rm -rf "$environ_test_file"
		}
		AfterAll 'cleanup'
		echo -ne "container=bwrap-osbuild\x00SSH_AUTH_SOCK=/tmp/ssh-XXXXXXEbw33A/agent.1794\x00SSH_AGENT_PID=1929\x00env=test_env" >"$environ_test_file"
		Parameters
			container bwrap-osbuild
			SSH_AUTH_SOCK /tmp/ssh-XXXXXXEbw33A/agent.1794
			env test_env
			not_exist ""
		End
		It 'should read the environ variable value as expected'
			When call read_proc_environ_var "$1" "$environ_test_file"
			The output should equal "$2"
			The status should be success
		End
	End

	Describe "_is_osbuild()"
		environ_test_file=$(mktemp -t spec_test_environ_test_file.XXXXXXXXXX)
		# shellcheck disable=SC2034
		# override the _OSBUILD_ENVIRON_PATH variable
		_OSBUILD_ENVIRON_PATH="$environ_test_file"
		Parameters
			'container=bwrap-osbuild' success
			'' failure
		End
		It 'should be able to tell if it is the osbuild environment'
			echo -ne "$1" >"$environ_test_file"
			When call _is_osbuild
			The status should be "$2"
			The stderr should equal ""
		End
	End

	Describe '_update_kernel_arg_in_grub_etc_default()'
		GRUB_ETC_DEFAULT=/tmp/default_grub

		cleanup() {
			rm -rf "$GRUB_ETC_DEFAULT"
		}
		AfterAll 'cleanup'

		Context 'when the given parameter is in different positions'
			Parameters
				"crashkernel=222M fadump=on rhgb quiet" crashkernel 333M
				" fadump=on crashkernel=222M rhgb quiet" crashkernel 333M
				"fadump=on rhgb quiet crashkernel=222M" crashkernel 333M
				"fadump=on rhgb quiet" crashkernel 333M
				"fadump=on foo=bar1 rhgb quiet" foo bar2
			End

			It 'should update the kernel parameter correctly'
				echo 'GRUB_CMDLINE_LINUX="'"$1"'"' >$GRUB_ETC_DEFAULT
				When call _update_kernel_arg_in_grub_etc_default "$2" "$3"
				# the updated kernel parameter should appear in the end
				The contents of file $GRUB_ETC_DEFAULT should include "$2=$3\""
			End
		End

		It 'should only update the given parameter and not update the parameter that has the given parameter as suffix'
			echo 'GRUB_CMDLINE_LINUX="fadump=on rhgb quiet ckcrashkernel=222M"' >$GRUB_ETC_DEFAULT
			_ck_val=1G-4G:192M,4G-64G:256M,64G-102400T:512M
			When call _update_kernel_arg_in_grub_etc_default crashkernel "$_ck_val"
			The contents of file $GRUB_ETC_DEFAULT should include "crashkernel=$_ck_val\""
			The contents of file $GRUB_ETC_DEFAULT should include "ckcrashkernel=222M"
		End

		It 'should be able to handle the cases of there are multiple crashkernel entries'
			echo 'GRUB_CMDLINE_LINUX="fadump=on rhgb quiet crashkernel=101M crashkernel=222M"' >$GRUB_ETC_DEFAULT
			_ck_val=1G-4G:192M,4G-64G:256M,64G-102400T:512M
			When call _update_kernel_arg_in_grub_etc_default crashkernel "$_ck_val"
			The contents of file $GRUB_ETC_DEFAULT should include "crashkernel=$_ck_val\""
			The contents of file $GRUB_ETC_DEFAULT should not include "crashkernel=222M"
		End

		Context 'when it removes a kernel parameter'

			It 'should remove all values for given arg'
				echo 'GRUB_CMDLINE_LINUX="crashkernel=33M crashkernel=11M fadump=on crashkernel=222M"' >$GRUB_ETC_DEFAULT
				When call _update_kernel_arg_in_grub_etc_default crashkernel
				The contents of file $GRUB_ETC_DEFAULT should equal 'GRUB_CMDLINE_LINUX="fadump=on"'
			End

			It 'should not remove args that have the given arg as suffix'
				echo 'GRUB_CMDLINE_LINUX="ckcrashkernel=33M crashkernel=11M ckcrashkernel=222M"' >$GRUB_ETC_DEFAULT
				When call _update_kernel_arg_in_grub_etc_default crashkernel
				The contents of file $GRUB_ETC_DEFAULT should equal 'GRUB_CMDLINE_LINUX="ckcrashkernel=33M ckcrashkernel=222M"'
			End
		End

	End

	Describe '_read_kernel_arg_in_grub_etc_default()'
		GRUB_ETC_DEFAULT=/tmp/default_grub
		It 'should read the value for given arg'
			echo 'GRUB_CMDLINE_LINUX="crashkernel=33M crashkernel=11M ckcrashkernel=222M"' >$GRUB_ETC_DEFAULT
			When call _read_kernel_arg_in_grub_etc_default crashkernel
			 The output should equal '11M'
		End
	End

	Describe 'parse_config()'
		bad_kdump_conf=$(mktemp -t bad_kdump_conf.XXXXXXXXXX)
		cleanup() {
			rm -f "$bad_kdump_conf"
		}
		AfterAll 'cleanup'

		It 'should not be happy with unkown option in kdump.conf'
			KDUMP_CONFIG_FILE="$bad_kdump_conf"
			echo blabla > "$bad_kdump_conf"
			When call parse_config
			The status should be failure
			The stderr should include 'Invalid kdump config option blabla'
		End

		It 'should be happy with the default kdump.conf'
		 # shellcheck disable=SC2034
			# override the KDUMP_CONFIG_FILE variable
			KDUMP_CONFIG_FILE=./kdump.conf
			When call parse_config
			The status should be success
		End

	End

End
