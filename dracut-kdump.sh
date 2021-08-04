#!/bin/sh
#
# The main kdump routine in capture kernel
#

. /lib/dracut-lib.sh
. /lib/kdump-logger.sh
. /lib/kdump-lib-initramfs.sh

#initiate the kdump logger
dlog_init
if [ $? -ne 0 ]; then
    echo "failed to initiate the kdump logger."
    exit 1
fi

KDUMP_PATH="/var/crash"
KDUMP_LOG_FILE="/run/initramfs/kexec-dmesg.log"
CORE_COLLECTOR=""
DEFAULT_CORE_COLLECTOR="makedumpfile -l --message-level 7 -d 31"
DMESG_COLLECTOR="/sbin/vmcore-dmesg"
FAILURE_ACTION="systemctl reboot -f"
DATEDIR=`date +%Y-%m-%d-%T`
HOST_IP='127.0.0.1'
DUMP_INSTRUCTION=""
SSH_KEY_LOCATION="/root/.ssh/kdump_id_rsa"
KDUMP_SCRIPT_DIR="/kdumpscripts"
DD_BLKSIZE=512
FINAL_ACTION="systemctl reboot -f"
KDUMP_PRE=""
KDUMP_POST=""
NEWROOT="/sysroot"
OPALCORE="/sys/firmware/opal/mpipl/core"

set -o pipefail
DUMP_RETVAL=0

export PATH=$PATH:$KDUMP_SCRIPT_DIR

get_kdump_confs()
{
    local config_opt config_val

    while read config_opt config_val;
    do
        # remove inline comments after the end of a directive.
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
            fence_kdump_args)
                FENCE_KDUMP_ARGS="$config_val"
            ;;
            fence_kdump_nodes)
                FENCE_KDUMP_NODES="$config_val"
            ;;
            failure_action|default)
                case $config_val in
                    shell)
                        FAILURE_ACTION="kdump_emergency_shell"
                    ;;
                    reboot)
                        FAILURE_ACTION="systemctl reboot -f && exit"
                    ;;
                    halt)
                        FAILURE_ACTION="halt && exit"
                    ;;
                    poweroff)
                        FAILURE_ACTION="systemctl poweroff -f && exit"
                    ;;
                    dump_to_rootfs)
                        FAILURE_ACTION="dump_to_rootfs"
                    ;;
                esac
            ;;
            final_action)
                case $config_val in
                    reboot)
                        FINAL_ACTION="systemctl reboot -f"
                    ;;
                    halt)
                        FINAL_ACTION="halt"
                    ;;
                    poweroff)
                        FINAL_ACTION="systemctl poweroff -f"
                    ;;
                esac
            ;;
        esac
    done <<< "$(kdump_read_conf)"

    if [ -z "$CORE_COLLECTOR" ]; then
        CORE_COLLECTOR="$DEFAULT_CORE_COLLECTOR"
        if is_ssh_dump_target || is_raw_dump_target; then
            CORE_COLLECTOR="$CORE_COLLECTOR -F"
        fi
    fi
}

# store the kexec kernel log to a file.
save_log()
{
    dmesg -T > $KDUMP_LOG_FILE

    if command -v journalctl > /dev/null; then
        journalctl -ab >> $KDUMP_LOG_FILE
    fi
    chmod 600 $KDUMP_LOG_FILE
}

# dump_fs <mount point>
dump_fs()
{
    local _exitcode
    local _mp=$1
    local _op=$(get_mount_info OPTIONS target $_mp -f)
    ddebug "dump_fs _mp=$_mp _opts=$_op"

    if ! is_mounted "$_mp"; then
        dinfo "dump path \"$_mp\" is not mounted, trying to mount..."
        mount --target $_mp
        if [ $? -ne 0 ]; then
            derror "failed to dump to \"$_mp\", it's not a mount point!"
            return 1
        fi
    fi

    # Remove -F in makedumpfile case. We don't want a flat format dump here.
    [[ $CORE_COLLECTOR = *makedumpfile* ]] && CORE_COLLECTOR=`echo $CORE_COLLECTOR | sed -e "s/-F//g"`

    local _dump_path=$(echo "$_mp/$KDUMP_PATH/$HOST_IP-$DATEDIR/" | tr -s /)

    dinfo "saving to $_dump_path"

    # Only remount to read-write mode if the dump target is mounted read-only.
    if [[ "$_op" = "ro"* ]]; then
       dinfo "Remounting the dump target in rw mode."
       mount -o remount,rw $_mp || return 1
    fi

    mkdir -p $_dump_path || return 1

    save_vmcore_dmesg_fs ${DMESG_COLLECTOR} "$_dump_path"
    save_opalcore_fs "$_dump_path"

    dinfo "saving vmcore"
    $CORE_COLLECTOR /proc/vmcore $_dump_path/vmcore-incomplete
    _exitcode=$?
    if [ $_exitcode -eq 0 ]; then
        mv $_dump_path/vmcore-incomplete $_dump_path/vmcore
        sync
        dinfo "saving vmcore complete"
    else
        derror "saving vmcore failed, _exitcode:$_exitcode"
    fi

    dinfo "saving the $KDUMP_LOG_FILE to $_dump_path/"
    save_log
    mv $KDUMP_LOG_FILE $_dump_path/
    if [ $_exitcode -ne 0 ]; then
        return 1
    fi

    # improper kernel cmdline can cause the failure of echo, we can ignore this kind of failure
    return 0
}

save_vmcore_dmesg_fs() {
    local _dmesg_collector=$1
    local _path=$2

    dinfo "saving vmcore-dmesg.txt to ${_path}"
    $_dmesg_collector /proc/vmcore > ${_path}/vmcore-dmesg-incomplete.txt
    _exitcode=$?
    if [ $_exitcode -eq 0 ]; then
        mv ${_path}/vmcore-dmesg-incomplete.txt ${_path}/vmcore-dmesg.txt
        chmod 600 ${_path}/vmcore-dmesg.txt

        # Make sure file is on disk. There have been instances where later
        # saving vmcore failed and system rebooted without sync and there
        # was no vmcore-dmesg.txt available.
        sync
        dinfo "saving vmcore-dmesg.txt complete"
    else
        if [ -f ${_path}/vmcore-dmesg-incomplete.txt ]; then
            chmod 600 ${_path}/vmcore-dmesg-incomplete.txt
        fi
        derror "saving vmcore-dmesg.txt failed"
    fi
}

save_opalcore_fs() {
    local _path=$1

    if [ ! -f $OPALCORE ]; then
        # Check if we are on an old kernel that uses a different path
        if [ -f /sys/firmware/opal/core ]; then
            OPALCORE="/sys/firmware/opal/core"
        else
            return 0
        fi
    fi

    dinfo "saving opalcore:$OPALCORE to ${_path}/opalcore"
    cp $OPALCORE ${_path}/opalcore
    if [ $? -ne 0 ]; then
        derror "saving opalcore failed"
        return 1
    fi

    sync
    dinfo "saving opalcore complete"
    return 0
}

dump_to_rootfs()
{

    if [[ $(systemctl status dracut-initqueue | sed -n "s/^\s*Active: \(\S*\)\s.*$/\1/p") == "inactive" ]]; then
        dinfo "Trying to bring up initqueue for rootfs mount"
        systemctl start dracut-initqueue
    fi

    dinfo "Clean up dead systemd services"
    systemctl cancel
    dinfo "Waiting for rootfs mount, will timeout after 90 seconds"
    systemctl start --no-block sysroot.mount

    _loop=0
    while [ $_loop -lt 90 ] && ! is_mounted /sysroot; do
        sleep 1
        _loop=$((_loop + 1))
    done

    if ! is_mounted /sysroot; then
        derror "Failed to mount rootfs"
        return
    fi

    ddebug "NEWROOT=$NEWROOT"
    dump_fs $NEWROOT
}

kdump_emergency_shell()
{
    ddebug "Switching to kdump emergency shell..."

    [ -f /etc/profile ] && . /etc/profile
    export PS1='kdump:${PWD}# '

    . /lib/dracut-lib.sh
    if [ -f /dracut-state.sh ]; then
        . /dracut-state.sh 2>/dev/null
    fi

    source_conf /etc/conf.d

    type plymouth >/dev/null 2>&1 && plymouth quit

    source_hook "emergency"
    while read _tty rest; do
        (
        echo
        echo
        echo 'Entering kdump emergency mode.'
        echo 'Type "journalctl" to view system logs.'
        echo 'Type "rdsosreport" to generate a sosreport, you can then'
        echo 'save it elsewhere and attach it to a bug report.'
        echo
        echo
        ) > /dev/$_tty
    done < /proc/consoles
    sh -i -l
    /bin/rm -f -- /.console_lock
}

do_failure_action()
{
    dinfo "Executing failure action $FAILURE_ACTION"
    eval $FAILURE_ACTION
}

do_final_action()
{
    dinfo "Executing final action $FINAL_ACTION"
    eval $FINAL_ACTION
}
do_dump()
{
    local _ret

    eval $DUMP_INSTRUCTION
    _ret=$?

    if [ $_ret -ne 0 ]; then
        derror "saving vmcore failed"
    fi

    return $_ret
}

do_kdump_pre()
{
    local _ret

    if [ -n "$KDUMP_PRE" ]; then
        "$KDUMP_PRE"
        _ret=$?
        if [ $_ret -ne 0 ]; then
            derror "$KDUMP_PRE exited with $_ret status"
            return $_ret
        fi
    fi

    # if any script fails, it just raises warning and continues
    if [ -d /etc/kdump/pre.d ]; then
        for file in /etc/kdump/pre.d/*; do
            "$file"
            _ret=$?
            if [ $_ret -ne 0 ]; then
                derror "$file exited with $_ret status"
            fi
        done
    fi
    return 0
}

do_kdump_post()
{
    local _ret

    if [ -d /etc/kdump/post.d ]; then
        for file in /etc/kdump/post.d/*; do
            "$file" "$1"
            _ret=$?
            if [ $_ret -ne 0 ]; then
                derror "$file exited with $_ret status"
            fi
        done
    fi

    if [ -n "$KDUMP_POST" ]; then
        "$KDUMP_POST" "$1"
        _ret=$?
        if [ $_ret -ne 0 ]; then
            derror "$KDUMP_POST exited with $_ret status"
        fi
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

    dinfo "saving to raw disk $_raw"

    if ! $(echo -n $CORE_COLLECTOR|grep -q makedumpfile); then
        _src_size=`ls -l /proc/vmcore | cut -d' ' -f5`
        _src_size_mb=$(($_src_size / 1048576))
        monitor_dd_progress $_src_size_mb &
    fi

    dinfo "saving vmcore"
    $CORE_COLLECTOR /proc/vmcore | dd of=$_raw bs=$DD_BLKSIZE >> /tmp/dd_progress_file 2>&1 || return 1
    sync

    dinfo "saving vmcore complete"
    return 0
}

dump_ssh()
{
    local _ret=0
    local _exitcode=0 _exitcode2=0
    local _opt="-i $1 -o BatchMode=yes -o StrictHostKeyChecking=yes"
    local _dir="$KDUMP_PATH/$HOST_IP-$DATEDIR"
    local _host=$2
    local _vmcore="vmcore"
    local _ipv6_addr="" _username=""

    dinfo "saving to $_host:$_dir"

    cat /var/lib/random-seed > /dev/urandom
    ssh -q $_opt $_host mkdir -p $_dir || return 1

    save_vmcore_dmesg_ssh ${DMESG_COLLECTOR} ${_dir} "${_opt}" $_host
    save_opalcore_ssh ${_dir} "${_opt}" $_host

    dinfo "saving vmcore"

    if is_ipv6_address "$_host"; then
        _username=${_host%@*}
	_ipv6_addr="[${_host#*@}]"
    fi

    if [ "${CORE_COLLECTOR%%[[:blank:]]*}" = "scp" ]; then
        if [ -n "$_username" ] && [ -n "$_ipv6_addr" ]; then
            scp -q $_opt /proc/vmcore "$_username@$_ipv6_addr:$_dir/vmcore-incomplete"
        else
            scp -q $_opt /proc/vmcore "$_host:$_dir/vmcore-incomplete"
        fi
        _exitcode=$?
    else
        $CORE_COLLECTOR /proc/vmcore | ssh $_opt $_host "umask 0077 && dd bs=512 of=$_dir/vmcore-incomplete"
        _exitcode=$?
        _vmcore="vmcore.flat"
    fi

    if [ $_exitcode -eq 0 ]; then
        ssh $_opt $_host "mv $_dir/vmcore-incomplete $_dir/$_vmcore"
        _exitcode2=$?
        if [ $_exitcode2 -ne 0 ]; then
            derror "moving vmcore failed, _exitcode:$_exitcode2"
        else
            dinfo "saving vmcore complete"
        fi
    else
        derror "saving vmcore failed, _exitcode:$_exitcode"
    fi

    dinfo "saving the $KDUMP_LOG_FILE to $_host:$_dir/"
    save_log
    if [ -n "$_username" ] && [ -n "$_ipv6_addr" ]; then
        scp -q $_opt $KDUMP_LOG_FILE "$_username@$_ipv6_addr:$_dir/"
    else
        scp -q $_opt $KDUMP_LOG_FILE "$_host:$_dir/"
    fi
    _ret=$?
    if [ $_ret -ne 0 ]; then
        derror "saving log file failed, _exitcode:$_ret"
    fi

    if [ $_exitcode -ne 0 ] || [ $_exitcode2 -ne 0 ];then
        return 1
    fi

    return 0
}

save_opalcore_ssh() {
    local _path=$1
    local _opts="$2"
    local _location=$3
    local _user_name="" _ipv6addr=""

    ddebug "_path=$_path _opts=$_opts _location=$_location"

    if [ ! -f $OPALCORE ]; then
        # Check if we are on an old kernel that uses a different path
        if [ -f /sys/firmware/opal/core ]; then
            OPALCORE="/sys/firmware/opal/core"
        else
            return 0
        fi
    fi

    if is_ipv6_address "$_host"; then
        _user_name=${_location%@*}
        _ipv6addr="[${_location#*@}]"
    fi

    dinfo "saving opalcore:$OPALCORE to $_location:$_path"

    if [ -n "$_user_name" ] && [ -n "$_ipv6addr" ]; then
        scp $_opts $OPALCORE $_user_name@$_ipv6addr:$_path/opalcore-incomplete
    else
        scp $_opts $OPALCORE $_location:$_path/opalcore-incomplete
    fi
    if [ $? -ne 0 ]; then
        derror "saving opalcore failed"
       return 1
    fi

    ssh $_opts $_location mv $_path/opalcore-incomplete $_path/opalcore
    dinfo "saving opalcore complete"
    return 0
}

save_vmcore_dmesg_ssh() {
    local _dmesg_collector=$1
    local _path=$2
    local _opts="$3"
    local _location=$4

    dinfo "saving vmcore-dmesg.txt to $_location:$_path"
    $_dmesg_collector /proc/vmcore | ssh $_opts $_location "umask 0077 && dd of=$_path/vmcore-dmesg-incomplete.txt"
    _exitcode=$?

    if [ $_exitcode -eq 0 ]; then
        ssh -q $_opts $_location mv $_path/vmcore-dmesg-incomplete.txt $_path/vmcore-dmesg.txt
        dinfo "saving vmcore-dmesg.txt complete"
    else
        derror "saving vmcore-dmesg.txt failed"
    fi
}

get_host_ip()
{
    local _host
    if is_nfs_dump_target || is_ssh_dump_target
    then
        kdumpnic=$(getarg kdumpnic=)
        [ -z "$kdumpnic" ] && derror "failed to get kdumpnic!" && return 1
        _host=`ip addr show dev $kdumpnic|grep '[ ]*inet'`
        [ $? -ne 0 ] && derror "wrong kdumpnic: $kdumpnic" && return 1
        _host=`echo $_host | head -n 1 | cut -d' ' -f2`
        _host="${_host%%/*}"
        [ -z "$_host" ] && derror "wrong kdumpnic: $kdumpnic" && return 1
        HOST_IP=$_host
    fi
    return 0
}

read_kdump_confs()
{
    if [ ! -f "$KDUMP_CONFIG_FILE" ]; then
        derror "$KDUMP_CONFIG_FILE not found"
        return
    fi

    get_kdump_confs

    # rescan for add code for dump target
    while read config_opt config_val;
    do
        # remove inline comments after the end of a directive.
        case "$config_opt" in
        dracut_args)
            config_val=$(get_dracut_args_target "$config_val")
            if [ -n "$config_val" ]; then
                config_val=$(get_mntpoint_from_target "$config_val")
                add_dump_code "dump_fs $config_val"
            fi
            ;;
        ext[234]|xfs|btrfs|minix|nfs)
            config_val=$(get_mntpoint_from_target "$config_val")
            add_dump_code "dump_fs $config_val"
            ;;
        raw)
            add_dump_code "dump_raw $config_val"
            ;;
        ssh)
            add_dump_code "dump_ssh $SSH_KEY_LOCATION $config_val"
            ;;
        esac
    done <<< "$(kdump_read_conf)"
}

fence_kdump_notify()
{
    if [ -n "$FENCE_KDUMP_NODES" ]; then
        $FENCE_KDUMP_SEND $FENCE_KDUMP_ARGS $FENCE_KDUMP_NODES &
    fi
}

if [ "$1" = "--error-handler" ]; then
    get_kdump_confs
    do_failure_action
    do_final_action

    exit $?
fi

# continue here only if we have to save dump.
if [ -f /etc/fadump.initramfs ] && [ ! -f /proc/device-tree/rtas/ibm,kernel-dump ] && [ ! -f /proc/device-tree/ibm,opal/dump/mpipl-boot ]; then
    exit 0
fi

read_kdump_confs
fence_kdump_notify

get_host_ip
if [ $? -ne 0 ]; then
    derror "get_host_ip exited with non-zero status!"
    exit 1
fi

if [ -z "$DUMP_INSTRUCTION" ]; then
    add_dump_code "dump_fs $NEWROOT"
fi

do_kdump_pre
if [ $? -ne 0 ]; then
    derror "kdump_pre script exited with non-zero status!"
    do_final_action
    # During systemd service to reboot the machine, stop this shell script running
    exit 1
fi
make_trace_mem "kdump saving vmcore" '1:shortmem' '2+:mem' '3+:slab'
do_dump
DUMP_RETVAL=$?

do_kdump_post $DUMP_RETVAL
if [ $? -ne 0 ]; then
    derror "kdump_post script exited with non-zero status!"
fi

if [ $DUMP_RETVAL -ne 0 ]; then
    exit 1
fi

do_final_action
