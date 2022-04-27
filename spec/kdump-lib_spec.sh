#!/bin/bash
Describe 'kdump-lib'
	Include ./kdump-lib.sh

	Describe 'get_system_size()'

		PROC_IOMEM=$(mktemp -t spec_test_proc_iomem_file.XXXXXXXXXX)

		cleanup() {
			rm -rf "$PROC_IOMEM"
		}

		AfterAll 'cleanup'

		ONE_GIGABYTE='000000-3fffffff : System RAM'
		Parameters
			1
			3
		End

		It 'should return correct system RAM size'
			echo -n >"$PROC_IOMEM"
			for _ in $(seq 1 "$1"); do echo "$ONE_GIGABYTE" >>"$PROC_IOMEM"; done
			When call get_system_size
			The output should equal "$1"
		End

	End

	Describe 'get_recommend_size()'
		# Testing stragety:
		# 1. inclusive for the lower bound of the range of crashkernel
		# 2. exclusive for the upper bound of the range of crashkernel
		# 3. supports ranges not sorted in increasing order

		ck="4G-64G:256M,2G-4G:192M,64G-1T:512M,1T-:12345M"
		Parameters
			1 0M
			2 192M
			64 512M
			1024 12345M
			"$((64 * 1024))" 12345M
		End

		It 'should handle all cases correctly'
			When call get_recommend_size "$1" $ck
			The output should equal "$2"
		End
	End

End
