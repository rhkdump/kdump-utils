#!/bin/sh
#
# Kdump common functions
#

is_ssh_dump_target()
{
    grep -q "^ssh[[:blank:]].*@" /etc/kdump.conf
}

is_nfs_dump_target()
{
    grep -q "^nfs" /etc/kdump.conf
}

is_raw_dump_target()
{
    grep -q "^raw" /etc/kdump.conf
}
