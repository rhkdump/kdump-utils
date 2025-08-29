#!/bin/bash
Describe 'kdumpctl reset-crashkernel [--kernel] [--fadump]'
	Include ./kdumpctl
	kernel1=/boot/vmlinuz-5.15.6-100.fc34.x86_64
	kernel2=/boot/vmlinuz-5.14.14-200.fc34.x86_64
	kernel2_index1=1
	kernel2_index2=2
	ck=222M
	KDUMP_SPEC_TEST_RUN_DIR=$(mktemp -d /tmp/spec_test.XXXXXXXXXX)
	current_kernel=5.15.6-100.fc34.x86_64

	setup() {
		cp -r spec/support/boot_load_entries "$KDUMP_SPEC_TEST_RUN_DIR"
		cp spec/support/grub_env "$KDUMP_SPEC_TEST_RUN_DIR"/env_temp
	}

	cleanup() {
		rm -rf "$KDUMP_SPEC_TEST_RUN_DIR"
	}

	BeforeAll 'setup'
	AfterAll 'cleanup'

	# the boot loader entries are for a system without a boot partition, mock
	# mountpoint to let grubby know it
	Mock mountpoint
		exit 1
	End

	grubby() {
		# - --no-etc-grub-update, not update /etc/default/grub
		# - --bad-image-okay, don't check the validity of the image
		# - --env, specify custom grub2 environment block file to avoid modifying
		#   the default /boot/grub2/grubenv
		# - --bls-directory, specify custom BootLoaderSpec config files to avoid
		#   modifying the default /boot/loader/entries
		/usr/sbin/grubby --no-etc-grub-update --grub2 --bad-image-okay --env="$KDUMP_SPEC_TEST_RUN_DIR"/env_temp -b "$KDUMP_SPEC_TEST_RUN_DIR"/boot_load_entries "$@"
	}

	# The mocking breaks has_command. Mock it as well to fix the tests.
	has_command() {
		[[ "$1" == grubby ]]
	}

	Describe "Test the kdump dump mode "
		uname() {
			if [[ $1 == '-m' ]]; then
				echo -n x86_64
			elif [[ $1 == '-r' ]]; then
				echo -n "$current_kernel"
			fi
		}
		kdump_crashkernel=$(get_default_crashkernel kdump)
		Context "when --kernel not specified"
			grubby --args crashkernel="$ck" --update-kernel ALL
			Specify 'kdumpctl should warn the user that crashkernel has been udpated'
				When call reset_crashkernel
				The error should include "Updated crashkernel=$kdump_crashkernel"
			End

			Specify 'Current running kernel should have crashkernel updated'
				When call grubby --info "$kernel1"
				The line 3 of output should include crashkernel="$kdump_crashkernel"
				The line 3 of output should not include crashkernel="$ck"
			End

			Specify 'Other kernel still use the old crashkernel value'
				When call grubby --info "$kernel2"
				The line 3 of output should include crashkernel="$ck"
			End
		End

		Context "--kernel=ALL"
			grubby --args crashkernel="$ck" --update-kernel ALL
			Specify 'kdumpctl should warn the user that crashkernel has been udpated'
				When call reset_crashkernel --kernel=ALL
				The error should include "Updated crashkernel=$kdump_crashkernel for kernel=$kernel1"
				The error should include "Updated crashkernel=$kdump_crashkernel for kernel=$kernel2"
			End

			Specify 'kernel1 should have crashkernel updated'
				When call grubby --info "$kernel1"
				The line 3 of output should include crashkernel="$kdump_crashkernel"
			End

			Specify 'kernel2 should have crashkernel updated'
				When call grubby --info "$kernel2"
				The line 3 of output should include crashkernel="$kdump_crashkernel"
			End
		End

		Context "--kernel=/boot/one-kernel to update one specified kernel"
			grubby --args crashkernel="$ck" --update-kernel ALL
			Specify 'kdumpctl should warn the user that crashkernel has been updated'
				When call reset_crashkernel --kernel="$kernel1"
				The error should include "Updated crashkernel=$kdump_crashkernel for kernel=$kernel1"
			End

			Specify 'kernel1 should have crashkernel updated'
				When call grubby --info "$kernel1"
				The line 3 of output should include crashkernel="$kdump_crashkernel"
			End

			Specify 'kernel2 should have the old crashkernel'
				When call grubby --info "$kernel2"
				The line 3 of output should include crashkernel="$ck"
			End
		End

		Context "one kernel have 2 grub entries, and the first one is modified"
			grubby --args crashkernel="$kdump_crashkernel" --update-kernel ALL
			grubby --args crashkernel="$ck" --update-kernel "$kernel2_index1"
			Specify 'kdumpctl should warn the user that crashkernel has been updated'
				When call reset_crashkernel --kernel="$kernel2"
				The error should include "Updated crashkernel=$kdump_crashkernel for kernel=$kernel2, grub entry index=$kernel2_index1"
			End
			Specify 'kernel2 should not have old crashkernel ck'
				When call grubby --info "$kernel2"
				The line 3 of output should not include crashkernel="$ck"
			End
		End

		Context "one kernel have 2 grub entries, and the second one is modified"
			grubby --args crashkernel="$kdump_crashkernel" --update-kernel ALL
			grubby --args crashkernel="$ck" --update-kernel "$kernel2_index2"
			Specify 'kdumpctl should warn the user that crashkernel has been updated'
				When call reset_crashkernel --kernel="$kernel2"
				The error should include "Updated crashkernel=$kdump_crashkernel for kernel=$kernel2, grub entry index=$kernel2_index2"
			End

			Specify 'kernel2 should not have old crashkernel ck'
				When call grubby --info "$kernel2"
				The line 3 of output should not include crashkernel="$ck"
			End
		End
	End

	Describe "FADump" fadump
		uname() {
			if [[ $1 == '-m' ]]; then
				echo -n ppc64le
			elif [[ $1 == '-r' ]]; then
				echo -n "$current_kernel"
			fi
		}

		kdump_crashkernel=$(get_default_crashkernel kdump)
		fadump_crashkernel=$(get_default_crashkernel fadump)
		Context "when no --kernel specified"
			grubby --args crashkernel="$ck" --update-kernel ALL
			grubby --remove-args=fadump --update-kernel ALL
			Specify 'kdumpctl should warn the user that crashkernel has been udpated'
				When call reset_crashkernel
				The error should include "Updated crashkernel=$kdump_crashkernel"
			End

			Specify 'Current running kernel should have crashkernel updated'
				When call grubby --info "$kernel1"
				The line 3 of output should include crashkernel="$kdump_crashkernel"
			End

			Specify 'Other kernel still use the old crashkernel value'
				When call grubby --info "$kernel2"
				The line 3 of output should include crashkernel="$ck"
			End
		End

		Context "--kernel=ALL --fadump=on"
			grubby --args crashkernel="$ck" --update-kernel ALL
			Specify 'kdumpctl should warn the user that crashkernel has been udpated'
				When call reset_crashkernel --kernel=ALL --fadump=on
				The error should include "Updated fadump=on and updated crashkernel=$fadump_crashkernel for kernel=$kernel1"
				The error should include "Updated fadump=on and updated crashkernel=$fadump_crashkernel for kernel=$kernel2"
			End

			Specify 'kernel1 should have crashkernel updated'
				When call grubby --info "$kernel1"
				The line 3 of output should include crashkernel="$fadump_crashkernel"
			End

			Specify 'kernel2 should have crashkernel updated'
				When call get_grub_kernel_boot_parameter "$kernel2" crashkernel
				The output should equal "$fadump_crashkernel"
			End
		End

		Context "--kernel=/boot/one-kernel to update one specified kernel"
			grubby --args crashkernel="$ck" --update-kernel ALL
			grubby --args fadump=on --update-kernel "$kernel1"
			Specify 'kdumpctl should warn the user that crashkernel has been updated'
				When call reset_crashkernel --kernel="$kernel1"
				The error should include "Updated crashkernel=$fadump_crashkernel for kernel=$kernel1"
			End

			Specify 'kernel1 should have crashkernel updated'
				When call grubby --info "$kernel1"
				The line 3 of output should include crashkernel="$fadump_crashkernel"
			End

			Specify 'kernel2 should have the old crashkernel'
				When call get_grub_kernel_boot_parameter "$kernel2" crashkernel
				The output should equal "$ck"
			End
		End

		Context "multiple grub entries, and the 1st enabled fadump"
			grubby --args crashkernel="$kdump_crashkernel" --remove-args=fadump --update-kernel ALL
			grubby --args fadump=on --update-kernel "$kernel2_index1"
			Specify 'kdumpctl should warn the user that crashkernel has been updated'
				When call reset_crashkernel --kernel="$kernel2"
				The error should include "Updated crashkernel=$fadump_crashkernel for kernel=$kernel2, grub entry index=$kernel2_index1"
			End

			Specify 'kernel2 index 2 should have old crashkernel'
				When call grubby --info "$kernel2_index2"
				The line 3 of output should include crashkernel="$kdump_crashkernel"
			End

			Specify 'kdumpctl should warn the user that crashkernel has been updated'
				When call reset_crashkernel --kernel="$kernel2" --fadump=on
				The error should include "Updated fadump=on and updated crashkernel=$fadump_crashkernel for kernel=$kernel2, grub entry index=$kernel2_index2"
			End
		End

		Context "multiple grub entries, and the 2nd is enabled fadump"
			grubby --args crashkernel="$kdump_crashkernel" --remove-args=fadump --update-kernel ALL
			grubby --args fadump=on --update-kernel "$kernel2_index2"
			Specify 'kdumpctl should warn the user that crashkernel has been updated'
				When call reset_crashkernel --kernel="$kernel2"
				The error should include "Updated crashkernel=$fadump_crashkernel for kernel=$kernel2, grub entry index=$kernel2_index2"
			End

			Specify 'kernel2 index 1 should have old crashkernel'
				When call grubby --info "$kernel2_index1"
				The line 3 of output should include crashkernel="$kdump_crashkernel"
			End

			Specify 'kdumpctl should warn the user that crashkernel has been updated'
				When call reset_crashkernel --kernel="$kernel2" --fadump=on
				The error should include "Updated fadump=on and updated crashkernel=$fadump_crashkernel for kernel=$kernel2, grub entry index=$kernel2_index1"
			End
		End

		Context "multiple grub entries, and the 1st is enabled fadump with default crashkernel, --fadump=off"
			grubby --args crashkernel="$kdump_crashkernel" --remove-args=fadump --update-kernel "$kernel2_index2"
			grubby --args crashkernel="$fadump_crashkernel" --update-kernel "$kernel2_index1"
			Specify 'kdumpctl should warn the user that crashkernel has been updated'
				When call reset_crashkernel --kernel="$kernel2" --fadump=off
				The error should include "Removed fadump and updated crashkernel=$kdump_crashkernel for kernel=$kernel2, grub entry index=$kernel2_index1"
			End

			Specify 'kernel2 index 1 should not have fadump'
				When call grubby --info "$kernel2_index1"
				The line 3 of output should not include fadump=on
			End
		End

		Context "multiple grub entries, and the 2nd is enabled fadump with default crashkernel, --fadump=off"
			grubby --args crashkernel="$kdump_crashkernel" --remove-args=fadump --update-kernel "$kernel2_index1"
			grubby --args crashkernel="$fadump_crashkernel" --update-kernel "$kernel2_index2"
			Specify 'kdumpctl should warn the user that crashkernel has been updated'
				When call reset_crashkernel --kernel="$kernel2" --fadump=off
				The error should include "Removed fadump and updated crashkernel=$kdump_crashkernel for kernel=$kernel2, grub entry index=$kernel2_index2"
			End

			Specify 'kernel2 index 2 should not have fadump crashkernel'
				When call grubby --info "$kernel2_index2"
				The line 3 of output should not include fadump=on
			End
		End

		Context "Update all kernels but without --fadump specified"
			grubby --args crashkernel="$ck" --update-kernel ALL
			grubby --args fadump=on --update-kernel "$kernel1"
			Specify 'kdumpctl should warn the user that crashkernel has been updated'
				When call reset_crashkernel --kernel="$kernel1"
				The error should include "Updated crashkernel=$fadump_crashkernel for kernel=$kernel1"
			End

			Specify 'kernel1 should have crashkernel updated'
				When call get_grub_kernel_boot_parameter "$kernel1" crashkernel
				The output should equal "$fadump_crashkernel"
			End

			Specify 'kernel2 should have the old crashkernel'
				When call get_grub_kernel_boot_parameter "$kernel2" crashkernel
				The output should equal "$ck"
			End
		End

		Context 'Switch between fadump=on and fadump=nocma'
			grubby --args crashkernel="$ck" --update-kernel ALL
			grubby --args fadump=on --update-kernel ALL
			Specify 'fadump=on to fadump=nocma'
				When call reset_crashkernel --kernel=ALL --fadump=nocma
				The error should include "Updated fadump=nocma and updated crashkernel=$fadump_crashkernel for kernel=$kernel1"
				The error should include "Updated fadump=nocma and updated crashkernel=$fadump_crashkernel for kernel=$kernel2"
			End

			Specify 'kernel1 should have fadump=nocma in cmdline'
				When call get_grub_kernel_boot_parameter "$kernel1" fadump
				The output should equal nocma
			End

			Specify 'fadump=nocma to fadump=on'
				When call reset_crashkernel --kernel=ALL --fadump=on
				The error should include "Updated fadump=on for kernel=$kernel1"
			End

			Specify 'kernel2 should have fadump=on in cmdline'
				When call get_grub_kernel_boot_parameter "$kernel1" fadump
				The output should equal on
			End

		End

	End
End
