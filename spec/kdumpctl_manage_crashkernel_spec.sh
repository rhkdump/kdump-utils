#!/bin/bash

Describe 'Management of the kernel crashkernel parameter.'
	Include ./kdumpctl
	kernel1=/boot/vmlinuz-5.15.6-100.fc34.x86_64
	kernel2=/boot/vmlinuz-5.14.14-200.fc34.x86_64
	old_ck=1G-4G:162M,4G-64G:256M,64G-:512M
	new_ck=1G-4G:196M,4G-64G:256M,64G-:512M
	KDUMP_SPEC_TEST_RUN_DIR=$(mktemp -u /tmp/spec_test.XXXXXXXXXX)
	GRUB_CFG="$KDUMP_SPEC_TEST_RUN_DIR/grub.cfg"

	uname() {
		if [[ $1 == '-m' ]]; then
			echo -n x86_64
		elif [[ $1 == '-r' ]]; then
			echo -n $current_kernel
		fi
	}

	# dinfo is a bit complex for unit tets, simply mock it
	dinfo() {
		echo "$1"
	}

	kdump_get_arch_recommend_crashkernel() {
		echo -n "$new_ck"
	}

	setup() {
		mkdir -p "$KDUMP_SPEC_TEST_RUN_DIR"
		cp -r spec/support/boot_load_entries "$KDUMP_SPEC_TEST_RUN_DIR"
		cp spec/support/grub_env "$KDUMP_SPEC_TEST_RUN_DIR"/env_temp
		touch "$GRUB_CFG"

		grubby --args crashkernel=$old_ck --update-kernel=$kernel1
		grubby --args crashkernel=$new_ck --update-kernel=$kernel2
		grubby --remove-args fadump --update-kernel=ALL

	}

	cleanup() {
		rm -rf "$KDUMP_SPEC_TEST_RUN_DIR"
	}

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
		/usr/sbin/grubby --no-etc-grub-update --grub2 --config-file="$GRUB_CFG" --bad-image-okay --env="$KDUMP_SPEC_TEST_RUN_DIR"/env_temp -b "$KDUMP_SPEC_TEST_RUN_DIR"/boot_load_entries "$@"
	}

	# The mocking breaks has_command. Mock it as well to fix the tests.
	has_command() {
		[[ "$1" == grubby ]]
	}

	Describe "When kexec-tools have its default crashkernel updated, "

		Context "if kexec-tools is updated alone, "
			BeforeAll 'setup'
			AfterAll 'cleanup'
			Specify 'reset_crashkernel_after_update should report updated kernels and note that auto_reset_crashkernel=yes'
				When call reset_crashkernel_after_update
				The output should include "For kernel=$kernel1, crashkernel=$new_ck now."
				The output should not include "For kernel=$kernel2, crashkernel=$new_ck now."
				# A hint on how to turn off auto update of crashkernel
				The output should include "auto_reset_crashkernel=no"
			End

			Specify 'kernel1 should have crashkernel updated'
				When call grubby --info $kernel1
				The line 3 of output should include crashkernel="$new_ck"
			End

			Specify 'kernel2 should also have crashkernel updated'
				When call grubby --info $kernel2
				The line 3 of output should include crashkernel="$new_ck"
			End

		End

		Context "If kernel package is installed alone, "
			BeforeAll 'setup'
			AfterAll 'cleanup'
			# BeforeAll somehow doesn't work as expected, manually call setup to bypass this issue.
			setup
			new_kernel_ver=new_kernel
			new_kernel=/boot/vmlinuz-$new_kernel_ver
			grubby --add-kernel=$new_kernel --initrd=/boot/initramfs-$new_kernel_ver.img --title=$new_kernel_ver

			Specify 'reset_crashkernel_for_installed_kernel should report the new kernel has its crashkernel updated'
				When call reset_crashkernel_for_installed_kernel $new_kernel_ver
				The output should include "crashkernel=$new_ck"
			End

			Specify 'the new kernel should have crashkernel updated'
				When call grubby --info $new_kernel
				The output should include crashkernel="$new_ck"
			End

			Specify 'kernel1 keeps its crashkernel value'
				When call grubby --info $kernel1
				The output should include crashkernel="$old_ck"
			End

		End

	End
End
