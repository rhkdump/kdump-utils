#!/bin/sh
#
# Kdump common variables and functions
#

DEFAULT_PATH="/var/crash/"
FENCE_KDUMP_CONFIG_FILE="/etc/sysconfig/fence_kdump"
FENCE_KDUMP_SEND="/usr/libexec/fence_kdump_send"

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
