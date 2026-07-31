#!/bin/bash --norc
# Kdump common functions to interact with dracut
#
# Copyright 2011 Red Hat, Inc.
#
# Written by Cong Wang <amwang@redhat.com>
#

# check whether the given dracut module is installed. If multiple modules are
# provided return true if any of them is installed.
has_dracut_module()
{
	local -a _args
	local _e

	[[ $# -ge 1 ]] || return 1

	for _e in "$@"; do
		_args+=(-e "$_e")
	done

	grep -x -q "${_args[@]}" <<< "$(dracut --list-modules)"
}

# caller should ensure $1 is valid and mounted in 1st kernel
to_mount()
{
	local _target=$1 _fstype=$2 _options=$3 _sed_cmd _new_mntpoint _pdev

	_fstype="${_fstype:-$(get_fs_type_from_target "$_target")}"
	_options="${_options:-$(get_mntopt_from_target "$_target")}"
	_options="${_options:-defaults}"
	if [[ $_fstype == btrfs ]]; then
		_subvol=$(get_btrfs_subvol_from_mntopt "$_options")
	fi
	_new_mntpoint=$(get_kdump_mntpoint_from_target "$_target" "$_subvol")

	if [[ $_fstype == "nfs"* ]]; then
		_pdev=$_target
		_sed_cmd+='s/,\(mount\)\?addr=[^,]*//g;'
		_sed_cmd+='s/,\(mount\)\?proto=[^,]*//g;'
		_sed_cmd+='s/,clientaddr=[^,]*//;'
	else
		# for non-nfs _target converting to use udev persistent name
		_pdev="$(kdump_get_persistent_dev "$_target")"
		if [[ -z $_pdev ]]; then
			return 1
		fi
	fi

	# mount fs target as rw in 2nd kernel
	_sed_cmd+='s/\(^\|,\)ro\($\|,\)/\1rw\2/g;'
	# with 'noauto' in fstab nfs and non-root disk mount will fail in 2nd
	# kernel, filter it out here.
	_sed_cmd+='s/\(^\|,\)noauto\($\|,\)/\1/g;'
	# drop nofail or nobootwait
	_sed_cmd+='s/\(^\|,\)nofail\($\|,\)/\1/g;'
	_sed_cmd+='s/\(^\|,\)nobootwait\($\|,\)/\1/g;'

	_options=$(echo "$_options" | sed "$_sed_cmd")

	echo "$_pdev $_new_mntpoint $_fstype $_options"
}

#Function: get_ssh_size
#$1=dump target
#called from while loop and shouldn't read from stdin, so we're using "ssh -n"
get_ssh_size()
{
	local _out
	local _opt=("-i" "${OPT[sshkey]}" "-o" "BatchMode=yes" "-o" "StrictHostKeyChecking=yes")

	if ! _out=$(ssh -q -n "${_opt[@]}" "$1" "df" "--output=avail" "${OPT[path]}"); then
		derror "checking remote ssh server available size failed."
		return 1
	fi

	echo -n "$_out" | tail -1
}

#mkdir if save path does not exist on ssh dump target
#$1=ssh dump target
#caller should ensure write permission on $1:${OPT[path]}
#called from while loop and shouldn't read from stdin, so we're using "ssh -n"
mkdir_save_path_ssh()
{
	local _opt _dir
	_opt=(-i "${OPT[sshkey]}" -o BatchMode=yes -o StrictHostKeyChecking=yes)
	ssh -qn "${_opt[@]}" "$1" mkdir -p "${OPT[path]}" &> /dev/null || {
		derror "mkdir failed on $1:${OPT[path]}"
		return 1
	}

	# check whether user has write permission on $1:${OPT[path]}
	_dir=$(ssh -qn "${_opt[@]}" "$1" mktemp -dqp "${OPT[path]}" 2> /dev/null) || {
		derror "Could not create temporary directory on $1:${OPT[path]}. Make sure user has write permission on destination"
		return 1
	}
	ssh -qn "${_opt[@]}" "$1" rmdir "$_dir"

	return 0
}

#Function: get_fs_size
#$1=dump target
get_fs_size()
{
	df --output=avail "$(get_mntpoint_from_target "$1" "$2")/${OPT[path]}" | tail -1
}

#Function: get_raw_size
#$1=dump target
get_raw_size()
{
	fdisk -s "$1"
}

#Function: check_size
#$1: dump type string ('raw', 'fs', 'ssh')
#$2: dump target
#$3: btrfs subvol
check_size()
{
	local avail memtotal

	memtotal=$(awk '/MemTotal/{print $2}' /proc/meminfo)
	case "$1" in
	raw)
		avail=$(get_raw_size "$2")
		;;
	ssh)
		avail=$(get_ssh_size "$2")
		;;
	fs)
		avail=$(get_fs_size "$2" "$3")
		;;
	*)
		return
		;;
	esac || {
		derror "Check dump target size failed"
		return 1
	}

	if [[ $avail -lt $memtotal ]]; then
		dwarn "There might not be enough space to save a vmcore."
		dwarn "The size of $2 should be greater than $memtotal kilo bytes."
	fi
}

check_save_path_fs()
{
	local _path=$1

	if [[ ! -d $_path ]]; then
		derror "Dump path $_path does not exist."
		return 1
	fi
}

mount_failure()
{
	local _target=$1
	local _mnt=$2
	local _fstype=$3
	local msg="Failed to mount $_target"

	if [[ -n $_mnt ]]; then
		msg="$msg on $_mnt"
	fi

	msg="$msg for kdump preflight check."

	if [[ $_fstype == "nfs" ]]; then
		msg="$msg Please make sure nfs-utils has been installed, and nfs server is accessible."
	fi

	derror "$msg"
	return 1
}

check_user_configured_target()
{
	local _target=$1 _cfg_fs_type=$2 _mounted
	local _mnt _opt _fstype
	local -a _timeout_cmd=()

	_mnt=$(get_mntpoint_from_target "$_target")
	_opt=$(get_mntopt_from_target "$_target")
	_fstype=$(get_fs_type_from_target "$_target")

	if [[ -n $_fstype ]]; then
		# In case of nfs4, nfs should be used instead, nfs* options is deprecated in kdump.conf
		[[ $_fstype == "nfs"* ]] && _fstype=nfs

		if [[ -n $_cfg_fs_type ]] && [[ $_fstype != "$_cfg_fs_type" ]]; then
			derror "\"$_target\" have a wrong type config \"$_cfg_fs_type\", expected \"$_fstype\""
			return 1
		fi
	else
		_fstype="$_cfg_fs_type"
		_fstype="$_cfg_fs_type"
	fi

	if [[ $_fstype == "nfs"* ]]; then
		_timeout_cmd=(timeout --preserve-status 10m)
	fi

	# For noauto mount, mount it inplace with default value.
	# Else use the temporary target directory
	if [[ -n $_mnt ]]; then
		if ! is_mounted "$_mnt"; then
			if [[ $_opt == *",noauto"* ]]; then
				"${_timeout_cmd[@]}" mount "$_mnt" || {
					mount_failure "$_target" "$_mnt" "$_fstype"
					return 1
				}
				_mounted=$_mnt
			else
				derror "Dump target \"$_target\" is neither mounted nor configured as \"noauto\""
				return 1
			fi
		fi
	else
		_mnt=$KDUMP_TMPMNT
		mkdir -p "$_mnt"
		"${_timeout_cmd[@]}" mount "$_target" "$_mnt" -t "$_fstype" -o defaults || {
			mount_failure "$_target" "" "$_fstype"
			return 1
		}
		_mounted=$_mnt
	fi

	# For user configured target, use ${OPT[path]} as the dump path within the target
	if [[ ! -d "$_mnt/${OPT[path]}" ]]; then
		derror "Dump path \"${OPT[path]}\" does not exist in dump target \"$_target\""
		[[ -n $_mounted ]] && umount -f -- "$_mounted"
		return 1
	fi

	check_size fs "$_target" || {
		[[ -n $_mounted ]] && umount -f -- "$_mounted"
		return 1
	}

	# Unmount it early, if function is interrupted and didn't reach here, the shell trap will clear it up anyway
	if [[ -n $_mounted ]]; then
		umount -f -- "$_mounted"
	fi
}

# $1: core_collector config value
verify_core_collector()
{
	local _cmd="${1%% *}"
	local _params="${1#"${_cmd}"}"

	if [[ $_cmd != "makedumpfile" ]]; then
		if is_raw_dump_target; then
			dwarn "Specifying a non-makedumpfile core collector, you will have to recover the vmcore manually."
		fi
		return
	fi

	if is_ssh_dump_target || is_raw_dump_target; then
		if ! strstr "$_params" "-F"; then
			derror 'The specified dump target needs makedumpfile "-F" option.'
			return 1
		fi
		_params="$_params vmcore"
	else
		_params="$_params vmcore dumpfile"
	fi

	# shellcheck disable=SC2086
	if ! $_cmd --check-params $_params; then
		derror "makedumpfile parameter check failed."
		return 1
	fi
}

add_mount()
{
	dracut_args+=(--mount "$(to_mount "$@")") || return 1
}

#handle the case user does not specify the dump target explicitly
handle_default_dump_target()
{
	local _target _mntpoint _fstype _subvol _options

	is_user_configured_dump_target && return

	check_save_path_fs "${OPT[path]}" || return 1

	_save_path=$(get_bind_mount_source "${OPT[path]}")
	_options=$(get_mount_info OPTIONS target "$_save_path" -f)
	_target=$(get_target_from_path "$_save_path")
	_fstype=$(get_fs_type_from_target "$_target")
	if [[ $_fstype == btrfs ]]; then
		_subvol=$(get_btrfs_subvol_from_mntopt "$_options")
	fi

	_mntpoint=$(get_mntpoint_from_target "$_target" "$_subvol")
	OPT[path]=${_save_path##"$_mntpoint"}
	add_mount "$_target" "$_fstype" "$_options" || return 1
	check_size fs "$_target" "$_subvol" || return 1
}

have_compression_in_dracut_args()
{
	[[ "${OPT[dracut_args]}" =~ (^|[[:space:]])--(gzip|bzip2|lzma|xz|lzo|lz4|zstd|no-compress|compress|squash-compressor)([[:space:]]|$) ]]
}

mkdumprd()
{
	local -a dracut_args
	dracut_args+=(--force)
	if [[ -n $debug ]]; then
		dracut_args+=(--debug)
	else
		dracut_args+=(--quiet)
	fi
	dracut_args+=(--hostonly)
	dracut_args+=(--hostonly-cmdline)
	dracut_args+=(--hostonly-i18n)
	dracut_args+=(--hostonly-mode strict)
	dracut_args+=(--hostonly-nics '')
	dracut_args+=(--aggressive-strip)

	if [[ -n ${OPT[extra_modules]} ]]; then
		dracut_args+=(--add-drivers "${OPT[extra_modules]}")
	fi

	case "${OPT[_fstype]}" in
	ext[234] | xfs | btrfs | minix | nfs | virtiofs)
		check_user_configured_target "${OPT[_target]}" "${OPT[_fstype]}" || return 1
		add_mount "${OPT[_target]}" "${OPT[_fstype]}" || return 1
		;;
	raw)
		dd if="${OPT[_target]}" count=1 of=/dev/null > /dev/null 2>&1 || {
			derror "Bad raw disk ${OPT[_target]}"
			return 1
		}
		_praw=$(persistent_policy="by-id" kdump_get_persistent_dev "${OPT[_target]}")
		if [[ -z $_praw ]]; then
			return 1
		fi
		dracut_args+=(--device "$_praw")
		check_size raw "${OPT[_target]}" || return 1
		;;
	ssh)
		if strstr "${OPT[_target]}" "@"; then
			mkdir_save_path_ssh "${OPT[_target]}" || return 1
			check_size ssh "${OPT[_target]}" || return 1
			dracut_args+=(--sshkey "${OPT[sshkey]}")
		else
			derror "Bad ssh dump target ${OPT[_target]}"
			return 1
		fi
		;;
	esac

	if [[ -n ${OPT[core_collector]} ]]; then
		verify_core_collector "${OPT[core_collector]}" || return 1
	fi

	if [[ -n ${OPT[dracut_args]} ]]; then
		# When users specify nfs dumping via dracut_args, kdump-utils won't
		# mount nfs fs beforehand thus nfsv4-related drivers won't be installed
		# because we call dracut with --hostonly-mode strict. So manually install
		# nfsv4-related drivers.
		if [[ $(get_dracut_args_fstype "${OPT[dracut_args]}") == nfs* ]]; then
			dracut_args+=(--add-drivers "nfs_layout_nfsv41_files")
		fi

		while read -r dracut_arg; do
			dracut_args+=("$dracut_arg")
		done <<< "$(echo "${OPT[dracut_args]}" | xargs -n 1 echo)"
	fi

	handle_default_dump_target || return 1

	if ! have_compression_in_dracut_args; then
		# With dracut 104 the 99squash module got split up into 99squash and
		# 95squash-squashfs as well as the new 95squash-erofs. Explicitly set
		# which image type is required otherwise the requested compression
		# algorithm might not be supported.
		if has_dracut_module squash-squashfs && has_command mksquashfs; then
			dracut_args+=(--add squash-squashfs)
			dracut_args+=(--squash-compressor zstd)
		elif has_dracut_module squash-erofs && has_command mkfs.erofs; then
			dracut_args+=(--add squash-erofs)
			dracut_args+=(--squash-compressor lzma)
		elif has_command mksquashfs; then
			# only true for dracut <= 103
			dracut_args+=(--add squash)
			dracut_args+=(--squash-compressor zstd)
		fi
	fi

	# TODO: The below check is not needed anymore with the introduction of
	#       'zz-fadumpinit' module, that isolates fadump's capture kernel initrd,
	#       but still sysroot.mount unit gets generated based on 'root=' kernel
	#       parameter available in fadump case. So, find a way to fix that first
	#       before removing this check.
	if ! is_fadump_capable; then
		# The 2nd rootfs mount stays behind the normal dump target mount,
		# so it doesn't affect the logic of check_dump_fs_modified().
		is_dump_to_rootfs && { add_mount "$(to_dev_name "$(get_root_fs_device)")" || return 1; }

		dracut_args+=(--no-hostonly-default-device)

		# When FIPS mode is enabled, the fips dracut module needs to use
		# /boot/.vmlinuz-${KERNEL}.hmac to verify the integrity of the kernel.
		#
		# If /boot is on a separate partition, the fips module will mount /boot
		# based on the boot= kernel parameter.
		#
		# If /boot is not on a separate partition, the fips dracut module will
		# link /sysroot/boot to /boot. So we need to mount the root partition
		# to /sysroot beforehand.
		if [[ $(cat /proc/sys/crypto/fips_enabled 2> /dev/null) == 1 ]]; then
			_boot_source=$(findmnt -n -o SOURCE --target /boot)
			_disk_persistent=$(get_persistent_dev "$_boot_source")
			if mountpoint -q /boot; then
				dracut_args+=(--add-device "$_disk_persistent")
			else
				add_mount "$_boot_source" || return 1
			fi
		fi
	fi

	# Use kdump managed dracut profile.
	[[ $kdump_dracut_confdir ]] || kdump_dracut_confdir=/lib/kdump/dracut.conf.d
	if [[ "$(dracut --help)" == *--add-confdir* ]] && [[ -d $kdump_dracut_confdir ]]; then
		dracut_args+=("--add-confdir" "$kdump_dracut_confdir")
	else
		dracut_args+=(--add kdumpbase)
		dracut_args+=(--omit "rdma plymouth resume ifcfg earlykdump")
	fi

	export IN_KDUMP=1
	dracut "${dracut_args[@]}" "$@"
	local _ret=$?
	unset IN_KDUMP
	return $_ret
}

mkfadumprd()
{
	local MKFADUMPRD_TMPDIR REBUILD_INITRD TARGET_INITRD FADUMP_INITRD
	local -a _dracut_isolate_args

	MKFADUMPRD_TMPDIR="$KDUMP_TMPDIR/mkfadump"
	mkdir "$MKFADUMPRD_TMPDIR" || {
		derror "mkfadumprd: failed to create mkfadump tmpdir."
		return 1
	}

	# Default boot initramfs to be rebuilt
	REBUILD_INITRD="$1" && shift
	TARGET_INITRD="$1" && shift
	FADUMP_INITRD="$MKFADUMPRD_TMPDIR/fadump.img"

	### First build an initramfs with dump capture capability
	# this file tells the initrd is fadump enabled
	touch "$MKFADUMPRD_TMPDIR/fadump.initramfs"
	ddebug "rebuild fadump initrd: $FADUMP_INITRD"
	# Don't use squash for capture image or default image as it negatively impacts
	# compression ratio and increases the size of the initramfs image.
	# Don't compress the capture image as uncompressed image is needed immediately.
	# Also, early microcode would not be needed here.
	if ! mkdumprd "$FADUMP_INITRD" -i "$MKFADUMPRD_TMPDIR/fadump.initramfs" /etc/fadump.initramfs --omit squash --omit squash-squashfs --omit squash-erofs --no-compress --no-early-microcode; then
		derror "mkfadumprd: failed to build image with dump capture support"
		return 1
	fi

	### Unpack the initramfs having dump capture capability retaining previous file modification time.
	# This helps in saving space by hardlinking identical files.
	mkdir -p "$MKFADUMPRD_TMPDIR/fadumproot"
	if ! cpio -id --preserve-modification-time --quiet -D "$MKFADUMPRD_TMPDIR/fadumproot" < "$FADUMP_INITRD"; then
		derror "mkfadumprd: failed to unpack '$MKFADUMPRD_TMPDIR'"
		return 1
	fi

	### Pack it into the normal boot initramfs with zz-fadumpinit module
	_dracut_isolate_args=(
		--rebuild "$REBUILD_INITRD" --add zz-fadumpinit
		-i "$MKFADUMPRD_TMPDIR/fadumproot" /fadumproot
		-i "$MKFADUMPRD_TMPDIR/fadumproot/usr/lib/dracut/hostonly-kernel-modules.txt"
		/usr/lib/dracut/fadump-kernel-modules.txt
	)

	# Use zstd compression method, if available
	if ! have_compression_in_dracut_args; then
		if has_command zstd; then
			_dracut_isolate_args+=(--compress zstd)
		fi
	fi

	local _debug_dracut=--quiet
	[[ -n $debug ]] && _debug_dracut=--debug
	if ! dracut --force "$_debug_dracut" "${_dracut_isolate_args[@]}" "$@" "$TARGET_INITRD"; then
		derror "mkfadumprd: failed to setup '$TARGET_INITRD' with dump capture capability"
		return 1
	fi
}
