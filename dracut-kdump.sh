#!/bin/sh

exec >&2
. /lib/dracut-lib.sh

set -o pipefail
KDUMP_PATH="/var/crash"
CORE_COLLECTOR=""
DEFAULT_CORE_COLLECTOR="makedumpfile -c --message-level 1 -d 31"
DMESG_COLLECTOR="/sbin/vmcore-dmesg"
DEFAULT_ACTION="reboot -f"
DATEDIR=`date +%Y.%m.%d-%T`
HOST_IP='127.0.0.1'
DUMP_INSTRUCTION=""
SSH_KEY_LOCATION="/root/.ssh/kdump_id_rsa"
KDUMP_SCRIPT_DIR="/kdumpscripts"
DD_BLKSIZE=512
FINAL_ACTION="reboot -f"
DUMP_RETVAL=0
conf_file="/etc/kdump.conf"
KDUMP_PRE=""
KDUMP_POST=""
MOUNTS=""

export PATH=$PATH:$KDUMP_SCRIPT_DIR

do_umount()
{
    if [ -n "$MOUNTS" ]; then
        for mount in $MOUNTS; do
            ismounted $mount && umount -R $mount
        done
    fi
}

do_final_action()
{
    do_umount
    eval $FINAL_ACTION
}

do_default_action()
{
    wait_for_loginit
    eval $DEFAULT_ACTION
}

do_kdump_pre()
{
    if [ -n "$KDUMP_PRE" ]; then
        "$KDUMP_PRE"
    fi
}

do_kdump_post()
{
    if [ -n "$KDUMP_POST" ]; then
        "$KDUMP_POST" "$1"
    fi
}

add_dump_code()
{
    DUMP_INSTRUCTION=$1
}

dump_fs()
{
    echo "kdump: dump target is $1"

    local _mp=$(findmnt -k -f -n -r -o TARGET $1)

    if [ -z "$_mp" ]; then
        echo "kdump: error: Dump target $1 is not mounted."
        return 1
    fi
    MOUNTS="$MOUNTS $_mp"

    echo "kdump: saving to $_mp/$KDUMP_PATH/$HOST_IP-$DATEDIR/"

    if [ "$_mp" = "$NEWROOT/" ] || [ "$_mp" = "$NEWROOT" ]
    then
        mount -o remount,rw $_mp || return 1
    fi
    mkdir -p $_mp/$KDUMP_PATH/$HOST_IP-$DATEDIR || return 1

    save_vmcore_dmesg_fs ${DMESG_COLLECTOR} "$_mp/$KDUMP_PATH/$HOST_IP-$DATEDIR/"

    echo "kdump: saving vmcore"
    $CORE_COLLECTOR /proc/vmcore $_mp/$KDUMP_PATH/$HOST_IP-$DATEDIR/vmcore-incomplete || return 1
    mv $_mp/$KDUMP_PATH/$HOST_IP-$DATEDIR/vmcore-incomplete $_mp/$KDUMP_PATH/$HOST_IP-$DATEDIR/vmcore
    sync

    echo "kdump: saving vmcore complete"
    return 0
}

dump_raw()
{
    local _raw=$1

    [ -b "$_raw" ] || return 1

    echo "kdump: saving to raw disk $_raw"

    if ! $(echo -n $CORE_COLLECTOR|grep -q makedumpfile); then
        _src_size=`ls -l /proc/vmcore | cut -d' ' -f5`
        _src_size_mb=$(($_src_size / 1048576))
        monitor_dd_progress $_src_size_mb &
    fi

    echo "kdump: saving vmcore"
    $CORE_COLLECTOR /proc/vmcore | dd of=$_raw bs=$DD_BLKSIZE >> /tmp/dd_progress_file 2>&1 || return 1
    sync

    echo "kdump: saving vmcore complete"
    return 0
}

dump_to_rootfs()
{
    echo "kdump: dump target is root fs"
    echo "kdump: saving to $NEWROOT/$KDUMP_PATH/$HOST_IP-$DATEDIR/"

    MOUNTS="$MOUNTS $NEWROOT"

    #For dumping to rootfs, "-F" need be removed. Surely only available for makedumpfile case.
    [[ $CORE_COLLECTOR = *makedumpfile* ]] && CORE_COLLECTOR=`echo $CORE_COLLECTOR | sed -e s/-F//g`

    mount -o remount,rw $NEWROOT/ || return 1
    mkdir -p $NEWROOT/$KDUMP_PATH/$HOST_IP-$DATEDIR

    save_vmcore_dmesg_fs ${DMESG_COLLECTOR} "$NEWROOT/$KDUMP_PATH/$HOST_IP-$DATEDIR/"

    echo "kdump: saving vmcore"
    $CORE_COLLECTOR /proc/vmcore $NEWROOT/$KDUMP_PATH/$HOST_IP-$DATEDIR/vmcore-incomplete || return 1
    mv $NEWROOT/$KDUMP_PATH/$HOST_IP-$DATEDIR/vmcore-incomplete $NEWROOT/$KDUMP_PATH/$HOST_IP-$DATEDIR/vmcore
    sync

    echo "kdump: saving vmcore complete"
    return 0
}

dump_ssh()
{
    local _opt="-i $1 -o BatchMode=yes -o StrictHostKeyChecking=yes"
    local _dir="$KDUMP_PATH/$HOST_IP-$DATEDIR"
    local _host=$2

    echo "kdump: saving to $_host:$_dir"

    cat /var/lib/random-seed > /dev/urandom
    ssh -q $_opt $_host mkdir -p $_dir || return 1

    save_vmcore_dmesg_ssh ${DMESG_COLLECTOR} ${_dir} "${_opt}" $_host

    echo "kdump: saving vmcore"

    if [ "${CORE_COLLECTOR%%[[:blank:]]*}" = "scp" ]; then
        scp -q $_opt /proc/vmcore "$_host:$_dir/vmcore-incomplete" || return 1
        ssh $_opt $_host "mv $_dir/vmcore-incomplete $_dir/vmcore" || return 1
    else
        $CORE_COLLECTOR /proc/vmcore | ssh $_opt $_host "dd bs=512 of=$_dir/vmcore-incomplete" || return 1
        ssh $_opt $_host "mv $_dir/vmcore-incomplete $_dir/vmcore.flat" || return 1
    fi

    echo "kdump: saving vmcore complete"
    return 0
}

save_vmcore_dmesg_fs() {
    local _dmesg_collector=$1
    local _path=$2

    echo "kdump: saving vmcore-dmesg.txt"
    $_dmesg_collector /proc/vmcore > ${_path}/vmcore-dmesg-incomplete.txt
    _exitcode=$?
    if [ $_exitcode -eq 0 ]; then
        mv ${_path}/vmcore-dmesg-incomplete.txt ${_path}/vmcore-dmesg.txt
        echo "kdump: saving vmcore-dmesg.txt complete"
    else
        echo "kdump: saving vmcore-dmesg.txt failed"
    fi
}

save_vmcore_dmesg_ssh() {
    local _dmesg_collector=$1
    local _path=$2
    local _opts="$3"
    local _location=$4

    echo "kdump: saving vmcore-dmesg.txt"
    $_dmesg_collector /proc/vmcore | ssh $_opts $_location "dd of=$_path/vmcore-dmesg-incomplete.txt"
    _exitcode=$?

    if [ $_exitcode -eq 0 ]; then
        ssh -q $_opts $_location mv $_path/vmcore-dmesg-incomplete.txt $_path/vmcore-dmesg.txt
        echo "kdump: saving vmcore-dmesg.txt complete"
    else
        echo "kdump: saving vmcore-dmesg.txt failed"
    fi
}


is_ssh_dump_target()
{
    grep -q "^ssh[[:blank:]].*@" $conf_file
}

is_nfs_dump_target()
{
    grep -q "^nfs.*:" $conf_file
}

is_raw_dump_target()
{
    grep -q "^raw" $conf_file
}

get_host_ip()
{
    local _host
    if is_nfs_dump_target || is_ssh_dump_target
    then
        kdumpnic=$(getarg kdumpnic=)
        [ -z "$kdumpnic" ] && echo "kdump: failed to get kdumpnic!" && return 1
        _host=`ip addr show dev $kdumpnic|grep 'inet '`
        [ $? -ne 0 ] && echo "kdump: wrong kdumpnic: $kdumpnic" && return 1
        _host="${_host##*inet }"
        _host="${_host%%/*}"
        [ -z "$_host" ] && echo "kdump: wrong kdumpnic: $kdumpnic" && return 1
        HOST_IP=$_host
    fi
    return 0
}

read_kdump_conf()
{
    if [ ! -f "$conf_file" ]; then
        echo "kdump: $conf_file not found"
        return
    fi

    # first get the necessary variables
    while read config_opt config_val;
    do
        case "$config_opt" in
        path)
        KDUMP_PATH="$config_val"
            ;;
        core_collector)
            [ -n "$config_val" ] && CORE_COLLECTOR="$config_val"
            ;;
        sshkey)
            if [ -f "$config_val" ]; then
                SSH_KEY_LOCATION=$config_val
            fi
            ;;
        kdump_pre)
            KDUMP_PRE="$config_val"
            ;;
        kdump_post)
            KDUMP_POST="$config_val"
            ;;
        default)
            case $config_val in
                shell)
                    DEFAULT_ACTION="_emergency_shell kdump"
                    ;;
                reboot)
                    DEFAULT_ACTION="do_umount; reboot -f"
                    ;;
                halt)
                    DEFAULT_ACTION="do_umount; halt -f"
                    ;;
                poweroff)
                    DEFAULT_ACTION="do_umount; poweroff -f"
                    ;;
                dump_to_rootfs)
                    DEFAULT_ACTION="dump_to_rootfs"
                    ;;
            esac
            ;;
        esac
    done < $conf_file

    # rescan for add code for dump target
    while read config_opt config_val;
    do
        case "$config_opt" in
        ext[234]|xfs|btrfs|minix|nfs)
            add_dump_code "dump_fs $config_val"
            ;;
        raw)
            add_dump_code "dump_raw $config_val"
            ;;
        ssh)
            add_dump_code "dump_ssh $SSH_KEY_LOCATION $config_val"
            ;;
        esac
    done < $conf_file
}

read_kdump_conf

if [ -z "$CORE_COLLECTOR" ];then
    CORE_COLLECTOR=$DEFAULT_CORE_COLLECTOR
    if is_ssh_dump_target || is_raw_dump_target; then
        CORE_COLLECTOR="$CORE_COLLECTOR -F"
    fi
fi

get_host_ip
if [ $? -ne 0 ]; then
    echo "kdump: get_host_ip exited with non-zero status!"
    do_default_action
    do_final_action
fi

if [ -z "$DUMP_INSTRUCTION" ]; then
    add_dump_code "dump_to_rootfs"
fi

do_kdump_pre
if [ $? -ne 0 ]; then
    echo "kdump: kdump_pre script exited with non-zero status!"
    do_final_action
fi

$DUMP_INSTRUCTION
DUMP_RETVAL=$?

do_kdump_post $DUMP_RETVAL
if [ $? -ne 0 ]; then
    echo "kdump: kdump_post script exited with non-zero status!"
fi

if [ $DUMP_RETVAL -ne 0 ]; then
    do_default_action
fi

do_final_action
