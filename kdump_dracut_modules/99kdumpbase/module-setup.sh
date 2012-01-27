#!/bin/bash

. $dracutfunctions

check() {
    [[ $debug ]] && set -x
    #kdumpctl sets this explicitly
    if [ -z "$IN_KDUMP" ] || [ ! -f /etc/kdump.conf ]
    then
        return 1
    fi
    return 0
}

depends() {
    echo "base shutdown"
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

is_bridge() {
     [ -d /sys/class/net/"$1"/bridge ]
}

is_bond() {
     [ -d /sys/class/net/"$1"/bonding ]
}

install() {
    local _server
    local _netdev

    sed -ne '/^#/!p' /etc/kdump.conf > /tmp/$$-kdump.conf
    while read config_opt config_val;
    do
        case "$config_opt" in
        ext[234]|xfs|btrfs|minix|raw)
            sed -i -e "s#$config_val#/dev/$(to_udev_name $config_val)#" /tmp/$$-kdump.conf
            ;;
        net)
            if strstr "$config_val" "@"; then
                _server=$(echo $config_val | sed -e 's#.*@\(.*\):.*#\1#')
            else
                _server=$(echo $config_val | sed -e 's#\(.*\):.*#\1#')
            fi

            _netdev=`/sbin/ip route get to $_server 2>&1`
            [ $? != 0 ] && echo "Bad kdump location: $config_val" && exit 1
            #the field in the ip output changes if we go to another subnet
            if [ -n "`echo $_netdev | grep via`" ]
            then
                # we are going to a different subnet
                _netdev=`echo $_netdev|awk '{print $5;}'|head -n 1`
            else
                # we are on the same subnet
                _netdev=`echo $_netdev|awk '{print $3}'|head -n 1`
            fi
            echo " ip=$_netdev:dhcp" > ${initdir}/etc/cmdline.d/40ip.conf
            if is_bridge "$_netdev"; then
                echo " bridge=$_netdev:$(cd /sys/class/net/$_netdev/brif/; echo *)" > ${initdir}/etc/cmdline.d/41bridge.conf
            elif is_bond "$_netdev"; then
                echo " bond=$_netdev:\"$(cat /sys/class/net/$_netdev/bonding/slaves)\"" > ${initdir}/etc/cmdline.d/42bond.conf
                #TODO
                #echo "bondoptions=\"$bondoptions\"" >> /tmp/$$-bond
            else
                :
            fi
            ;;
        esac
    done < /etc/kdump.conf

    inst "/bin/date" "/bin/date"
    inst "/bin/sync" "/bin/sync"
    inst "/sbin/makedumpfile" "/sbin/makedumpfile"
    inst "/tmp/$$-kdump.conf" "/etc/kdump.conf"
    inst_hook pre-pivot 93 "$moddir/kdump.sh"
}

