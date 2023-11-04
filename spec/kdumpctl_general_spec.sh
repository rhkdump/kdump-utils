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

	Describe "_get_dracut_arg"
		dracut_args='-o "foo bar baz" -t 1 --test="a b c" --omit bla'
		Parameters
			-o	--omit	2	"foo bar baz bla"
			-e	--empty	0	""
			-t	""	1	"1"
			""	--test	1	"a b c"
			""	""	0	""
		End
		It "should parse the dracut_args correctly"
			When call _get_dracut_arg "$1" "$2" "$dracut_args"
			The status should equal $3
			The output should equal "$4"
		End
	End

	Describe "is_dracut_mod_omitted()"
		KDUMP_CONFIG_FILE=$(mktemp -t kdump_conf.XXXXXXXXXX)
		cleanup() {
			rm -f "$kdump_conf"
		}
		AfterAll 'cleanup'

		Parameters:dynamic
			for opt in '-o ' '--omit ' '--omit='; do
				for val in \
					'foo' \
					'"foo"' \
					'"foo bar baz"' \
					'"bar foo baz"' \
					'"bar baz foo"'; do
					%data success foo "$opt$val"
					%data success foo "-a x $opt$val -i y"
					%data failure xyz "$opt$val"
					%data failure xyz "-a x $opt$val -i y"
				done
			done
			%data success foo "-o xxx -o foo"
			%data failure foo "-a x -i y"
		End
		It "shall return $1 for module $2 and dracut_args '$3'"
			echo "dracut_args $3" > $KDUMP_CONFIG_FILE
			parse_config
			When call is_dracut_mod_omitted $2
			The status should be $1
		End
	End

	Describe '_find_kernel_path_by_release()'
		# When the array length changes, the Parameters:dynamic should change as well
		kernel_paths=(/boot/vmlinuz-6.2.11-200.fc37.x86_64
		              /boot/vmlinuz-5.14.0-316.el9.aarch64+64k
		              /boot/vmlinuz-5.14.0-322.el9.aarch64
		              /boot/efi/36b54597c46383/6.4.0-0.rc0.20230427git6e98b09da931.5.fc39.aarch64/linux)

		kernels=(vmlinuz-6.2.11-200.fc37.x86_64
		         vmlinuz-5.14.0-316.el9.aarch64+64k
		         vmlinuz-5.14.0-322.el9.aarch64
		         6.4.0-0.rc0.20230427git6e98b09da931.5.fc39.aarch64)

		grubby() {
			for key in "${!kernel_paths[@]}"; do
				echo "kernel=\"${kernel_paths[$key]}\""
			done
		}

		Parameters:dynamic
			# Due to a bug [1] in shellspec, hardcode the loop number instead of using the
			# array length
			# [1] https://github.com/shellspec/shellspec/issues/259
			for key in {0..3}; do
				%data "${kernels[$key]}" "${kernel_paths[$key]}"
			done
		End

		It 'returns the kernel path for the given release'
			When call _find_kernel_path_by_release "$1"
			The output should equal "$2"
		End
	End

	Describe 'parse_config()'
		KDUMP_CONFIG_FILE=$(mktemp -t kdump_conf.XXXXXXXXXX)
		cleanup() {
			rm -f "$KDUMP_CONFIG_FILE"
		}
		AfterAll 'cleanup'

		It 'should not be happy with unkown option in kdump.conf'
			echo blabla > "$KDUMP_CONFIG_FILE"
			When call parse_config
			The status should be failure
			The stderr should include 'Invalid kdump config option blabla'
		End

		Parameters:value aarch64 ppc64le s390x x86_64

		It 'should be happy with the default kdump.conf'
			./gen-kdump-conf.sh "$1" > "$KDUMP_CONFIG_FILE"
			When call parse_config
			The status should be success
		End

	End

End
