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

to_udev_name() {
    local dev="$1"

    case "$dev" in
    UUID=*)
        dev=`blkid -U "${dev#UUID=}"`
        ;;
    LABEL=*)
        dev=`blkid -L "${dev#LABEL=}"`
        ;;
    esac
    echo ${dev#/dev/}
}

depends() {
    echo "base shutdown"
    return 0
}

install() {
    sed -ne '/^#/!p' /etc/kdump.conf > /tmp/$$-kdump.conf
    while read config_opt config_val;
    do
        case "$config_opt" in
        ext[234]|xfs|btrfs|minix|raw)
            sed -i -e "s#$1#/dev/$(to_udev_name $1)#" /tmp/$$-kdump.conf
            ;;
        esac
    done < /etc/kdump.conf

    inst "/bin/date" "/bin/date"
    inst "/bin/sync" "/bin/sync"
    inst "/sbin/makedumpfile" "/sbin/makedumpfile"
    inst "/tmp/$$-kdump.conf" "/etc/kdump.conf"
    inst_hook pre-pivot 01 "$moddir/kdump.sh"
}

