#!/bin/sh
#
# The code in this file will be used in initramfs environment, bash may
# not be the default shell. Any code added must be POSIX compliant.

DEFAULT_PATH="/var/crash/"
DEFAULT_SSHKEY="/root/.ssh/kdump_id_rsa"
KDUMP_CONFIG_FILE="/etc/kdump.conf"
FENCE_KDUMP_CONFIG_FILE="/etc/sysconfig/fence_kdump"
FENCE_KDUMP_SEND="/usr/libexec/fence_kdump_send"

# Read kdump config in well formated style
kdump_read_conf()
{
	# Following steps are applied in order: strip trailing comment, strip trailing space,
	# strip heading space, match non-empty line, remove duplicated spaces between conf name and value
	[ -f "$KDUMP_CONFIG_FILE" ] && sed -n -e "s/#.*//;s/\s*$//;s/^\s*//;s/\(\S\+\)\s*\(.*\)/\1 \2/p" $KDUMP_CONFIG_FILE
}

# Retrieves config value defined in kdump.conf
# $1: config name, sed regexp compatible
kdump_get_conf_val()
{
	# For lines matching "^\s*$1\s+", remove matched part (config name including space),
	# remove tailing comment, space, then store in hold space. Print out the hold buffer on last line.
	[ -f "$KDUMP_CONFIG_FILE" ] &&
		sed -n -e "/^\s*\($1\)\s\+/{s/^\s*\($1\)\s\+//;s/#.*//;s/\s*$//;h};\${x;p}" $KDUMP_CONFIG_FILE
}

is_mounted()
{
	findmnt -k -n "$1" > /dev/null 2>&1
}

# $1: info type
# $2: mount source type
# $3: mount source
# $4: extra args
get_mount_info()
{
	__kdump_mnt=$(findmnt -k -n -r -o "$1" "--$2" "$3" $4)

	[ -z "$__kdump_mnt" ] && [ -e "/etc/fstab" ] && __kdump_mnt=$(findmnt -s -n -r -o "$1" "--$2" "$3" $4)

	echo "$__kdump_mnt"
}

is_ipv6_address()
{
	echo "$1" | grep -q ":"
}

is_fs_type_nfs()
{
	[ "$1" = "nfs" ] || [ "$1" = "nfs4" ]
}

# If $1 contains dracut_args "--mount", return <filesystem type>
get_dracut_args_fstype()
{
	echo $1 | grep "\-\-mount" | sed "s/.*--mount .\(.*\)/\1/" | cut -d' ' -f3
}

# If $1 contains dracut_args "--mount", return <device>
get_dracut_args_target()
{
	echo $1 | grep "\-\-mount" | sed "s/.*--mount .\(.*\)/\1/" | cut -d' ' -f1
}

get_save_path()
{
	__kdump_path=$(kdump_get_conf_val path)
	[ -z "$__kdump_path" ] && __kdump_path=$DEFAULT_PATH

	# strip the duplicated "/"
	echo "$__kdump_path" | tr -s /
}

get_root_fs_device()
{
	findmnt -k -f -n -o SOURCE /
}

# Return the current underlying device of a path, ignore bind mounts
get_target_from_path()
{
	__kdump_target=$(df "$1" 2> /dev/null | tail -1 | awk '{print $1}')
	[ "$__kdump_target" = "/dev/root" ] && [ ! -e /dev/root ] && __kdump_target=$(get_root_fs_device)
	echo "$__kdump_target"
}

get_fs_type_from_target()
{
	get_mount_info FSTYPE source "$1" -f
}

get_mntpoint_from_target()
{
	# --source is applied to ensure non-bind mount is returned
	get_mount_info TARGET source "$1" -f
}

is_ssh_dump_target()
{
	kdump_get_conf_val ssh | grep -q @
}

is_raw_dump_target()
{
	[ -n "$(kdump_get_conf_val raw)" ]
}

is_nfs_dump_target()
{
	if [ -n "$(kdump_get_conf_val nfs)" ]; then
		return 0
	fi

	if is_fs_type_nfs "$(get_dracut_args_fstype "$(kdump_get_conf_val dracut_args)")"; then
		return 0
	fi

	if is_fs_type_nfs "$(get_fs_type_from_target "$(get_target_from_path "$(get_save_path)")")"; then
		return 0
	fi

	return 1
}

is_fs_dump_target()
{
	[ -n "$(kdump_get_conf_val "ext[234]\|xfs\|btrfs\|minix")" ]
}
