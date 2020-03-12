# These variables and functions are useful in 2nd kernel

. /lib/kdump-lib.sh

KDUMP_PATH="/var/crash"
CORE_COLLECTOR=""
DEFAULT_CORE_COLLECTOR="makedumpfile -l --message-level 1 -d 31"
DMESG_COLLECTOR="/sbin/vmcore-dmesg"
FAILURE_ACTION="systemctl reboot -f"
DATEDIR=`date +%Y-%m-%d-%T`
HOST_IP='127.0.0.1'
DUMP_INSTRUCTION=""
SSH_KEY_LOCATION="/root/.ssh/kdump_id_rsa"
KDUMP_SCRIPT_DIR="/kdumpscripts"
DD_BLKSIZE=512
FINAL_ACTION="systemctl reboot -f"
KDUMP_CONF="/etc/kdump.conf"
KDUMP_PRE=""
KDUMP_POST=""
NEWROOT="/sysroot"
OPALCORE="/sys/firmware/opal/mpipl/core"

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
    done <<< "$(read_strip_comments $KDUMP_CONF)"

    if [ -z "$CORE_COLLECTOR" ]; then
        CORE_COLLECTOR="$DEFAULT_CORE_COLLECTOR"
        if is_ssh_dump_target || is_raw_dump_target; then
            CORE_COLLECTOR="$CORE_COLLECTOR -F"
        fi
    fi
}

# dump_fs <mount point| device>
dump_fs()
{
    local _dev=$(findmnt -k -f -n -r -o SOURCE $1)
    local _mp=$(findmnt -k -f -n -r -o TARGET $1)
    local _op=$(findmnt -k -f -n -r -o OPTIONS $1)

    if [ -z "$_mp" ]; then
        _dev=$(findmnt -s -f -n -r -o SOURCE $1)
        _mp=$(findmnt -s -f -n -r -o TARGET $1)
        _op=$(findmnt -s -f -n -r -o OPTIONS $1)

        if [ -n "$_dev" ] && [ -n "$_mp" ]; then
            echo "kdump: dump target $_dev is not mounted, trying to mount..."
            mkdir -p $_mp
            mount -o $_op $_dev $_mp

            if [ $? -ne 0 ]; then
                echo "kdump: mounting failed (mount point: $_mp, option: $_op)"
                return 1
            fi
        else
            echo "kdump: error: Dump target $_dev is not usable"
        fi
    else
        echo "kdump: dump target is $_dev"
    fi

    # Remove -F in makedumpfile case. We don't want a flat format dump here.
    [[ $CORE_COLLECTOR = *makedumpfile* ]] && CORE_COLLECTOR=`echo $CORE_COLLECTOR | sed -e "s/-F//g"`

    local _dump_path=$(echo "$_mp/$KDUMP_PATH/$HOST_IP-$DATEDIR/" | tr -s /)

    echo "kdump: saving to $_dump_path"

    # Only remount to read-write mode if the dump target is mounted read-only.
    if [[ "$_op" = "ro"* ]]; then
       echo "kdump: Mounting Dump target $_dev in rw mode."
       mount -o remount,rw $_dev $_mp || return 1
    fi

    mkdir -p $_dump_path || return 1

    save_vmcore_dmesg_fs ${DMESG_COLLECTOR} "$_dump_path"
    save_opalcore_fs "$_dump_path"

    echo "kdump: saving vmcore"
    $CORE_COLLECTOR /proc/vmcore $_dump_path/vmcore-incomplete || return 1
    mv $_dump_path/vmcore-incomplete $_dump_path/vmcore
    sync

    echo "kdump: saving vmcore complete"

    # improper kernel cmdline can cause the failure of echo, we can ignore this kind of failure
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

        # Make sure file is on disk. There have been instances where later
        # saving vmcore failed and system rebooted without sync and there
        # was no vmcore-dmesg.txt available.
        sync
        echo "kdump: saving vmcore-dmesg.txt complete"
    else
        echo "kdump: saving vmcore-dmesg.txt failed"
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

    echo "kdump: saving opalcore"
    cp $OPALCORE ${_path}/opalcore
    if [ $? -ne 0 ]; then
        echo "kdump: saving opalcore failed"
        return 1
    fi

    sync
    echo "kdump: saving opalcore complete"
    return 0
}

dump_to_rootfs()
{

    echo "Kdump: trying to bring up rootfs device"
    systemctl start dracut-initqueue
    echo "Kdump: waiting for rootfs mount, will timeout after 90 seconds"
    systemctl start sysroot.mount

    dump_fs $NEWROOT
}

kdump_emergency_shell()
{
    echo "PS1=\"kdump:\\\${PWD}# \"" >/etc/profile
    /bin/dracut-emergency
    rm -f /etc/profile
}

do_failure_action()
{
    echo "Kdump: Executing failure action $FAILURE_ACTION"
    eval $FAILURE_ACTION
}

do_final_action()
{
    eval $FINAL_ACTION
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
    done <<< "$(read_strip_comments $KDUMP_CONF)"
}
