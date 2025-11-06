#!/bin/sh
#
# The code in this file will be used in initramfs environment, bash may
# not be the default shell. Any code added must be POSIX compliant.

DEFAULT_PATH="/var/crash/"
# shellcheck disable=SC2034
DEFAULT_SSHKEY="/root/.ssh/kdump_id_rsa"
KDUMP_CONFIG_FILE="/etc/kdump.conf"
# shellcheck disable=SC2034
FENCE_KDUMP_SEND="/usr/libexec/fence_kdump_send"
# shellcheck disable=SC2034
LVM_CONF="/etc/lvm/lvm.conf"
# shellcheck disable=SC2034
LUKS_CONFIGFS=/sys/kernel/config/crash_dm_crypt_keys
# shellcheck disable=SC2034
LUKS_KEY_PRFIX="kdump-cryptsetup:vk-"

# Read kdump config in well formated style
kdump_read_conf()
{
	kdump_get_conf_val ""
}

# Retrieves config value defined in kdump.conf
# $1: config name, if empty print full config
kdump_get_conf_val()
{
	_to_find="$1"
	_found=""

	[ -f "$KDUMP_CONFIG_FILE" ] || return
	while read -r _line; do
		_line="$(echo "$_line" | tr -s "[:blank:]" " ")"
		case "$_line" in
		"" | \#*)
			continue
			;;
		*\#*)
			_line="${_line%%\#*}"
			_line="${_line% }"
			;;
		esac

		_opt=${_line%% *}
		_val=${_line#* }

		case "$_val" in
		\"*\")
			# Remove quotes
			_val="${_val#\"}"
			_val="${_val%\"}"
			;;
		esac

		if [ -z "$_to_find" ]; then
			echo "$_opt $_val"
		elif echo "$_opt" | grep -q -E "^($_to_find)$"; then
			# make sure to only return the last match to mirror the
			# old behavior
			_found="$_val"
		fi
	done < "$KDUMP_CONFIG_FILE"
	[ -n "$_found" ] && echo "$_found"

	# make sure we return 0 even when a option isn't set
	return 0
}

is_mounted()
{
	[ -n "$1" ] && findmnt -k -n "$1" > /dev/null 2>&1
}

# $1: info type
# $2: mount source type
# $3: mount source
# $4: extra args
# shellcheck disable=SC2086 # $4 means extra args which nees to word-splitted
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

is_fs_type_virtiofs()
{
	[ "$1" = "virtiofs" ]
}

# If $1 contains dracut_args "--mount", return <filesystem type>
get_dracut_args_fstype()
{
	echo "$1" | sed -n "s/.*--mount .\(.*\)/\1/p" | cut -d' ' -f3
}

# If $1 contains dracut_args "--mount", return <device>
get_dracut_args_target()
{
	echo "$1" | sed -n "s/.*--mount .\(.*\)/\1/p" | cut -d' ' -f1
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
	_subvol="$2"
	if [ -z "$_subvol" ]; then
		# get the first TARGET when SOURCE doesn't end with ].
		# In most cases, a SOURCE ends with ] when fsroot or subvol exists.
		_mntpoint=$(get_mount_info TARGET,SOURCE source "$1" | grep -v "\]$" | awk 'NR==1 { print $1 }')
	else
		# btrfs with subvol
		_mntpoint=$(get_mount_info TARGET,SOURCE source "$1" | grep "\[$_subvol\]$" | awk 'NR==1 { print $1 }')
	fi
	# fallback to the old way when _mntpoint is empty.
	[ -n "$_mntpoint" ] || _mntpoint=$(get_mount_info TARGET source "$1" -f)
	echo "$_mntpoint"
}

get_btrfs_subvol_from_mntopt()
{
	_subvol=${1#*subvol=}
	# mount option may not contain subvol
	[ "$1" != "$_subvol" ] || return 0
	_subvol=${_subvol%%,*}
	echo "$_subvol"
}

is_ssh_dump_target()
{
	kdump_get_conf_val ssh | grep -q @
}

is_raw_dump_target()
{
	[ -n "$(kdump_get_conf_val raw)" ]
}

is_virtiofs_dump_target()
{
	if [ -n "$(kdump_get_conf_val virtiofs)" ]; then
		return 0
	fi

	if is_fs_type_virtiofs "$(get_dracut_args_fstype "$(kdump_get_conf_val dracut_args)")"; then
		return 0
	fi

	if is_fs_type_virtiofs "$(get_fs_type_from_target "$(get_target_from_path "$(get_save_path)")")"; then
		return 0
	fi

	return 1
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

is_lvm2_thinp_device()
{
	_device_path=$1
	_lvm2_thin_device=$(lvm lvs -S 'lv_layout=sparse && lv_layout=thin' \
		--nosuffix --noheadings -o vg_name,lv_name "$_device_path" 2> /dev/null)

	[ -n "$_lvm2_thin_device" ]
}

kdump_get_ip_route()
{
	if ! _route=$(/sbin/ip -o route get to "$1" 2>&1); then
		exit 1
	fi
	echo "$_route"
}

kdump_get_ip_route_field()
{
	echo "$1" | sed -n -e "s/^.*\<$2\>\s\+\(\S\+\).*$/\1/p"
}
