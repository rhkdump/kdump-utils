#!/bin/sh

# Test RPMs to be installed
TEST_RPMS=
for _rpm in $@; do
	if [[ ! -e $_rpm ]]; then
		perror_exit "'$_rpm' not found"
	else
		TEST_RPMS=$(realpath "$_rpm")
	fi
done

img_inst_pkg $TEST_RPMS
# Test script should start kdump manually to save time
img_run_cmd "systemctl disable kdump.service"
