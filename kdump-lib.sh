#!/bin/bash
#
# Kdump common variables and functions
#
if [[ ${__SOURCED__:+x} ]]; then
	. ./kdump-lib-initramfs.sh
else
	. /lib/kdump/kdump-lib-initramfs.sh
fi

FADUMP_ENABLED_SYS_NODE="/sys/kernel/fadump/enabled"
FADUMP_REGISTER_SYS_NODE="/sys/kernel/fadump/registered"
FADUMP_APPEND_ARGS_SYS_NODE="/sys/kernel/fadump/bootargs_append"
maximize_crashkernel=0

is_uki()
{
	local img

	img="$1"

	[[ -f "$img" ]] || return
	[[ "$(objdump -a "$img" 2> /dev/null)" =~ pei-(x86-64|aarch64-little) ]] || return
	objdump -h -j .linux "$img" &> /dev/null
}

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

is_aws_aarch64()
{
	[[ "$(lscpu | grep "BIOS Model name")" =~ "AWS Graviton" ]]
}

is_sme_or_sev_active()
{
	$maximize_crashkernel || journalctl -q --dmesg --grep "^Memory Encryption Features active: AMD (SME|SEV)$" >/dev/null 2>&1
}

has_command()
{
	[[ -x $(command -v "$1") ]]
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
	[[ $(kdump_get_conf_val "ext[234]\|xfs\|btrfs\|minix\|raw\|nfs\|ssh\|virtiofs") ]] || is_mount_in_dracut_args
}

get_block_dump_target()
{
	local _target _fstype

	if is_ssh_dump_target || is_nfs_dump_target; then
		return
	fi

	_target=$(kdump_get_conf_val "ext[234]\|xfs\|btrfs\|minix\|raw\|virtiofs")
	[[ -n $_target ]] && to_dev_name "$_target" && return

	_target=$(get_dracut_args_target "$(kdump_get_conf_val "dracut_args")")
	[[ -b $_target ]] && to_dev_name "$_target" && return

	_fstype=$(get_dracut_args_fstype "$(kdump_get_conf_val "dracut_args")")
	is_fs_type_virtiofs "$_fstype" && echo "$_target" && return

	_target=$(get_target_from_path "$(get_save_path)")
	[[ -b $_target ]] && to_dev_name "$_target" && return

	_fstype=$(get_fs_type_from_target "$_target")
	is_fs_type_virtiofs "$_fstype" && echo "$_target" && return
}

is_dump_to_rootfs()
{
	[[ $(kdump_get_conf_val 'failure_action\|default') == dump_to_rootfs ]]
}

is_lvm2_thinp_dump_target()
{
	_target=$(get_block_dump_target)
	[ -n "$_target" ] && is_lvm2_thinp_device "$_target"
}

get_failure_action_target()
{
	local _target

	if is_dump_to_rootfs; then
		# Get rootfs device name
		_target=$(get_root_fs_device)
		[[ -b $_target ]] && to_dev_name "$_target" && return
		is_fs_type_virtiofs "$(get_fs_type_from_target "$_target")" && echo "$_target" && return
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
	_path=${1#"$_mnt"}

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

	_fsroot=${_src#"${_src_nofsroot}"[}
	_fsroot=${_fsroot%]}
	_mnt=$(get_mntpoint_from_target "$_src_nofsroot")

	# for btrfs, _fsroot will also contain the subvol value as well, strip it
	if [[ $_fstype == btrfs ]]; then
		local _subvol
		_subvol=${_opt#*subvol=}
		_subvol=${_subvol%,*}
		_fsroot=${_fsroot#"$_subvol"}
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
	get_persistent_dev "$dev"
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
	[[ "$(kdump_get_conf_val dracut_args)" =~ (^|[[:space:]])--(gzip|bzip2|lzma|xz|lzo|lz4|zstd|no-compress|compress|squash-compressor)([[:space:]]|$) ]]
}

# If "dracut_args" contains "--mount" information, use it
# directly without any check(users are expected to ensure
# its correctness).
is_mount_in_dracut_args()
{
	[[ " $(kdump_get_conf_val dracut_args)" =~ .*[[:space:]]--mount[=[:space:]].* ]]
}

get_reserved_mem_size()
{
	local reserved_mem_size=0

	if is_fadump_capable; then
		reserved_mem_size=$(< /sys/kernel/fadump/mem_reserved)
	else
		reserved_mem_size=$(< /sys/kernel/kexec_crash_size)
	fi

	echo "$reserved_mem_size"
}

check_crash_mem_reserved()
{
	local mem_reserved

	mem_reserved=$(get_reserved_mem_size)
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

is_kernel_loaded()
{
	local _sysfs _mode

	_mode=$1

	case "$_mode" in
	kdump)
		_sysfs="/sys/kernel/kexec_crash_loaded"
		;;
	fadump)
		_sysfs="$FADUMP_REGISTER_SYS_NODE"
		;;
	*)
		derror "Unknown dump mode '$_mode' provided"
		return 1
		;;
	esac

	if [[ ! -f $_sysfs ]]; then
		derror "$_mode is not supported on this kernel"
		return 1
	fi

	[[ $(< $_sysfs) -eq 1 ]]
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

	# For secureboot enabled machines, use new kexec file based syscall.
	# Old syscall will always fail as it does not have capability to do
	# kernel signature verification.
	if is_secure_boot_enforced; then
		dinfo "Secure Boot is enabled. Using kexec file based syscall."
		kexec_args="$kexec_args -s"
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
	boot_imglist="$KDUMP_IMG-$kdump_kernelver$KDUMP_IMG_EXT \
		$machine_id/$kdump_kernelver/$KDUMP_IMG \
		EFI/Linux/$machine_id-$kdump_kernelver.efi"

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

_is_valid_kver()
{
	[[ -f /usr/lib/modules/$1/modules.dep ]]
}

# This function is introduced since 64k variant may be installed on 4k or vice versa
# $1 the kernel path name.
parse_kver_from_path()
{
	local _img _kver

	[[ -z "$1" ]] && return

	_img=$1
	BLS_ENTRY_TOKEN=$(</etc/machine-id)

	# Fedora standard installation, i.e. $BOOT/vmlinuz-<version>
	_kver=${_img##*/vmlinuz-}
	_kver=${_kver%"$KDUMP_IMG_EXT"}
	if _is_valid_kver "$_kver"; then
		echo "$_kver"
		return
	fi

	# BLS recommended image names, i.e. $BOOT/<token>/<version>/linux
	_kver=${_img##*/"$BLS_ENTRY_TOKEN"/}
	_kver=${_kver%%/*}
	if _is_valid_kver "$_kver"; then
		echo "$_kver"
		return
	fi

	# Fedora UKI installation, i.e. $BOOT/efi/EFI/Linux/<token>-<version>.efi
	_kver=${_img##*/"$BLS_ENTRY_TOKEN"-}
	_kver=${_kver%.efi}
	if _is_valid_kver "$_kver"; then
		echo "$_kver"
		return
	fi

	ddebug "Could not parse version from $_img"
}

_get_kdump_kernel_version()
{
	local _version _version_nondebug

	if [[ -n "$KDUMP_KERNELVER" ]]; then
		echo "$KDUMP_KERNELVER"
		return
	fi

	_version=$(uname -r)
	if [[ ! "$_version" =~ [+|-]debug$ ]]; then
		echo "$_version"
		return
	fi

	_version_nondebug=${_version%+debug}
	_version_nondebug=${_version_nondebug%-debug}
	if _is_valid_kver "$_version_nondebug"; then
		dinfo "Use of debug kernel detected. Trying to use $_version_nondebug"
		echo "$_version_nondebug"
	else
		dinfo "Use of debug kernel detected but cannot find $_version_nondebug. Falling back to $_version"
		echo "$_version"
	fi
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
	local boot_initrdlist default_initrd_base var_target_initrd_dir

	KDUMP_KERNELVER=$(_get_kdump_kernel_version)
	KDUMP_KERNEL=$(prepare_kdump_kernel "$KDUMP_KERNELVER")

	if ! [[ -e $KDUMP_KERNEL ]]; then
		derror "Failed to detect kdump kernel location"
		return 1
	fi

	# For 64k variant, e.g. vmlinuz-5.14.0-327.el9.aarch64+64k-debug
	if [[ "$KDUMP_KERNEL" == *"+debug" || "$KDUMP_KERNEL" == *"64k-debug" ]]; then
		dwarn "Using debug kernel, you may need to set a larger crashkernel than the default value."
	fi

	# Set KDUMP_BOOTDIR to where kernel image is stored
	if is_uki "$KDUMP_KERNEL"; then
		KDUMP_BOOTDIR=/boot
	else
		KDUMP_BOOTDIR=$(dirname "$KDUMP_KERNEL")
	fi

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

_cmdline_parse()
{
	local opt val

	while read -r opt; do
		if [[ $opt =~ = ]]; then
			val=${opt#*=}
			opt=${opt%%=*}
			# ignore options like 'foo='
			[[ -z $val ]] && continue
			# xargs removes quotes, add them again
			[[ $val =~ [[:space:]] ]] && val="\"$val\""
		else
			val=""
		fi

		echo "$opt $val"
	done <<< "$(echo "$1" | xargs -n 1 echo)"
}

#
# prepare_cmdline <commandline> <commandline remove> <commandline append>
# This function performs a series of edits on the command line.
prepare_cmdline()
{
	local in out append opt val id drv
	local -A remove

	in=${1:-$(< /proc/cmdline)}
	while read -r opt val; do
		[[ -n "$opt" ]] || continue
		remove[$opt]=1
	done <<< "$(_cmdline_parse "$2")"
	append=$3


	# These params should always be removed
	remove[crashkernel]=1
	remove[panic_on_warn]=1

	# Always remove "root=X", as we now explicitly generate all kinds
	# of dump target mount information including root fs.
	#
	# We do this before KDUMP_COMMANDLINE_APPEND, if one really cares
	# about it(e.g. for debug purpose), then can pass "root=X" using
	# KDUMP_COMMANDLINE_APPEND.
	remove[root]=1

	# With the help of "--hostonly-cmdline", we can avoid some interitage.
	remove[rd.lvm.lv]=1
	remove[rd.luks.uuid]=1
	remove[rd.dm.uuid]=1
	remove[rd.md.uuid]=1
	remove[fcoe]=1

	# Remove netroot, rd.iscsi.initiator and iscsi_initiator since
	# we get duplicate entries for the same in case iscsi code adds
	# it as well.
	remove[netroot]=1
	remove[rd.iscsi.initiator]=1
	remove[iscsi_initiator]=1

	while read -r opt val; do
		[[ -n "$opt" ]] || continue
		[[ -n "${remove[$opt]}" ]] && continue

		if [[ -n "$val" ]]; then
			out+="$opt=$val "
		else
			out+="$opt "
		fi
	done <<< "$(_cmdline_parse "$in")"

	out+="$append "

	id=$(get_bootcpu_apicid)
	if [[ -n "${id}" ]]; then
		out+="disable_cpu_apicid=$id "
	fi

	# If any watchdog is used, set it's pretimeout to 0. pretimeout let
	# watchdog panic the kernel first, and reset the system after the
	# panic. If the system is already in kdump, panic is not helpful
	# and only increase the chance of watchdog failure.
	for drv in $(get_watchdog_drvs); do
		out+="$drv.pretimeout=0 "

		if [[ $drv == hpwdt ]]; then
			# hpwdt have a special parameter kdumptimeout, it is
			# only supposed to be set to non-zero in first kernel.
			# In kdump, non-zero value could prevent the watchdog
			# from resetting the system.
			out+="$drv.kdumptimeout=0 "
		fi
	done

	# This is a workaround on AWS platform. Always remove irqpoll since it
	# may cause the hot-remove of some pci hotplug device.
	is_aws_aarch64 && out=$(echo "$out" | sed -e "s/\<irqpoll\>//")

	# Always disable gpt-auto-generator as it hangs during boot of the
	# crash kernel. Furthermore we know which disk will be used for dumping
	# (if at all) and add it explicitly.
	is_uki "$KDUMP_KERNEL" && out+="rd.systemd.gpt_auto=no "

	# Trim unnecessary whitespaces
	echo "$out" | sed -e "s/^ *//g" -e "s/ *$//g" -e "s/ \+/ /g"
}

PROC_IOMEM=/proc/iomem
#get system memory size i.e. memblock.memory.total_size in the unit of GB
get_system_size()
{
	local _mem_size_mb _sum
	_sum=$(sed -n "s/\s*\([0-9a-fA-F]\+\)-\([0-9a-fA-F]\+\) : System RAM$/+ 0x\2 - 0x\1 + 1/p" $PROC_IOMEM)
	_mem_size_mb=$(( (_sum) / 1024 / 1024 ))
	# rounding up the total_size to 128M to align with kernel code kernel/crash_reserve.c
	echo $(((_mem_size_mb + 127) / 128 * 128 / 1024 ))
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
		IFS=, read -r start start_unit end end_unit size <<< \
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

has_mlx5()
{
	$maximize_crashkernel || [[ -d /sys/bus/pci/drivers/mlx5_core ]]
}

has_aarch64_smmu()
{
	$maximize_crashkernel || ls /sys/devices/platform/arm-smmu-* 1> /dev/null 2>&1
}

is_aarch64_64k_kernel()
{
	local _kernel="$1"
	$maximize_crashkernel || echo "$_kernel" | grep -q 64k
}

is_memsize() { [[ "$1" =~ ^[+-]?[0-9]+[KkMmGgTtPbEe]?$ ]]; }

# range defined for crashkernel parameter
# i.e. <start>-[<end>]
is_memrange()
{
	is_memsize "${1%-*}" || return 1
	[[ -n ${1#*-} ]] || return 0
	is_memsize "${1#*-}"
}

to_bytes()
{
	local _s

	_s="$1"
	is_memsize "$_s" || return 1

	case "${_s: -1}" in
		K|k)
			_s=${_s::-1}
			_s="$((_s * 1024))"
			;;
		M|m)
			_s=${_s::-1}
			_s="$((_s * 1024 * 1024))"
			;;
		G|g)
			_s=${_s::-1}
			_s="$((_s * 1024 * 1024 * 1024))"
			;;
		T|t)
			_s=${_s::-1}
			_s="$((_s * 1024 * 1024 * 1024 * 1024))"
			;;
		P|p)
			_s=${_s::-1}
			_s="$((_s * 1024 * 1024 * 1024 * 1024 * 1024))"
			;;
		E|e)
			_s=${_s::-1}
			_s="$((_s * 1024 * 1024 * 1024 * 1024 * 1024 * 1024))"
			;;
		*)
			;;
	esac
	echo "$_s"
}

memsize_add()
{
	local -a units=("" "K" "M" "G" "T" "P" "E")
	local i a b

	a=$(to_bytes "$1") || return 1
	b=$(to_bytes "$2") || return 1
	i=0

	(( a += b ))
	while :; do
		[[ $(( a / 1024 )) -eq 0 ]] && break
		[[ $(( a % 1024 )) -ne 0 ]] && break
		[[ $(( ${#units[@]} - 1 )) -eq $i ]] && break

		(( a /= 1024 ))
		(( i += 1 ))
	done

	echo "${a}${units[$i]}"
}

_crashkernel_parse()
{
	local ck entry
	local range size offset

	ck="$1"

	if [[ "$ck" == *@* ]]; then
		offset="@${ck##*@}"
		ck=${ck%@*}
	elif [[ "$ck" == *,high ]] || [[ "$ck" == *,low ]]; then
		offset=",${ck##*,}"
		ck=${ck%,*}
	else
		offset=''
	fi

	while read -d , -r entry; do
		[[ -n "$entry" ]] || continue
		if [[ "$entry" == *:* ]]; then
			range=${entry%:*}
			size=${entry#*:}
		else
			range=""
			size=${entry}
		fi

		echo "$size;$range;"
	done <<< "$ck,"
	echo ";;$offset"
}

# $1 crashkernel command line parameter
# $2 size to be added
_crashkernel_add()
{
	local ck delta ret
	local range size offset

	ck="$1"
	delta="$2"
	ret=""

	while IFS=';' read -r size range offset; do
		if [[ -n "$offset" ]]; then
			ret="${ret%,}$offset"
			break
		fi

		[[ -n "$size" ]] || continue
		if [[ -n "$range" ]]; then
			is_memrange "$range" || return 1
			ret+="$range:"
		fi

		size=$(memsize_add "$size" "$delta") || return 1
		ret+="$size,"
	done < <( _crashkernel_parse "$ck")

	echo "${ret%,}"
}

# get default crashkernel
# $1 dump mode, if not specified, dump_mode will be judged by is_fadump_capable
# $2 kernel-release, if not specified, got by _get_kdump_kernel_version
kdump_get_arch_recommend_crashkernel()
{
	local _arch _ck_cmdline _dump_mode
	local _delta=0

	# osbuild deploys rpm on chroot environment. kdump-utils has no opportunity
	# to deduce the exact memory cost on the real target.
	maximize_crashkernel=$(is_ostree)
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
		_ck_cmdline="2G-64G:256M,64G-:512M"
		is_sme_or_sev_active && ((_delta += 64))
	elif [[ $_arch == "aarch64" ]]; then
		local _running_kernel

		# Base line for 4K variant kernel. The formula is based on x86 plus extra = 64M
		_ck_cmdline="2G-4G:256M,4G-64G:320M,64G-:576M"
		if [[ -z "$2" ]]; then
			_running_kernel=$(_get_kdump_kernel_version)
		else
			_running_kernel=$2
		fi

		# the naming convention of 64k variant suffixes with +64k, e.g. "vmlinuz-5.14.0-312.el9.aarch64+64k"
		if is_aarch64_64k_kernel "$_running_kernel"; then
			# Without smmu, the diff of MemFree between 4K and 64K measured on a high end aarch64 machine is 82M.
			# Picking up 100M to cover this diff. And finally, we have "2G-4G:356M;4G-64G:420M;64G-:676M"
			((_delta += 100))
			# On a 64K system, the extra 384MB is calculated by: cmdq_num * 16 bytes + evtq_num * 32B + priq_num * 16B
			# While on a 4K system, it is negligible
			has_aarch64_smmu && ((_delta += 384))
			#64k kernel, mlx5 consumes extra 188M memory, and choose 200M
			has_mlx5 && ((_delta += 200))
		else
			#4k kernel, mlx5 consumes extra 124M memory, and choose 150M
			has_mlx5 && ((_delta += 150))
		fi
	elif [[ $_arch == "ppc64le" ]]; then
		if [[ $_dump_mode == "fadump" ]]; then
			_ck_cmdline="4G-16G:768M,16G-64G:1G,64G-128G:2G,128G-1T:4G,1T-2T:6G,2T-4T:12G,4T-8T:20G,8T-16T:36G,16T-32T:64G,32T-64T:128G,64T-:180G"
		else
			_ck_cmdline="2G-4G:384M,4G-16G:512M,16G-64G:1G,64G-128G:2G,128G-:4G"
		fi
	fi

	echo -n "$(_crashkernel_add "$_ck_cmdline" "${_delta}M")"
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
