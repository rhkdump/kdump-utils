#!/bin/sh

# continue here only if we have to save dump.
if [ -f /etc/fadump.initramfs ] && [ ! -f /proc/device-tree/rtas/ibm,kernel-dump ]; then
	exit 0
fi

exec &> /dev/console
. /lib/dracut-lib.sh
. /lib/kdump-lib-initramfs.sh

set -o pipefail
DUMP_RETVAL=0

export PATH=$PATH:$KDUMP_SCRIPT_DIR

do_dump()
{
    local _ret

    eval $DUMP_INSTRUCTION
    _ret=$?

    if [ $_ret -ne 0 ]; then
        echo "kdump: saving vmcore failed"
    fi

    return $_ret
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

get_host_ip()
{
    local _host
    if is_nfs_dump_target || is_ssh_dump_target
    then
        kdumpnic=$(getarg kdumpnic=)
        [ -z "$kdumpnic" ] && echo "kdump: failed to get kdumpnic!" && return 1
        _host=`ip addr show dev $kdumpnic|grep '[ ]*inet'`
        [ $? -ne 0 ] && echo "kdump: wrong kdumpnic: $kdumpnic" && return 1
        _host=`echo $_host | head -n 1 | cut -d' ' -f2`
        _host="${_host%%/*}"
        [ -z "$_host" ] && echo "kdump: wrong kdumpnic: $kdumpnic" && return 1
        HOST_IP=$_host
    fi
    return 0
}

read_kdump_conf()
{
    if [ ! -f "$KDUMP_CONF" ]; then
        echo "kdump: $KDUMP_CONF not found"
        return
    fi

    get_kdump_confs

    # rescan for add code for dump target
    while read config_opt config_val;
    do
        # remove inline comments after the end of a directive.
        config_val=$(strip_comments $config_val)
        case "$config_opt" in
        dracut_args)
            config_val=$(get_dracut_args_target "$config_val")
            [ -n "$config_val" ] && add_dump_code "dump_fs $config_val"
            ;;
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
    done < $KDUMP_CONF
}

fence_kdump_notify()
{
    if [ -n "$FENCE_KDUMP_NODES" ]; then
        $FENCE_KDUMP_SEND $FENCE_KDUMP_ARGS $FENCE_KDUMP_NODES &
    fi
}

read_kdump_conf
fence_kdump_notify

get_host_ip
if [ $? -ne 0 ]; then
    echo "kdump: get_host_ip exited with non-zero status!"
    exit 1
fi

if [ -z "$DUMP_INSTRUCTION" ]; then
    add_dump_code "dump_fs $NEWROOT"
fi

do_kdump_pre
if [ $? -ne 0 ]; then
    echo "kdump: kdump_pre script exited with non-zero status!"
    do_final_action
fi
make_trace_mem "kdump saving vmcore" '1:shortmem' '2+:mem' '3+:slab'
do_dump
DUMP_RETVAL=$?

do_kdump_post $DUMP_RETVAL
if [ $? -ne 0 ]; then
    echo "kdump: kdump_post script exited with non-zero status!"
fi

if [ $DUMP_RETVAL -ne 0 ]; then
    exit 1
fi

do_final_action
