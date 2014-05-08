# These variables and functions are useful in 2nd kernel

. /lib/dracut-lib.sh
. /lib/kdump-lib.sh

KDUMP_PATH="/var/crash"
CORE_COLLECTOR=""
DEFAULT_CORE_COLLECTOR="makedumpfile -l --message-level 1 -d 31"
DMESG_COLLECTOR="/sbin/vmcore-dmesg"
DEFAULT_ACTION="reboot -f"
DATEDIR=`date +%Y.%m.%d-%T`
HOST_IP='127.0.0.1'
DUMP_INSTRUCTION=""
SSH_KEY_LOCATION="/root/.ssh/kdump_id_rsa"
KDUMP_SCRIPT_DIR="/kdumpscripts"
DD_BLKSIZE=512
FINAL_ACTION="reboot -f"
KDUMP_CONF="/etc/kdump.conf"
KDUMP_PRE=""
KDUMP_POST=""
NEWROOT="/sysroot"
MOUNTS=""

get_kdump_confs()
{
    local config_opt config_val

    while read config_opt config_val;
    do
        # remove inline comments after the end of a directive.
        config_val=$(strip_comments $config_val)
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
                        DEFAULT_ACTION="dump_fs $NEWROOT"
                    ;;
                esac
            ;;
        esac
    done < $KDUMP_CONF
}

# dump_fs <mount point| device>
dump_fs()
{

    local _dev=$(findmnt -k -f -n -r -o SOURCE $1)
    local _mp=$(findmnt -k -f -n -r -o TARGET $1)

    echo "kdump: dump target is $_dev"

    if [ -z "$_mp" ]; then
        echo "kdump: error: Dump target $_dev is not mounted."
        return 1
    fi
    MOUNTS="$MOUNTS $_mp"

    # Remove -F in makedumpfile case. We don't want a flat format dump here.
    [[ $CORE_COLLECTOR = *makedumpfile* ]] && CORE_COLLECTOR=`echo $CORE_COLLECTOR | sed -e "s/-F//g"`

    echo "kdump: saving to $_mp/$KDUMP_PATH/$HOST_IP-$DATEDIR/"

    mount -o remount,rw $_mp || return 1
    mkdir -p $_mp/$KDUMP_PATH/$HOST_IP-$DATEDIR || return 1

    save_vmcore_dmesg_fs ${DMESG_COLLECTOR} "$_mp/$KDUMP_PATH/$HOST_IP-$DATEDIR/"

    echo "kdump: saving vmcore"
    $CORE_COLLECTOR /proc/vmcore $_mp/$KDUMP_PATH/$HOST_IP-$DATEDIR/vmcore-incomplete || return 1
    mv $_mp/$KDUMP_PATH/$HOST_IP-$DATEDIR/vmcore-incomplete $_mp/$KDUMP_PATH/$HOST_IP-$DATEDIR/vmcore
    sync

    echo "kdump: saving vmcore complete"
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

do_umount()
{
    if [ -n "$MOUNTS" ]; then
        for mount in $MOUNTS; do
            ismounted $mount && umount -R $mount
        done
    fi
}

do_default_action()
{
    wait_for_loginit
    eval $DEFAULT_ACTION
}

do_final_action()
{
    do_umount
    eval $FINAL_ACTION
}
