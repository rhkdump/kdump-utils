# These variables and functions are useful in 2nd kernel

. /lib/kdump-lib.sh
. /lib/kdump-logger.sh

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
KDUMP_CONF="/etc/kdump.conf"
KDUMP_PRE=""
KDUMP_POST=""
NEWROOT="/sysroot"
OPALCORE="/sys/firmware/opal/mpipl/core"

#initiate the kdump logger
dlog_init
if [ $? -ne 0 ]; then
    echo "failed to initiate the kdump logger."
    exit 1
fi

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

    dinfo "Trying to bring up rootfs device"
    systemctl start dracut-initqueue
    dinfo "Waiting for rootfs mount, will timeout after 90 seconds"
    systemctl start sysroot.mount

    ddebug "NEWROOT=$NEWROOT"

    dump_fs $NEWROOT
}

kdump_emergency_shell()
{
    echo "PS1=\"kdump:\\\${PWD}# \"" >/etc/profile
    ddebug "Switching to dracut emergency..."
    /bin/dracut-emergency
    rm -f /etc/profile
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
