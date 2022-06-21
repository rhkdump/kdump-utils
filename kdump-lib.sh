#!/bin/bash
#
# Kdump common variables and functions
#
if [[ ${__SOURCED__:+x} ]]; then
	. ./kdump-lib-initramfs.sh
else
	. /lib/kdump/kdump-lib-initramfs.sh
fi

FADUMP_ENABLED_SYS_NODE="/sys/kernel/fadump_enabled"

is_fadump_capable()
{
	# Check if firmware-assisted dump is enabled
	# if no, fallback to kdump check
	if [[ -f $FADUMP_ENABLED_SYS_NODE ]]; then
		rc=$(< $FADUMP_ENABLED_SYS_NODE)
		[[ $rc -eq 1 ]] && return 0
	fi
	return 1
}

is_squash_available()
{
	for kmodule in squashfs overlay loop; do
		if [[ -z $KDUMP_KERNELVER ]]; then
			modprobe --dry-run $kmodule &> /dev/null || return 1
		else
			modprobe -S "$KDUMP_KERNELVER" --dry-run $kmodule &> /dev/null || return 1
		fi
	done
}

is_zstd_command_available()
{
	[[ -x "$(command -v zstd)" ]]
}

perror_exit()
{
	derror "$@"
	exit 1
}

# Check if fence kdump is configured in Pacemaker cluster
is_pcs_fence_kdump()
{
	# no pcs or fence_kdump_send executables installed?
	type -P pcs > /dev/null || return 1
	[[ -x $FENCE_KDUMP_SEND ]] || return 1

	# fence kdump not configured?
	(pcs cluster cib | grep 'type="fence_kdump"') &> /dev/null || return 1
}

# Check if fence_kdump is configured using kdump options
is_generic_fence_kdump()
{
	[[ -x $FENCE_KDUMP_SEND ]] || return 1

	[[ $(kdump_get_conf_val fence_kdump_nodes) ]]
}

to_dev_name()
{
	local dev="${1//\"/}"

	case "$dev" in
	UUID=*)
		blkid -U "${dev#UUID=}"
		;;
	LABEL=*)
		blkid -L "${dev#LABEL=}"
		;;
	*)
		echo "$dev"
		;;
	esac
}

is_user_configured_dump_target()
{
	[[ $(kdump_get_conf_val "ext[234]\|xfs\|btrfs\|minix\|raw\|nfs\|ssh") ]] || is_mount_in_dracut_args
}

get_user_configured_dump_disk()
{
	local _target

	_target=$(kdump_get_conf_val "ext[234]\|xfs\|btrfs\|minix\|raw")
	[[ -n $_target ]] && echo "$_target" && return

	_target=$(get_dracut_args_target "$(kdump_get_conf_val "dracut_args")")
	[[ -b $_target ]] && echo "$_target"
}

get_block_dump_target()
{
	local _target _path

	if is_ssh_dump_target || is_nfs_dump_target; then
		return
	fi

	_target=$(get_user_configured_dump_disk)
	[[ -n $_target ]] && to_dev_name "$_target" && return

	# Get block device name from local save path
	_path=$(get_save_path)
	_target=$(get_target_from_path "$_path")
	[[ -b $_target ]] && to_dev_name "$_target"
}

is_dump_to_rootfs()
{
	[[ $(kdump_get_conf_val 'failure_action\|default') == dump_to_rootfs ]]
}

get_failure_action_target()
{
	local _target

	if is_dump_to_rootfs; then
		# Get rootfs device name
		_target=$(get_root_fs_device)
		[[ -b $_target ]] && to_dev_name "$_target" && return
		# Then, must be nfs root
		echo "nfs"
	fi
}

# Get kdump targets(including root in case of dump_to_rootfs).
get_kdump_targets()
{
	local _target _root
	local kdump_targets

	_target=$(get_block_dump_target)
	if [[ -n $_target ]]; then
		kdump_targets=$_target
	elif is_ssh_dump_target; then
		kdump_targets="ssh"
	else
		kdump_targets="nfs"
	fi

	# Add the root device if dump_to_rootfs is specified.
	_root=$(get_failure_action_target)
	if [[ -n $_root ]] && [[ $kdump_targets != "$_root" ]]; then
		kdump_targets="$kdump_targets $_root"
	fi

	echo "$kdump_targets"
}

# Return the bind mount source path, return the path itself if it's not bind mounted
# Eg. if /path/to/src is bind mounted to /mnt/bind, then:
# /mnt/bind -> /path/to/src, /mnt/bind/dump -> /path/to/src/dump
#
# findmnt uses the option "-v, --nofsroot" to exclusive the [/dir]
# in the SOURCE column for bind-mounts, then if $_src equals to
# $_src_nofsroot, the mountpoint is not bind mounted directory.
#
# Below is just an example for mount info
# /dev/mapper/atomicos-root[/ostree/deploy/rhel-atomic-host/var], if the
# directory is bind mounted. The former part represents the device path, rest
# part is the bind mounted directory which quotes by bracket "[]".
get_bind_mount_source()
{
	local _mnt _path _src _opt _fstype
	local _fsroot _src_nofsroot

	_mnt=$(df "$1" | tail -1 | awk '{print $NF}')
	_path=${1#$_mnt}

	_src=$(get_mount_info SOURCE target "$_mnt" -f)
	_opt=$(get_mount_info OPTIONS target "$_mnt" -f)
	_fstype=$(get_mount_info FSTYPE target "$_mnt" -f)

	# bind mount in fstab
	if [[ -d $_src ]] && [[ $_fstype == none ]] && (echo "$_opt" | grep -q "\bbind\b"); then
		echo "$_src$_path" && return
	fi

	# direct mount
	_src_nofsroot=$(get_mount_info SOURCE target "$_mnt" -v -f)
	if [[ $_src_nofsroot == "$_src" ]]; then
		echo "$_mnt$_path" && return
	fi

	_fsroot=${_src#${_src_nofsroot}[}
	_fsroot=${_fsroot%]}
	_mnt=$(get_mount_info TARGET source "$_src_nofsroot" -f)

	# for btrfs, _fsroot will also contain the subvol value as well, strip it
	if [[ $_fstype == btrfs ]]; then
		local _subvol
		_subvol=${_opt#*subvol=}
		_subvol=${_subvol%,*}
		_fsroot=${_fsroot#$_subvol}
	fi
	echo "$_mnt$_fsroot$_path"
}

get_mntopt_from_target()
{
	get_mount_info OPTIONS source "$1" -f
}

# Get the path where the target will be mounted in kdump kernel
# $1: kdump target device
get_kdump_mntpoint_from_target()
{
	local _mntpoint

	_mntpoint=$(get_mntpoint_from_target "$1")
	# mount under /sysroot if dump to root disk or mount under
	# mount under /kdumproot if dump target is not mounted in first kernel
	# mount under /kdumproot/$_mntpoint in other cases in 2nd kernel.
	# systemd will be in charge to umount it.
	if [[ -z $_mntpoint ]]; then
		_mntpoint="/kdumproot"
	else
		if [[ $_mntpoint == "/" ]]; then
			_mntpoint="/sysroot"
		else
			_mntpoint="/kdumproot/$_mntpoint"
		fi
	fi

	# strip duplicated "/"
	echo $_mntpoint | tr -s "/"
}

kdump_get_persistent_dev()
{
	local dev="${1//\"/}"

	case "$dev" in
	UUID=*)
		dev=$(blkid -U "${dev#UUID=}")
		;;
	LABEL=*)
		dev=$(blkid -L "${dev#LABEL=}")
		;;
	esac
	echo $(get_persistent_dev "$dev")
}

is_ostree()
{
	test -f /run/ostree-booted
}

# get ip address or hostname from nfs/ssh config value
get_remote_host()
{
	local _config_val=$1

	# ipv6 address in kdump.conf is around with "[]",
	# factor out the ipv6 address
	_config_val=${_config_val#*@}
	_config_val=${_config_val%:/*}
	_config_val=${_config_val#[}
	_config_val=${_config_val%]}
	echo "$_config_val"
}

is_hostname()
{
	local _hostname

	_hostname=$(echo "$1" | grep ":")
	if [[ -n $_hostname ]]; then
		return 1
	fi
	echo "$1" | grep -q "[a-zA-Z]"
}

# Copied from "/etc/sysconfig/network-scripts/network-functions"
get_hwaddr()
{
	if [[ -f "/sys/class/net/$1/address" ]]; then
		awk '{ print toupper($0) }' < "/sys/class/net/$1/address"
	elif [[ -d "/sys/class/net/$1" ]]; then
		LC_ALL="" LANG="" ip -o link show "$1" 2> /dev/null |
			awk '{ print toupper(gensub(/.*link\/[^ ]* ([[:alnum:]:]*).*/,
                                        "\\1", 1)); }'
	fi
}

# Get value by a field using "nmcli -g"
# Usage: get_nmcli_value_by_field <field> <nmcli command>
#
# "nmcli --get-values" allows us to retrive value(s) by field, for example,
# nmcli --get-values <field> connection show /org/freedesktop/NetworkManager/ActiveConnection/1
# returns the following value for the corresponding field respectively,
#   Field                                  Value
#   IP4.DNS                                "10.19.42.41 | 10.11.5.19 | 10.5.30.160"
#   802-3-ethernet.s390-subchannels        ""
#   bond.options                           "mode=balance-rr"
get_nmcli_value_by_field()
{
	LANG=C nmcli --get-values "$@"
}

# Get nmcli field value of an connection apath (a D-Bus active connection path)
# Usage: get_nmcli_field_by_apath <field> <apath>
get_nmcli_field_by_conpath()
{
	local _field=$1 _apath=$2

	get_nmcli_value_by_field "$_field" connection show "$_apath"
}

# Get nmcli connection apath (a D-Bus active connection path ) by ifname
#
# apath is used for nmcli connection operations, e.g.
#  $ nmcli connection show $apath
get_nmcli_connection_apath_by_ifname()
{
	local _ifname=$1

	get_nmcli_value_by_field "GENERAL.CON-PATH" device show "$_ifname"
}

get_ifcfg_by_device()
{
	grep -E -i -l "^[[:space:]]*DEVICE=\"*${1}\"*[[:space:]]*$" \
		/etc/sysconfig/network-scripts/ifcfg-* 2> /dev/null | head -1
}

get_ifcfg_by_hwaddr()
{
	grep -E -i -l "^[[:space:]]*HWADDR=\"*${1}\"*[[:space:]]*$" \
		/etc/sysconfig/network-scripts/ifcfg-* 2> /dev/null | head -1
}

get_ifcfg_by_uuid()
{
	grep -E -i -l "^[[:space:]]*UUID=\"*${1}\"*[[:space:]]*$" \
		/etc/sysconfig/network-scripts/ifcfg-* 2> /dev/null | head -1
}

get_ifcfg_by_name()
{
	grep -E -i -l "^[[:space:]]*NAME=\"*${1}\"*[[:space:]]*$" \
		/etc/sysconfig/network-scripts/ifcfg-* 2> /dev/null | head -1
}

is_nm_running()
{
	[[ "$(LANG=C nmcli -t --fields running general status 2> /dev/null)" == "running" ]]
}

is_nm_handling()
{
	LANG=C nmcli -t --fields device,state dev status 2> /dev/null |
		grep -q "^\(${1}:connected\)\|\(${1}:connecting.*\)$"
}

# $1: netdev name
get_ifcfg_nmcli()
{
	local nm_uuid nm_name
	local ifcfg_file

	# Get the active nmcli config name of $1
	if is_nm_running && is_nm_handling "${1}"; then
		# The configuration "uuid" and "name" generated by nm is wrote to
		# the ifcfg file as "UUID=<nm_uuid>" and "NAME=<nm_name>".
		nm_uuid=$(LANG=C nmcli -t --fields uuid,device c show --active 2> /dev/null |
			grep "${1}" | head -1 | cut -d':' -f1)
		nm_name=$(LANG=C nmcli -t --fields name,device c show --active 2> /dev/null |
			grep "${1}" | head -1 | cut -d':' -f1)
		ifcfg_file=$(get_ifcfg_by_uuid "${nm_uuid}")
		[[ -z ${ifcfg_file} ]] && ifcfg_file=$(get_ifcfg_by_name "${nm_name}")
	fi

	echo -n "${ifcfg_file}"
}

# $1: netdev name
get_ifcfg_legacy()
{
	local ifcfg_file hwaddr

	ifcfg_file="/etc/sysconfig/network-scripts/ifcfg-${1}"
	[[ -f ${ifcfg_file} ]] && echo -n "${ifcfg_file}" && return

	ifcfg_file=$(get_ifcfg_by_name "${1}")
	[[ -f ${ifcfg_file} ]] && echo -n "${ifcfg_file}" && return

	hwaddr=$(get_hwaddr "${1}")
	if [[ -n $hwaddr ]]; then
		ifcfg_file=$(get_ifcfg_by_hwaddr "${hwaddr}")
		[[ -f ${ifcfg_file} ]] && echo -n "${ifcfg_file}" && return
	fi

	ifcfg_file=$(get_ifcfg_by_device "${1}")

	echo -n "${ifcfg_file}"
}

# $1: netdev name
# Return the ifcfg file whole name(including the path) of $1 if any.
get_ifcfg_filename()
{
	local ifcfg_file

	ifcfg_file=$(get_ifcfg_nmcli "${1}")
	if [[ -z ${ifcfg_file} ]]; then
		ifcfg_file=$(get_ifcfg_legacy "${1}")
	fi

	echo -n "${ifcfg_file}"
}

# returns 0 when omission of a module is desired in dracut_args
# returns 1 otherwise
is_dracut_mod_omitted()
{
	local dracut_args dracut_mod=$1

	set -- $(kdump_get_conf_val dracut_args)
	while [ $# -gt 0 ]; do
		case $1 in
		-o | --omit)
			[[ " ${2//[^[:alnum:]]/ } " == *" $dracut_mod "* ]] && return 0
			;;
		esac
		shift
	done

	return 1
}

is_wdt_active()
{
	local active

	[[ -d /sys/class/watchdog ]] || return 1
	for dir in /sys/class/watchdog/*; do
		[[ -f "$dir/state" ]] || continue
		active=$(< "$dir/state")
		[[ $active == "active" ]] && return 0
	done
	return 1
}

have_compression_in_dracut_args()
{
	[[ "$(kdump_get_conf_val dracut_args)" =~ \
		(^|[[:space:]])--(gzip|bzip2|lzma|xz|lzo|lz4|zstd|no-compress|compress)([[:space:]]|$) ]]
}

# If "dracut_args" contains "--mount" information, use it
# directly without any check(users are expected to ensure
# its correctness).
is_mount_in_dracut_args()
{
	[[ " $(kdump_get_conf_val dracut_args)" =~ .*[[:space:]]--mount[=[:space:]].* ]]
}

check_crash_mem_reserved()
{
	local mem_reserved

	mem_reserved=$(< /sys/kernel/kexec_crash_size)
	if [[ $mem_reserved -eq 0 ]]; then
		derror "No memory reserved for crash kernel"
		return 1
	fi

	return 0
}

check_kdump_feasibility()
{
	if [[ ! -e /sys/kernel/kexec_crash_loaded ]]; then
		derror "Kdump is not supported on this kernel"
		return 1
	fi
	check_crash_mem_reserved
	return $?
}

check_current_kdump_status()
{
	if [[ ! -f /sys/kernel/kexec_crash_loaded ]]; then
		derror "Perhaps CONFIG_CRASH_DUMP is not enabled in kernel"
		return 1
	fi

	rc=$(< /sys/kernel/kexec_crash_loaded)
	if [[ $rc == 1 ]]; then
		return 0
	else
		return 1
	fi
}

# remove_cmdline_param <kernel cmdline> <param1> [<param2>] ... [<paramN>]
# Remove a list of kernel parameters from a given kernel cmdline and print the result.
# For each "arg" in the removing params list, "arg" and "arg=xxx" will be removed if exists.
remove_cmdline_param()
{
	local cmdline=$1
	shift

	for arg in "$@"; do
		cmdline=$(echo "$cmdline" |
			sed -e "s/\b$arg=[^ ]*//g" \
				-e "s/^$arg\b//g" \
				-e "s/[[:space:]]$arg\b//g" \
				-e "s/\s\+/ /g")
	done
	echo "$cmdline"
}

#
# This function returns the "apicid" of the boot
# cpu (cpu 0) if present.
#
get_bootcpu_apicid()
{
	awk '                                                       \
        BEGIN { CPU = "-1"; }                                   \
        $1=="processor" && $2==":"      { CPU = $NF; }          \
        CPU=="0" && /^apicid/           { print $NF; }          \
        ' \
		/proc/cpuinfo
}

#
# append_cmdline <kernel cmdline> <parameter name> <parameter value>
# This function appends argument "$2=$3" to string ($1) if not already present.
#
append_cmdline()
{
	local cmdline=$1
	local newstr=${cmdline/$2/""}

	# unchanged str implies argument wasn't there
	if [[ $cmdline == "$newstr" ]]; then
		cmdline="${cmdline} ${2}=${3}"
	fi

	echo "$cmdline"
}

# This function check iomem and determines if we have more than
# 4GB of ram available. Returns 1 if we do, 0 if we dont
need_64bit_headers()
{
	return "$(tail -n 1 /proc/iomem | awk '{ split ($1, r, "-");
        print (strtonum("0x" r[2]) > strtonum("0xffffffff")); }')"
}

# Check if secure boot is being enforced.
#
# Per Peter Jones, we need check efivar SecureBoot-$(the UUID) and
# SetupMode-$(the UUID), they are both 5 bytes binary data. The first four
# bytes are the attributes associated with the variable and can safely be
# ignored, the last bytes are one-byte true-or-false variables. If SecureBoot
# is 1 and SetupMode is 0, then secure boot is being enforced.
#
# Assume efivars is mounted at /sys/firmware/efi/efivars.
is_secure_boot_enforced()
{
	local secure_boot_file setup_mode_file
	local secure_boot_byte setup_mode_byte

	# On powerpc, secure boot is enforced if:
	#   host secure boot: /ibm,secure-boot/os-secureboot-enforcing DT property exists
	#   guest secure boot: /ibm,secure-boot >= 2
	if [[ -f /proc/device-tree/ibm,secureboot/os-secureboot-enforcing ]]; then
		return 0
	fi
	if [[ -f /proc/device-tree/ibm,secure-boot ]] &&
		[[ $(lsprop /proc/device-tree/ibm,secure-boot | tail -1) -ge 2 ]]; then
		return 0
	fi

	# Detect secure boot on x86 and arm64
	secure_boot_file=$(find /sys/firmware/efi/efivars -name "SecureBoot-*" 2> /dev/null)
	setup_mode_file=$(find /sys/firmware/efi/efivars -name "SetupMode-*" 2> /dev/null)

	if [[ -f $secure_boot_file ]] && [[ -f $setup_mode_file ]]; then
		secure_boot_byte=$(hexdump -v -e '/1 "%d\ "' "$secure_boot_file" | cut -d' ' -f 5)
		setup_mode_byte=$(hexdump -v -e '/1 "%d\ "' "$setup_mode_file" | cut -d' ' -f 5)

		if [[ $secure_boot_byte == "1" ]] && [[ $setup_mode_byte == "0" ]]; then
			return 0
		fi
	fi

	# Detect secure boot on s390x
	if [[ -e "/sys/firmware/ipl/secure" && "$(< /sys/firmware/ipl/secure)" == "1" ]]; then
		return 0
	fi

	return 1
}

#
# prepare_kexec_args <kexec args>
# This function prepares kexec argument.
#
prepare_kexec_args()
{
	local kexec_args=$1
	local found_elf_args

	ARCH=$(uname -m)
	if [[ $ARCH == "i686" ]] || [[ $ARCH == "i386" ]]; then
		need_64bit_headers
		if [[ $? == 1 ]]; then
			found_elf_args=$(echo "$kexec_args" | grep elf32-core-headers)
			if [[ -n $found_elf_args ]]; then
				dwarn "Warning: elf32-core-headers overrides correct elf64 setting"
			else
				kexec_args="$kexec_args --elf64-core-headers"
			fi
		else
			found_elf_args=$(echo "$kexec_args" | grep elf64-core-headers)
			if [[ -z $found_elf_args ]]; then
				kexec_args="$kexec_args --elf32-core-headers"
			fi
		fi
	fi
	echo "$kexec_args"
}

# prepare_kdump_kernel <kdump_kernelver>
# This function return kdump_kernel given a kernel version.
prepare_kdump_kernel()
{
	local kdump_kernelver=$1
	local dir img boot_dirlist boot_imglist kdump_kernel machine_id
	read -r machine_id < /etc/machine-id

	boot_dirlist=${KDUMP_BOOTDIR:-"/boot /boot/efi /efi /"}
	boot_imglist="$KDUMP_IMG-$kdump_kernelver$KDUMP_IMG_EXT $machine_id/$kdump_kernelver/$KDUMP_IMG"

	# The kernel of OSTree based systems is not in the standard locations.
	if is_ostree; then
		boot_dirlist="$(echo /boot/ostree/*) $boot_dirlist"
	fi

	# Use BOOT_IMAGE as reference if possible, strip the GRUB root device prefix in (hd0,gpt1) format
	boot_img="$(grep -P -o '^BOOT_IMAGE=(\S+)' /proc/cmdline | sed "s/^BOOT_IMAGE=\((\S*)\)\?\(\S*\)/\2/")"
	if [[ "$boot_img" == *"$kdump_kernelver" ]]; then
		boot_imglist="$boot_img $boot_imglist"
	fi

	for dir in $boot_dirlist; do
		for img in $boot_imglist; do
			if [[ -f "$dir/$img" ]]; then
				kdump_kernel=$(echo "$dir/$img" | tr -s '/')
				break 2
			fi
		done
	done
	echo "$kdump_kernel"
}

#
# Detect initrd and kernel location, results are stored in global environmental variables:
# KDUMP_BOOTDIR, KDUMP_KERNELVER, KDUMP_KERNEL, DEFAULT_INITRD, and KDUMP_INITRD
#
# Expectes KDUMP_BOOTDIR, KDUMP_IMG, KDUMP_IMG_EXT, KDUMP_KERNELVER to be loaded from config already
# and will prefer already set values so user can specify custom kernel/initramfs location
#
prepare_kdump_bootinfo()
{
	local boot_initrdlist nondebug_kernelver debug_kernelver
	local default_initrd_base var_target_initrd_dir

	if [[ -z $KDUMP_KERNELVER ]]; then
		KDUMP_KERNELVER=$(uname -r)
		nondebug_kernelver=$(sed -n -e 's/\(.*\)+debug$/\1/p' <<< "$KDUMP_KERNELVER")
	fi

	# Use nondebug kernel if possible, because debug kernel will consume more memory and may oom.
	if [[ -n $nondebug_kernelver ]]; then
		dinfo "Trying to use $nondebug_kernelver."
		debug_kernelver=$KDUMP_KERNELVER
		KDUMP_KERNELVER=$nondebug_kernelver
	fi

	KDUMP_KERNEL=$(prepare_kdump_kernel "$KDUMP_KERNELVER")

	if ! [[ -e $KDUMP_KERNEL ]]; then
		if [[ -n $debug_kernelver ]]; then
			dinfo "Fallback to using debug kernel"
			KDUMP_KERNELVER=$debug_kernelver
			KDUMP_KERNEL=$(prepare_kdump_kernel "$KDUMP_KERNELVER")
		fi
	fi

	if ! [[ -e $KDUMP_KERNEL ]]; then
		derror "Failed to detect kdump kernel location"
		return 1
	fi

	if [[ "$KDUMP_KERNEL" == *"+debug" ]]; then
		dwarn "Using debug kernel, you may need to set a larger crashkernel than the default value."
	fi

	# Set KDUMP_BOOTDIR to where kernel image is stored
	KDUMP_BOOTDIR=$(dirname "$KDUMP_KERNEL")

	# Default initrd should just stay aside of kernel image, try to find it in KDUMP_BOOTDIR
	boot_initrdlist="initramfs-$KDUMP_KERNELVER.img initrd"
	for initrd in $boot_initrdlist; do
		if [[ -f "$KDUMP_BOOTDIR/$initrd" ]]; then
			default_initrd_base="$initrd"
			DEFAULT_INITRD="$KDUMP_BOOTDIR/$default_initrd_base"
			break
		fi
	done

	# Create kdump initrd basename from default initrd basename
	# initramfs-5.7.9-200.fc32.x86_64.img => initramfs-5.7.9-200.fc32.x86_64kdump.img
	# initrd => initrdkdump
	if [[ -z $default_initrd_base ]]; then
		kdump_initrd_base=initramfs-${KDUMP_KERNELVER}kdump.img
	elif [[ $default_initrd_base == *.* ]]; then
		kdump_initrd_base=${default_initrd_base%.*}kdump.${DEFAULT_INITRD##*.}
	else
		kdump_initrd_base=${default_initrd_base}kdump
	fi

	# Place kdump initrd in $(/var/lib/kdump) if $(KDUMP_BOOTDIR) not writable
	if [[ ! -w $KDUMP_BOOTDIR ]]; then
		var_target_initrd_dir="/var/lib/kdump"
		mkdir -p "$var_target_initrd_dir"
		KDUMP_INITRD="$var_target_initrd_dir/$kdump_initrd_base"
	else
		KDUMP_INITRD="$KDUMP_BOOTDIR/$kdump_initrd_base"
	fi
}

get_watchdog_drvs()
{
	local _wdtdrvs _drv _dir

	for _dir in /sys/class/watchdog/*; do
		# device/modalias will return driver of this device
		[[ -f "$_dir/device/modalias" ]] || continue
		_drv=$(< "$_dir/device/modalias")
		_drv=$(modprobe --set-version "$KDUMP_KERNELVER" -R "$_drv" 2> /dev/null)
		for i in $_drv; do
			if ! [[ " $_wdtdrvs " == *" $i "* ]]; then
				_wdtdrvs="$_wdtdrvs $i"
			fi
		done
	done

	echo "$_wdtdrvs"
}

#
# prepare_cmdline <commandline> <commandline remove> <commandline append>
# This function performs a series of edits on the command line.
# Store the final result in global $KDUMP_COMMANDLINE.
prepare_cmdline()
{
	local cmdline id arg

	if [[ -z $1 ]]; then
		cmdline=$(< /proc/cmdline)
	else
		cmdline="$1"
	fi

	# These params should always be removed
	cmdline=$(remove_cmdline_param "$cmdline" crashkernel panic_on_warn)
	# These params can be removed configurably
	while read -r arg; do
		cmdline=$(remove_cmdline_param "$cmdline" "$arg")
	done <<< "$(echo "$2" | xargs -n 1 echo)"

	# Always remove "root=X", as we now explicitly generate all kinds
	# of dump target mount information including root fs.
	#
	# We do this before KDUMP_COMMANDLINE_APPEND, if one really cares
	# about it(e.g. for debug purpose), then can pass "root=X" using
	# KDUMP_COMMANDLINE_APPEND.
	cmdline=$(remove_cmdline_param "$cmdline" root)

	# With the help of "--hostonly-cmdline", we can avoid some interitage.
	cmdline=$(remove_cmdline_param "$cmdline" rd.lvm.lv rd.luks.uuid rd.dm.uuid rd.md.uuid fcoe)

	# Remove netroot, rd.iscsi.initiator and iscsi_initiator since
	# we get duplicate entries for the same in case iscsi code adds
	# it as well.
	cmdline=$(remove_cmdline_param "$cmdline" netroot rd.iscsi.initiator iscsi_initiator)

	cmdline="${cmdline} $3"

	id=$(get_bootcpu_apicid)
	if [[ -n ${id} ]]; then
		cmdline=$(append_cmdline "$cmdline" disable_cpu_apicid "$id")
	fi

	# If any watchdog is used, set it's pretimeout to 0. pretimeout let
	# watchdog panic the kernel first, and reset the system after the
	# panic. If the system is already in kdump, panic is not helpful
	# and only increase the chance of watchdog failure.
	for i in $(get_watchdog_drvs); do
		cmdline+=" $i.pretimeout=0"

		if [[ $i == hpwdt ]]; then
			# hpwdt have a special parameter kdumptimeout, is's only suppose
			# to be set to non-zero in first kernel. In kdump, non-zero
			# value could prevent the watchdog from resetting the system.
			cmdline+=" $i.kdumptimeout=0"
		fi
	done

	echo "$cmdline"
}

PROC_IOMEM=/proc/iomem
#get system memory size i.e. memblock.memory.total_size in the unit of GB
get_system_size()
{
	sum=$(sed -n "s/\s*\([0-9a-fA-F]\+\)-\([0-9a-fA-F]\+\) : System RAM$/+ 0x\2 - 0x\1 + 1/p" $PROC_IOMEM)
	echo $(( (sum) / 1024 / 1024 / 1024))
}

# Return the recommended size for the reserved crashkernel memory
# depending on the system memory size.
#
# This functions is expected to be consistent with the parse_crashkernel_mem()
# in kernel i.e. how kernel allocates the kdump memory given the crashkernel
# parameter crashkernel=range1:size1[,range2:size2,…] and the system memory
# size.
get_recommend_size()
{
	local mem_size=$1
	local _ck_cmdline=$2
	local range start start_unit end end_unit size

	while read -r -d , range; do
		# need to use non-default IFS as double spaces are used as a
		# single delimiter while commas aren't...
		IFS=, read start start_unit end end_unit size <<< \
			"$(echo "$range" | sed -n "s/\([0-9]\+\)\([GT]\?\)-\([0-9]*\)\([GT]\?\):\([0-9]\+[MG]\)/\1,\2,\3,\4,\5/p")"

		# aka. 102400T
		end=${end:-104857600}
		[[ "$end_unit" == T ]] && end=$((end * 1024))
		[[ "$start_unit" == T ]] && start=$((start * 1024))

		if [[ $mem_size -ge $start ]] && [[ $mem_size -lt $end ]]; then
			echo "$size"
			return
		fi

		# append a ',' as read expects the 'file' to end with a delimiter
	done <<< "$_ck_cmdline,"

	# no matching range found
	echo "0M"
}

# get default crashkernel
# $1 dump mode, if not specified, dump_mode will be judged by is_fadump_capable
kdump_get_arch_recommend_crashkernel()
{
	local _arch _ck_cmdline _dump_mode

	if [[ -z "$1" ]]; then
		if is_fadump_capable; then
			_dump_mode=fadump
		else
			_dump_mode=kdump
		fi
	else
		_dump_mode=$1
	fi

	_arch=$(uname -m)

	if [[ $_arch == "x86_64" ]] || [[ $_arch == "s390x" ]]; then
		_ck_cmdline="1G-4G:192M,4G-64G:256M,64G-:512M"
	elif [[ $_arch == "aarch64" ]]; then
		# For 4KB page size, the formula is based on x86 plus extra = 64M
		_ck_cmdline="1G-4G:256M,4G-64G:320M,64G-:576M"
	elif [[ $_arch == "ppc64le" ]]; then
		if [[ $_dump_mode == "fadump" ]]; then
			_ck_cmdline="4G-16G:768M,16G-64G:1G,64G-128G:2G,128G-1T:4G,1T-2T:6G,2T-4T:12G,4T-8T:20G,8T-16T:36G,16T-32T:64G,32T-64T:128G,64T-:180G"
		else
			_ck_cmdline="2G-4G:384M,4G-16G:512M,16G-64G:1G,64G-128G:2G,128G-:4G"
		fi
	fi

	echo -n "$_ck_cmdline"
}

# return recommended size based on current system RAM size
# $1: kernel version, if not set, will defaults to $(uname -r)
kdump_get_arch_recommend_size()
{
	local _ck_cmdline _sys_mem

	if ! [[ -r "/proc/iomem" ]]; then
		echo "Error, can not access /proc/iomem."
		return 1
	fi
	_sys_mem=$(get_system_size)
	_ck_cmdline=$(kdump_get_arch_recommend_crashkernel)
	_ck_cmdline=${_ck_cmdline//-:/-102400T:}
	get_recommend_size "$_sys_mem" "$_ck_cmdline"
}

# Print all underlying crypt devices of a block device
# print nothing if device is not on top of a crypt device
# $1: the block device to be checked in maj:min format
get_luks_crypt_dev()
{
	local _type

	[[ -b /dev/block/$1 ]] || return 1

	_type=$(blkid -u filesystem,crypto -o export -- "/dev/block/$1" | \
		sed -n -E "s/^TYPE=(.*)$/\1/p")
	[[ $_type == "crypto_LUKS" ]] && echo "$1"

	for _x in "/sys/dev/block/$1/slaves/"*; do
		[[ -f $_x/dev ]] || continue
		[[ $_x/subsystem -ef /sys/class/block ]] || continue
		get_luks_crypt_dev "$(< "$_x/dev")"
	done
}

# kdump_get_maj_min <device>
# Prints the major and minor of a device node.
# Example:
# $ get_maj_min /dev/sda2
# 8:2
kdump_get_maj_min()
{
	local _majmin
	_majmin="$(stat -L -c '%t:%T' "$1" 2> /dev/null)"
	printf "%s" "$((0x${_majmin%:*})):$((0x${_majmin#*:}))"
}

get_all_kdump_crypt_dev()
{
	local _dev

	for _dev in $(get_block_dump_target); do
		get_luks_crypt_dev "$(kdump_get_maj_min "$_dev")"
	done
}

check_vmlinux()
{
	# Use readelf to check if it's a valid ELF
	readelf -h "$1" &> /dev/null || return 1
}

get_vmlinux_size()
{
	local size=0 _msize

	while read -r _msize; do
		size=$((size + _msize))
	done <<< "$(readelf -l -W "$1" | awk '/^  LOAD/{print $6}' 2> /dev/stderr)"

	echo $size
}

try_decompress()
{
	# The obscure use of the "tr" filter is to work around older versions of
	# "grep" that report the byte offset of the line instead of the pattern.

	# Try to find the header ($1) and decompress from here
	for pos in $(tr "$1\n$2" "\n$2=" < "$4" | grep -abo "^$2"); do
		if ! type -P "$3" > /dev/null; then
			ddebug "Signiature detected but '$3' is missing, skip this decompressor"
			break
		fi

		pos=${pos%%:*}
		tail "-c+$pos" "$img" | $3 > "$5" 2> /dev/null
		if check_vmlinux "$5"; then
			ddebug "Kernel is extracted with '$3'"
			return 0
		fi
	done

	return 1
}

# Borrowed from linux/scripts/extract-vmlinux
get_kernel_size()
{
	# Prepare temp files:
	local tmp img=$1

	tmp=$(mktemp /tmp/vmlinux-XXX)
	trap 'rm -f "$tmp"' 0

	# Try to check if it's a vmlinux already
	check_vmlinux "$img" && get_vmlinux_size "$img" && return 0

	# That didn't work, so retry after decompression.
	try_decompress '\037\213\010' xy gunzip "$img" "$tmp" ||
		try_decompress '\3757zXZ\000' abcde unxz "$img" "$tmp" ||
		try_decompress 'BZh' xy bunzip2 "$img" "$tmp" ||
		try_decompress '\135\0\0\0' xxx unlzma "$img" "$tmp" ||
		try_decompress '\211\114\132' xy 'lzop -d' "$img" "$tmp" ||
		try_decompress '\002!L\030' xxx 'lz4 -d' "$img" "$tmp" ||
		try_decompress '(\265/\375' xxx unzstd "$img" "$tmp"

	# Finally check for uncompressed images or objects:
	[[ $? -eq 0 ]] && get_vmlinux_size "$tmp" && return 0

	# Fallback to use iomem
	local _size=0 _seg
	while read -r _seg; do
		_size=$((_size + 0x${_seg#*-} - 0x${_seg%-*}))
	done <<< "$(grep -E "Kernel (code|rodata|data|bss)" /proc/iomem | cut -d ":" -f 1)"
	echo $_size
}
