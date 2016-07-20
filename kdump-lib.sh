#!/bin/sh
#
# Kdump common variables and functions
#

DEFAULT_PATH="/var/crash/"
FENCE_KDUMP_CONFIG_FILE="/etc/sysconfig/fence_kdump"
FENCE_KDUMP_SEND="/usr/libexec/fence_kdump_send"

perror_exit() {
    echo $@ >&2
    exit 1
}

perror() {
    echo $@ >&2
}

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

is_fs_type_nfs()
{
    local _fstype=$1
    [ $_fstype = "nfs" ] || [ $_fstype = "nfs4" ] && return 0
    return 1
}

is_fs_dump_target()
{
    egrep -q "^ext[234]|^xfs|^btrfs|^minix" /etc/kdump.conf
}

is_user_configured_dump_target()
{
    return $(is_ssh_dump_target || is_nfs_dump_target || is_raw_dump_target || is_fs_dump_target)
}

strip_comments()
{
    echo $@ | sed -e 's/\(.*\)#.*/\1/'
}

# Check if fence kdump is configured in Pacemaker cluster
is_pcs_fence_kdump()
{
    # no pcs or fence_kdump_send executables installed?
    type -P pcs > /dev/null || return 1
    [ -x $FENCE_KDUMP_SEND ] || return 1

    # fence kdump not configured?
    (pcs cluster cib | grep -q 'type="fence_kdump"') &> /dev/null || return 1
}

# Check if fence_kdump is configured using kdump options
is_generic_fence_kdump()
{
    [ -x $FENCE_KDUMP_SEND ] || return 1

    grep -q "^fence_kdump_nodes" /etc/kdump.conf
}

to_dev_name() {
    local dev="${1//\"/}"

    case "$dev" in
    UUID=*)
        dev=`blkid -U "${dev#UUID=}"`
        ;;
    LABEL=*)
        dev=`blkid -L "${dev#LABEL=}"`
        ;;
    esac
    echo $dev
}

kdump_get_persistent_dev() {
    local i _tmp _dev _lookup_dirs

    _dev=$(udevadm info --query=name --name="$1" 2>/dev/null)
    [ -z "$_dev" ] && {
        perror_exit "Kernel dev name of $1 is not found."
    }

    if [[ $2 = "raw" ]];then
	_lookup_dirs="/dev/mapper/* /dev/disk/by-id/*"
    else
	_lookup_dirs="/dev/mapper/* /dev/disk/by-uuid/* /dev/disk/by-id/*"
    fi

    for i in $_lookup_dirs; do
        _tmp=$(udevadm info --query=name --name="$i" 2>/dev/null)
        if [ "$_tmp" = "$_dev" ]; then
            echo $i
            return
        fi
    done

    perror "WARNING: Persistent device name of $1 not found. Using $1 as dump target name"
    echo $1
}

get_user_configured_dump_disk()
{
    local _target

    if is_ssh_dump_target || is_nfs_dump_target; then
        return
    fi

    _target=$(egrep "^ext[234]|^xfs|^btrfs|^minix|^raw" /etc/kdump.conf 2>/dev/null |awk '{print $2}')
    [ -n "$_target" ] && echo $_target

    return
}

get_root_fs_device()
{
    local _target
    _target=$(findmnt -k -f -n -o SOURCE /)
    [ -n "$_target" ] && echo $_target

    return
}

# findmnt uses the option "-v, --nofsroot" to exclusive the [/dir]
# in the SOURCE column for bind-mounts, then if $_mntpoint equals to
# $_mntpoint_nofsroot, the mountpoint is not bind mounted directory.
is_bind_mount()
{
    local _mntpoint=$(findmnt $1 | tail -n 1 | awk '{print $2}')
    local _mntpoint_nofsroot=$(findmnt -v $1 | tail -n 1 | awk '{print $2}')

    if [[ $_mntpoint = $_mntpoint_nofsroot ]]; then
        return 1
    else
        return 0
    fi
}

# Below is just an example for mount info
# /dev/mapper/atomicos-root[/ostree/deploy/rhel-atomic-host/var], if the
# directory is bind mounted. The former part represents the device path, rest
# part is the bind mounted directory which quotes by bracket "[]".
get_bind_mount_directory()
{
    local _mntpoint=$(findmnt $1 | tail -n 1 | awk '{print $2}')
    local _mntpoint_nofsroot=$(findmnt -v $1 | tail -n 1 | awk '{print $2}')

    _mntpoint=${_mntpoint#*$_mntpoint_nofsroot}

    _mntpoint=${_mntpoint#[}
    _mntpoint=${_mntpoint%]}

    echo $_mntpoint
}

get_mntpoint_from_path() 
{
    echo $(df $1 | tail -1 |  awk '{print $NF}')
}

get_target_from_path()
{
    echo $(df $1 | tail -1 |  awk '{print $1}')
}

get_fs_type_from_target() 
{
    echo $(findmnt -k -f -n -r -o FSTYPE $1)
}

# input: device path
# output: the general mount point
# find the general mount point, not the bind mounted point in atomic
# As general system, Use the previous code
#
# ERROR and EXIT:
# the device can be umounted the general mount point, if one of the mount point is bind mounted
# For example:
# mount /dev/sda /mnt/
# mount -o bind /mnt/var /var
# umount /mnt
get_mntpoint_from_target()
{
    if is_atomic; then
        for _mnt in $(findmnt -k -n -r -o TARGET $1)
        do
            if ! is_bind_mount $_mnt; then
                echo $_mnt
                return
            fi
        done

        echo "Mount $1 firstly, without the bind mode" >&2
        exit 1
    else
        echo $(findmnt -k -f -n -r -o TARGET $1)
    fi
}

# get_option_value <option_name>
# retrieves value of option defined in kdump.conf
get_option_value() {
    echo $(strip_comments `grep "^$1[[:space:]]\+" /etc/kdump.conf | tail -1 | cut -d\  -f2-`)
}

#This function compose a absolute path with the mount
#point and the relative $SAVE_PATH.
#target is passed in as argument, could be UUID, LABEL,
#block device or even nfs server export of the form of
#"my.server.com:/tmp/export"?
#And possibly this could be used for both default case
#as well as when dump taret is specified. When dump
#target is not specified, then $target would be null.
make_absolute_save_path()
{
    local _target=$1
    local _mnt

    [ -n $_target ] && _mnt=$(get_mntpoint_from_target $1)
    _mnt="${_mnt}/$SAVE_PATH"

    # strip the duplicated "/"
    echo "$_mnt" | tr -s /
}

check_save_path_fs()
{
    local _path=$1

    if [ ! -d $_path ]; then
        perror_exit "Dump path $_path does not exist."
    fi
}

is_atomic()
{
    grep -q "ostree" /proc/cmdline
}

is_ipv6_address()
{
    echo $1 | grep -q ":"
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
    echo $_config_val
}

is_hostname()
{
    local _hostname=`echo $1 | grep ":"`

    if [ -n "$_hostname" ]; then
        return 1
    fi
    echo $1 | grep -q "[a-zA-Z]"
}

# Copied from "/etc/sysconfig/network-scripts/network-functions"
get_hwaddr()
{
    if [ -f "/sys/class/net/${1}/address" ]; then
        awk '{ print toupper($0) }' < /sys/class/net/${1}/address
    elif [ -d "/sys/class/net/${1}" ]; then
       LC_ALL= LANG= ip -o link show ${1} 2>/dev/null | \
            awk '{ print toupper(gensub(/.*link\/[^ ]* ([[:alnum:]:]*).*/,
                                        "\\1", 1)); }'
    fi
}

get_ifcfg_by_device()
{
    grep -E -i -l "^[[:space:]]*DEVICE=\"*${1}\"*[[:space:]]*$" \
         /etc/sysconfig/network-scripts/ifcfg-* 2>/dev/null | head -1
}

get_ifcfg_by_hwaddr()
{
    grep -E -i -l "^[[:space:]]*HWADDR=\"*${1}\"*[[:space:]]*$" \
         /etc/sysconfig/network-scripts/ifcfg-* 2>/dev/null | head -1
}

get_ifcfg_by_uuid()
{
    grep -E -i -l "^[[:space:]]*UUID=\"*${1}\"*[[:space:]]*$" \
         /etc/sysconfig/network-scripts/ifcfg-* 2>/dev/null | head -1
}

get_ifcfg_by_name()
{
    grep -E -i -l "^[[:space:]]*NAME=\"*${1}\"*[[:space:]]*$" \
         /etc/sysconfig/network-scripts/ifcfg-* 2>/dev/null | head -1
}

is_nm_running()
{
    [ "$(LANG=C nmcli -t --fields running general status 2>/dev/null)" = "running" ]
}

is_nm_handling()
{
    LANG=C nmcli -t --fields device,state  dev status 2>/dev/null \
          | grep -q "^\(${1}:connected\)\|\(${1}:connecting.*\)$"
}

# $1: netdev name
get_ifcfg_nmcli()
{
    local nm_uuid nm_name
    local ifcfg_file

    # Get the active nmcli config name of $1
    if is_nm_running && is_nm_handling "${1}" ; then
        # The configuration "uuid" and "name" generated by nm is wrote to
        # the ifcfg file as "UUID=<nm_uuid>" and "NAME=<nm_name>".
        nm_uuid=$(LANG=C nmcli -t --fields uuid,device c show --active 2>/dev/null \
                  | grep "${1}" | head -1 | cut -d':' -f1)
        nm_name=$(LANG=C nmcli -t --fields name,device c show --active 2>/dev/null \
                  | grep "${1}" | head -1 | cut -d':' -f1)
        ifcfg_file=$(get_ifcfg_by_uuid "${nm_uuid}")
        [ -z "${ifcfg_file}" ] && ifcfg_file=$(get_ifcfg_by_name "${nm_name}")
    fi

    echo -n "${ifcfg_file}"
}

# $1: netdev name
get_ifcfg_legacy()
{
    local ifcfg_file

    ifcfg_file="/etc/sysconfig/network-scripts/ifcfg-${1}"
    [ -f "${ifcfg_file}" ] && echo -n "${ifcfg_file}" && return

    ifcfg_file=$(get_ifcfg_by_name "${1}")
    [ -f "${ifcfg_file}" ] && echo -n "${ifcfg_file}" && return

    local hwaddr=$(get_hwaddr "${1}")
    if [ -n "$hwaddr" ]; then
        ifcfg_file=$(get_ifcfg_by_hwaddr "${hwaddr}")
        [ -f "${ifcfg_file}" ] && echo -n "${ifcfg_file}" && return
    fi

    ifcfg_file=$(get_ifcfg_by_device "${1}")

    echo -n "${ifcfg_file}"
}

# $1: netdev name
# Return the ifcfg file whole name(including the path) of $1 if any.
get_ifcfg_filename() {
    local ifcfg_file

    ifcfg_file=$(get_ifcfg_nmcli "${1}")
    if [ -z "${ifcfg_file}" ]; then
        ifcfg_file=$(get_ifcfg_legacy "${1}")
    fi

    echo -n "${ifcfg_file}"
}

# returns 0 when omission of watchdog module is desired in dracut_args
# returns 1 otherwise
is_wdt_mod_omitted() {
	local dracut_args
	local ret=1

	dracut_args=$(grep  "^dracut_args" /etc/kdump.conf)
	[[ -z $dracut_args ]] && return $ret

	eval set -- $dracut_args
	while :; do
		[[ -z $1 ]] && break
		case $1 in
			-o|--omit)
				echo $2 | grep -qw "watchdog"
				[[ $? == 0 ]] && ret=0
				break
		esac
		shift
	done

	return $ret
}
