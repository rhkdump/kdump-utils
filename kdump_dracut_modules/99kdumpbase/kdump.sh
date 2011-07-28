#!/bin/sh

. /lib/dracut-lib.sh

set -x
KDUMP_PATH="/var/crash"
CORE_COLLECTOR="makedumpfile -d 31 -c"
DEFAULT_ACTION="reboot -f"
DATEDIR=`date +%d.%m.%y-%T`
DUMP_INSTRUCTION=""

do_default_action()
{
    wait_for_loginit
    $DEFAULT_ACTION
}

add_dump_instruction()
{
    if [ -z "$DUMP_INSTRUCTION" ]
    then
        DUMP_INSTRUCTION="$1"
    else
        DUMP_INSTRUCTION="$DUMP_INSTRUCTION && $1"
    fi
}

dump_rootfs()
{
    mount -o remount,rw $NEWROOT/ || return 1
    mkdir -p $NEWROOT/$KDUMP_PATH/$DATEDIR
    $CORE_COLLECTOR /proc/vmcore $NEWROOT/$KDUMP_PATH/$DATEDIR/vmcore || return 1
    sync
    return 0
}

dump_nfs()
{
    mount -o nolock -o tcp -t nfs $1 $NEWROOT/mnt/
    mkdir -p $NEWROOT/mnt/$KDUMP_PATH/$DATEDIR || return 1
    $CORE_COLLECTOR /proc/vmcore $NEWROOT/mnt/$KDUMP_PATH/$DATEDIR/vmcore || return 1
    umount $NEWROOT/mnt/ || return 1
    return 0
}

dump_ssh()
{
    ssh -q -o BatchMode=yes -o StrictHostKeyChecking=yes $1 mkdir -p $KDUMP_PATH/$DATEDIR || return 1
    scp -q -o BatchMode=yes -o StrictHostKeyChecking=yes /proc/vmcore "$1:$KDUMP_PATH/$DATEDIR"  || return 1
    return 0
}

read_kdump_conf()
{
    local conf_file="/etc/kdump.conf"
    if [ -f "$conf_file" ]; then
        while read config_opt config_val;
        do
	    case "$config_opt" in
	    path)
                KDUMP_PATH="$config_val"
	        ;;
            core_collector)
		CORE_COLLECTOR="$config_val"
                ;;
            net)
                if [ -n "$(echo $config_val | grep @)" ]
                then
                    add_dump_instruction "dump_ssh $config_val || do_default_action"
                else
                    add_dump_instruction "dump_nfs $config_val || do_default_action"
                fi
                ;;
            default)
                case $config_val in
                    shell)
                        DEFAULT_ACTION="sh -i -l"
                        ;;
                    reboot)
                        DEFAULT_ACTION="reboot -f"
                        ;;
                    halt)
                        DEFAULT_ACTION="halt -f"
                        ;;
                    poweroff)
                        DEFAULT_ACTION="poweroff -f"
                        ;;
                esac
	        ;;
	    esac
        done < $conf_file
    fi
}

read_kdump_conf

if [ -n "$DUMP_INSTRUCTION" ]
then
    eval "$DUMP_INSTRUCTION"
else
    dump_rootfs
    do_default_action
fi


