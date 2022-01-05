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
End
