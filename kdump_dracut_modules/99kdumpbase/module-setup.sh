#!/bin/bash

check() {
    [[ $debug ]] && set -x
    #kdumpctl sets this explicitly
    if [ -z "$IN_KDUMP" ] || [ ! -f /etc/kdump.conf ]
    then
        return 1
    fi
    return 0
}

is_lvm() { [[ $(get_fs_type /dev/block/$1) = LVM2_member ]]; }
is_mdraid() { [[ -d "/sys/dev/block/$1/md" ]]; }
is_btrfs() { get_fs_type /dev/block/$1 | grep -q btrfs; }
is_mpath() {
    [ -e /sys/dev/block/$1/dm/uuid ] || return 1
    [[ $(cat /sys/dev/block/$1/dm/uuid) =~ ^mpath- ]] && return 0
    return 1
}
is_dmraid() { get_fs_type /dev/block/$1 |grep -v linux_raid_member | \
    grep -q _raid_member; }

is_iscsi() (
    [[ -L /sys/dev/block/$1 ]] || return
    cd "$(readlink -f /sys/dev/block/$1)"
    until [[ -d sys || -d iscsi_session ]]; do
        cd ..
    done
    [[ -d iscsi_session ]]
)

pull_dracut_modules() {
    local _dev=$1
    local _is_uuid=`echo $1 | grep UUID`
    local _is_label=`echo $1 | grep LABEL`

    if [ -n "$_is_uuid" -o -n "$_is_label" ]
    then
        _dev=`findfs $1`
    fi

    . $dracutfunctions
    unset MAJOR MINOR
    eval $(udevadm info --query=env --name="$_dev" | egrep '^(MAJOR|MINOR)')
    check_block_and_slaves is_btrfs "$MAJOR:$MINOR" && echo -n "btrfs "
    check_block_and_slaves is_lvm "$MAJOR:$MINOR" && echo -n "lvm "
    check_block_and_slaves is_mdraid "$MAJOR:$MINOR" && echo -n "mdraid "
    check_block_and_slaves is_mpath "$MAJOR:$MINOR" && echo -n "multipath "
    check_block_and_slaves is_iscsi "$MAJOR:$MINOR" && echo -n "iscsi "
    check_block_and_slaves is_dmraid "$MAJOR:$MINOR" && echo -n "dmraid "
    unset MAJOR MINOR
}

depends() {
    local _deps="base shutdown"
    while read config_opt config_val;
    do
        case "$config_opt" in
        ext[234]|xfs|btrfs|minix|raw)
            _deps="$_deps `pull_dracut_modules "$config_val"`"
            ;;
        esac
    done < /etc/kdump.conf
    echo $_deps
    return 0
}

install() {
    inst "/bin/date" "/bin/date"
    inst "/bin/sync" "/bin/sync"
    inst "/sbin/makedumpfile" "/sbin/makedumpfile"
    inst "/etc/kdump.conf" "/etc/kdump.conf"
    inst_hook pre-pivot 01 "$moddir/kdump.sh"
    inst_hook pre-udev 40 "$moddir/block-genrules.sh"
}

