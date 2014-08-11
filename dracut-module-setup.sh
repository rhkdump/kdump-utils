#!/bin/bash

. $dracutfunctions
. /lib/kdump/kdump-lib.sh

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
    local _dep="base shutdown"

    if [ -d /sys/module/drm/drivers ]; then
        _dep="$_dep drm"
    fi

    if [ is_generic_fence_kdump -o is_pcs_fence_kdump ]; then
        _dep="$_dep network"
    fi

    echo $_dep
    return 0
}

kdump_to_udev_name() {
    local dev="${1//\"/}"

    case "$dev" in
    UUID=*)
        dev=`blkid -U "${dev#UUID=}"`
        ;;
    LABEL=*)
        dev=`blkid -L "${dev#LABEL=}"`
        ;;
    esac
    echo $(get_persistent_dev "$dev")
}

kdump_is_bridge() {
     [ -d /sys/class/net/"$1"/bridge ]
}

kdump_is_bond() {
     [ -d /sys/class/net/"$1"/bonding ]
}

kdump_is_team() {
     [ -f /usr/bin/teamnl ] && teamnl $1 ports &> /dev/null
}

kdump_is_vlan() {
     [ -f /proc/net/vlan/"$1" ]
}

# $1: netdev name
kdump_setup_dns() {
    _dnsfile=${initdir}/etc/cmdline.d/42dns.conf
    . /etc/sysconfig/network-scripts/ifcfg-$1
    [ -n "$DNS1" ] && echo "nameserver=$DNS1" > "$_dnsfile"
    [ -n "$DNS2" ] && echo "nameserver=$DNS2" >> "$_dnsfile"
}

#$1: netdev name
#$2: srcaddr
#if it use static ip echo it, or echo null
kdump_static_ip() {
    local _netmask _gateway
    local _netdev="$1" _srcaddr="$2"
    local _ipaddr=$(ip addr show dev $_netdev permanent | \
                    awk "/ $_srcaddr\/.* $_netdev\$/{print \$2}")
    if [ -n "$_ipaddr" ]; then
       _netmask=$(ipcalc -m $_ipaddr | cut -d'=' -f2)
       _gateway=$(ip route list dev $_netdev | awk '/^default /{print $3}')
       echo -n "${_srcaddr}::${_gateway}:${_netmask}::"
    fi

    /sbin/ip route show | grep -v default | grep "^[[:digit:]].*via.* $_netdev " |\
    while read line; do
        echo $line | awk '{printf("rd.route=%s:%s:%s\n", $1, $3, $5)}'
    done >> ${initdir}/etc/cmdline.d/45route-static.conf
}

kdump_get_mac_addr() {
    cat /sys/class/net/$1/address
}

#Bonding or team master modifies the mac address
#of its slaves, we should use perm address
kdump_get_perm_addr() {
    local addr=$(ethtool -P $1 | sed -e 's/Permanent address: //')
    if [ -z "$addr" ] || [ "$addr" = "00:00:00:00:00:00" ]
    then
        derror "Can't get the permanent address of $1"
    else
        echo "$addr"
    fi
}

# Prefix kernel assigned names with "kdump-". EX: eth0 -> kdump-eth0
# Because kernel assigned names are not persistent between 1st and 2nd
# kernel. We could probably end up with eth0 being eth1, eth0 being
# eth1, and naming conflict happens.
kdump_setup_ifname() {
    local _ifname

    if [[ $1 =~ eth* ]]; then
        _ifname="kdump-$1"
    else
        _ifname="$1"
    fi

    echo "$_ifname"
}

kdump_setup_bridge() {
    local _netdev=$1
    local _brif _dev _mac _kdumpdev
    for _dev in `ls /sys/class/net/$_netdev/brif/`; do
        _kdumpdev=$_dev
        if kdump_is_bond "$_dev"; then
            kdump_setup_bond "$_dev"
        elif kdump_is_team "$_dev"; then
            kdump_setup_team "$_dev"
        elif kdump_is_vlan "$_dev"; then
            kdump_setup_vlan "$_dev"
        else
            _mac=$(kdump_get_mac_addr $_dev)
            _kdumpdev=$(kdump_setup_ifname $_dev)
            echo -n " ifname=$_kdumpdev:$_mac" >> ${initdir}/etc/cmdline.d/41bridge.conf
        fi
        _brif+="$_kdumpdev,"
    done
    echo " bridge=$_netdev:$(echo $_brif | sed -e 's/,$//')" >> ${initdir}/etc/cmdline.d/41bridge.conf
}

kdump_setup_bond() {
    local _netdev=$1
    local _dev _mac _slaves _kdumpdev
    for _dev in `cat /sys/class/net/$_netdev/bonding/slaves`; do
        _mac=$(kdump_get_perm_addr $_dev)
        _kdumpdev=$(kdump_setup_ifname $_dev)
        echo -n " ifname=$_kdumpdev:$_mac" >> ${initdir}/etc/cmdline.d/42bond.conf
        _slaves+="$_kdumpdev,"
    done
    echo -n " bond=$_netdev:$(echo $_slaves | sed 's/,$//')" >> ${initdir}/etc/cmdline.d/42bond.conf
    # Get bond options specified in ifcfg
    . /etc/sysconfig/network-scripts/ifcfg-$_netdev
    bondoptions="$(echo :$BONDING_OPTS | sed 's/\s\+/,/')"
    echo "$bondoptions" >> ${initdir}/etc/cmdline.d/42bond.conf
}

kdump_setup_team() {
    local _netdev=$1
    local _dev _mac _slaves _kdumpdev
    for _dev in `teamnl $_netdev ports | awk -F':' '{print $2}'`; do
        _mac=$(kdump_get_perm_addr $_dev)
        _kdumpdev=$(kdump_setup_ifname $_dev)
        echo -n " ifname=$_kdumpdev:$_mac" >> ${initdir}/etc/cmdline.d/44team.conf
        _slaves+="$_kdumpdev,"
    done
    echo " team=$_netdev:$(echo $_slaves | sed -e 's/,$//')" >> ${initdir}/etc/cmdline.d/44team.conf
    #Buggy version teamdctl outputs to stderr!
    #Try to use the latest version of teamd.
    teamdctl "$_netdev" config dump > /tmp/$$-$_netdev.conf
    if [ $? -ne 0 ]
    then
        derror "teamdctl failed."
        exit 1
    fi
    inst_dir /etc/teamd
    inst_simple /tmp/$$-$_netdev.conf "/etc/teamd/$_netdev.conf"
    rm -f /tmp/$$-$_netdev.conf
}

kdump_setup_vlan() {
    local _netdev=$1
    local _phydev="$(awk '/^Device:/{print $2}' /proc/net/vlan/"$_netdev")"
    local _netmac="$(kdump_get_mac_addr $_phydev)"
    local _kdumpdev

    #Just support vlan over bond, it is not easy
    #to support all other complex setup
    if kdump_is_bridge "$_phydev"; then
        derror "Vlan over bridge is not supported!"
        exit 1
    elif kdump_is_team "$_phydev"; then
        derror "Vlan over team is not supported!"
        exit 1
    elif kdump_is_bond "$_phydev"; then
        kdump_setup_bond "$_phydev"
        echo " vlan=$_netdev:$_phydev" > ${initdir}/etc/cmdline.d/43vlan.conf
    else
        _kdumpdev="$(kdump_setup_ifname $_phydev)"
        echo " vlan=$_netdev:$_kdumpdev ifname=$_kdumpdev:$_netmac" > ${initdir}/etc/cmdline.d/43vlan.conf
    fi
}

# setup s390 znet cmdline
# $1: netdev name
kdump_setup_znet() {
    local _options=""
    . /etc/sysconfig/network-scripts/ifcfg-$1
    for i in $OPTIONS; do
        _options=${_options},$i
    done
    echo rd.znet=${NETTYPE},${SUBCHANNELS}${_options} > ${initdir}/etc/cmdline.d/30znet.conf
}

# Setup dracut to bringup a given network interface
kdump_setup_netdev() {
    local _netdev=$1 _srcaddr=$2
    local _static _proto _ip_conf _ip_opts _ifname_opts

    if [ "$(uname -m)" = "s390x" ]; then
        kdump_setup_znet $_netdev
    fi

    _netmac=$(kdump_get_mac_addr $_netdev)
    _static=$(kdump_static_ip $_netdev $_srcaddr)
    if [ -n "$_static" ]; then
        _proto=none
    else
        _proto=dhcp
    fi

    _ip_conf="${initdir}/etc/cmdline.d/40ip.conf"
    _ip_opts=" ip=${_static}$(kdump_setup_ifname $_netdev):${_proto}"

    # dracut doesn't allow duplicated configuration for same NIC, even they're exactly the same.
    # so we have to avoid adding duplicates
    if [ ! -f $_ip_conf ] || ! grep -q $_ip_opts $_ip_conf; then
        echo "$_ip_opts" >> $_ip_conf
    fi

    if kdump_is_bridge "$_netdev"; then
        kdump_setup_bridge "$_netdev"
    elif kdump_is_bond "$_netdev"; then
        kdump_setup_bond "$_netdev"
    elif kdump_is_team "$_netdev"; then
        kdump_setup_team "$_netdev"
    elif kdump_is_vlan "$_netdev"; then
        kdump_setup_vlan "$_netdev"
    else
        _ifname_opts=" ifname=$(kdump_setup_ifname $_netdev):$(kdump_get_mac_addr $_netdev)"
        echo "$_ifname_opts" >> $_ip_conf
    fi

    kdump_setup_dns "$_netdev"
}

#Function:kdump_install_net
#$1: config values of net line in kdump.conf
#$2: srcaddr of network device
kdump_install_net() {
    local _server _netdev _srcaddr
    local config_val="$1"

    _server=`echo $config_val | sed 's/.*@//' | cut -d':' -f1`

    _need_dns=`echo $_server|grep "[a-zA-Z]"`
    [ -n "$_need_dns" ] && _server=`getent hosts $_server|cut -d' ' -f1`

    _netdev=`/sbin/ip route get to $_server 2>&1`
    [ $? != 0 ] && echo "Bad kdump location: $config_val" && exit 1

    #the field in the ip output changes if we go to another subnet
    if [ -n "`echo $_netdev | grep via`" ]
    then
        # we are going to a different subnet
        _srcaddr=`echo $_netdev|awk '{print $7}'|head -n 1`
        _netdev=`echo $_netdev|awk '{print $5;}'|head -n 1`
    else
        # we are on the same subnet
        _srcaddr=`echo $_netdev|awk '{print $5}'|head -n 1`
        _netdev=`echo $_netdev|awk '{print $3}'|head -n 1`
    fi

    kdump_setup_netdev "${_netdev}" "${_srcaddr}"

    #save netdev used for kdump as cmdline
    # Whoever calling kdump_install_net() is setting up the default gateway,
    # ie. bootdev/kdumpnic. So don't override the setting if calling
    # kdump_install_net() for another time. For example, after setting eth0 as
    # the default gate way for network dump, eth1 in the fence kdump path will
    # call kdump_install_net again and we don't want eth1 to be the default
    # gateway.
    if [ ! -f ${initdir}${initdir}/etc/cmdline.d/60kdumpnic.conf ] &&
       [ ! -f ${initdir}/etc/cmdline.d/70bootdev.conf ]; then
        echo "kdumpnic=$(kdump_setup_ifname $_netdev)" > ${initdir}/etc/cmdline.d/60kdumpnic.conf
        echo "bootdev=$(kdump_setup_ifname $_netdev)" > ${initdir}/etc/cmdline.d/70bootdev.conf
    fi
}

default_dump_target_install_conf()
{
    local _target _fstype
    local _s  _t
    local _mntpoint
    local _path _save_path

    is_user_configured_dump_target && return

    _save_path=$(grep ^path "/etc/kdump.conf"| cut -d' '  -f2)
    [ -z "$_save_path" ] && _save_path=$DEFAULT_PATH

    _mntpoint=$(get_mntpoint_from_path $_save_path)
    _target=$(get_target_from_path $_save_path)
    if [ "$_mntpoint" != "/" ]; then
        _fstype=$(get_fs_type_from_target $_target)

        if $(is_fs_type_nfs $_fstype); then
            kdump_install_net "$_target"
            _fstype="nfs"
        else
            _target=$(kdump_to_udev_name $_target)
        fi

        echo "$_fstype $_target" >> /tmp/$$-kdump.conf

        _path=${_save_path##"$_mntpoint"}
        sed -i -e "s#$_save_path#$_path#" /tmp/$$-kdump.conf
    fi

}

#install kdump.conf and what user specifies in kdump.conf
kdump_install_conf() {
    sed -ne '/^#/!p' /etc/kdump.conf > /tmp/$$-kdump.conf

    while read config_opt config_val;
    do
        # remove inline comments after the end of a directive.
        config_val=$(strip_comments $config_val)
        case "$config_opt" in
        ext[234]|xfs|btrfs|minix|raw)
            sed -i -e "s#$config_val#$(kdump_to_udev_name $config_val)#" /tmp/$$-kdump.conf
            ;;
        ssh|nfs)
            kdump_install_net "$config_val"
            ;;
        kdump_pre|kdump_post|extra_bins)
            dracut_install $config_val
            ;;
        core_collector)
            dracut_install "${config_val%%[[:blank:]]*}"
            ;;
        esac
    done < /etc/kdump.conf

    default_dump_target_install_conf

    kdump_configure_fence_kdump  "/tmp/$$-kdump.conf"
    inst "/tmp/$$-kdump.conf" "/etc/kdump.conf"
    rm -f /tmp/$$-kdump.conf
}

kdump_iscsi_get_rec_val() {

    local result

    # The open-iscsi 742 release changed to using flat files in
    # /var/lib/iscsi.

    result=$(/sbin/iscsiadm --show -m session -r ${1} | grep "^${2} = ")
    result=${result##* = }
    echo $result
}

kdump_get_iscsi_initiator() {
    local _initiator
    local initiator_conf="/etc/iscsi/initiatorname.iscsi"

    [ -f "$initiator_conf" ] || return 1

    while read _initiator; do
        [ -z "${_initiator%%#*}" ] && continue # Skip comment lines

        case $_initiator in
            InitiatorName=*)
                initiator=${_initiator#InitiatorName=}
                echo "rd.iscsi.initiator=${initiator}"
                return 0;;
            *) ;;
        esac
    done < ${initiator_conf}

    return 1
}

# No ibft handling yet.
kdump_setup_iscsi_device() {
    local path=$1
    local tgt_name; local tgt_ipaddr;
    local username; local password; local userpwd_str;
    local username_in; local password_in; local userpwd_in_str;
    local netdev
    local srcaddr
    local idev
    local netroot_str ; local initiator_str;
    local netroot_conf="${initdir}/etc/cmdline.d/50iscsi.conf"
    local initiator_conf="/etc/iscsi/initiatorname.iscsi"

    dinfo "Found iscsi component $1"

    # Check once before getting explicit values, so we can output a decent
    # error message.

    if ! /sbin/iscsiadm -m session -r ${path} >/dev/null ; then
        derror "Unable to find iscsi record for $path"
        return 1
    fi

    tgt_name=$(kdump_iscsi_get_rec_val ${path} "node.name")
    tgt_ipaddr=$(kdump_iscsi_get_rec_val ${path} "node.conn\[0\].address")

    # get and set username and password details
    username=$(kdump_iscsi_get_rec_val ${path} "node.session.auth.username")
    [ "$username" == "<empty>" ] && username=""
    password=$(kdump_iscsi_get_rec_val ${path} "node.session.auth.password")
    [ "$password" == "<empty>" ] && password=""
    username_in=$(kdump_iscsi_get_rec_val ${path} "node.session.auth.username_in")
    [ -n "$username" ] && userpwd_str="$username:$password"

    # get and set incoming username and password details
    [ "$username_in" == "<empty>" ] && username_in=""
    password_in=$(kdump_iscsi_get_rec_val ${path} "node.session.auth.password_in")
    [ "$password_in" == "<empty>" ] && password_in=""

    [ -n "$username_in" ] && userpwd_in_str=":$username_in:$password_in"

    netdev=$(/sbin/ip route get to ${tgt_ipaddr} | \
        sed 's|.*dev \(.*\).*|\1|g')
    srcaddr=$(echo $netdev | awk '{ print $3; exit }')
    netdev=$(echo $netdev | awk '{ print $1; exit }')

    kdump_setup_netdev $netdev $srcaddr

    # prepare netroot= command line
    # FIXME: IPV6 addresses require explicit [] around $tgt_ipaddr
    # FIXME: Do we need to parse and set other parameters like protocol, port
    #        iscsi_iface_name, netdev_name, LUN etc.

    netroot_str="netroot=iscsi:${userpwd_str}${userpwd_in_str}@$tgt_ipaddr::::$tgt_name"

    [[ -f $netroot_conf ]] || touch $netroot_conf

    # If netroot target does not exist already, append.
    if ! grep -q $netroot_str $netroot_conf; then
         echo $netroot_str >> $netroot_conf
         dinfo "Appended $netroot_str to $netroot_conf"
    fi

    # Setup initator
    initiator_str=$(kdump_get_iscsi_initiator)
    [ $? -ne "0" ] && derror "Failed to get initiator name" && return 1

    # If initiator details do not exist already, append.
    if ! grep -q "$initiator_str" $netroot_conf; then
         echo "$initiator_str" >> $netroot_conf
         dinfo "Appended "$initiator_str" to $netroot_conf"
    fi
}

kdump_check_iscsi_targets () {
    # If our prerequisites are not met, fail anyways.
    type -P iscsistart >/dev/null || return 1

    kdump_check_setup_iscsi() (
        local _dev
        _dev=$1

        [[ -L /sys/dev/block/$_dev ]] || return
        cd "$(readlink -f /sys/dev/block/$_dev)"
        until [[ -d sys || -d iscsi_session ]]; do
            cd ..
        done
        [[ -d iscsi_session ]] && kdump_setup_iscsi_device "$PWD"
    )

    [[ $hostonly ]] || [[ $mount_needs ]] && {
        for_each_host_dev_and_slaves_all kdump_check_setup_iscsi
    }
}

# retrieves fence_kdump nodes from Pacemaker cluster configuration
get_pcs_fence_kdump_nodes() {
    local nodes

    # get cluster nodes from cluster cib, get interface and ip address
    nodelist=`pcs cluster cib | xmllint --xpath "/cib/status/node_state/@uname" -`

    # nodelist is formed as 'uname="node1" uname="node2" ... uname="nodeX"'
    # we need to convert each to node1, node2 ... nodeX in each iteration
    for node in ${nodelist}; do
        # convert $node from 'uname="nodeX"' to 'nodeX'
        eval $node
        nodename=$uname
        # Skip its own node name
        if [ "$nodename" = `hostname` -o "$nodename" = `hostname -s` ]; then
            continue
        fi
        nodes="$nodes $nodename"
    done

    echo $nodes
}

# retrieves fence_kdump args from config file
get_pcs_fence_kdump_args() {
    if [ -f $FENCE_KDUMP_CONFIG_FILE ]; then
        . $FENCE_KDUMP_CONFIG_FILE
        echo $FENCE_KDUMP_OPTS
    fi
}

# setup fence_kdump in cluster
# setup proper network and install needed files
kdump_configure_fence_kdump () {
    local kdump_cfg_file=$1
    local nodes
    local args

    if is_generic_fence_kdump; then
        nodes=$(get_option_value "fence_kdump_nodes")

    elif is_pcs_fence_kdump; then
        nodes=$(get_pcs_fence_kdump_nodes)

        # set appropriate options in kdump.conf
        echo "fence_kdump_nodes $nodes" >> ${kdump_cfg_file}

        args=$(get_pcs_fence_kdump_args)
        if [ -n "$args" ]; then
            echo "fence_kdump_args $args" >> ${kdump_cfg_file}
        fi

    else
        # fence_kdump not configured
        return 1
    fi

    # setup network for each node
    for node in ${nodes}; do
        kdump_install_net $node
    done

    dracut_install $FENCE_KDUMP_SEND
}

# Install a random seed used to feed /dev/urandom
# By the time kdump service starts, /dev/uramdom is already fed by systemd
kdump_install_random_seed() {
    local poolsize=`cat /proc/sys/kernel/random/poolsize`

    if [ ! -d ${initdir}/var/lib/ ]; then
        mkdir -p ${initdir}/var/lib/
    fi

    dd if=/dev/urandom of=${initdir}/var/lib/random-seed \
       bs=$poolsize count=1 2> /dev/null
}

install() {
    kdump_install_conf

    if is_ssh_dump_target; then
        kdump_install_random_seed
    fi
    dracut_install -o /etc/adjtime /etc/localtime
    inst "$moddir/monitor_dd_progress" "/kdumpscripts/monitor_dd_progress"
    chmod +x ${initdir}/kdumpscripts/monitor_dd_progress
    inst "/bin/dd" "/bin/dd"
    inst "/bin/tail" "/bin/tail"
    inst "/bin/date" "/bin/date"
    inst "/bin/sync" "/bin/sync"
    inst "/bin/cut" "/bin/cut"
    inst "/sbin/makedumpfile" "/sbin/makedumpfile"
    inst "/sbin/vmcore-dmesg" "/sbin/vmcore-dmesg"
    inst "/lib/kdump/kdump-lib.sh" "/lib/kdump-lib.sh"
    inst "/lib/kdump/kdump-lib-initramfs.sh" "/lib/kdump-lib-initramfs.sh"
    inst "$moddir/kdump.sh" "/usr/bin/kdump.sh"
    inst "$moddir/kdump-capture.service" "$systemdsystemunitdir/kdump-capture.service"
    ln_r "$systemdsystemunitdir/kdump-capture.service" "$systemdsystemunitdir/initrd.target.wants/kdump-capture.service"
    inst "$moddir/kdump-error-handler.sh" "/usr/bin/kdump-error-handler.sh"
    inst "$moddir/kdump-error-handler.service" "$systemdsystemunitdir/kdump-error-handler.service"
    # Replace existing emergency service
    cp "$moddir/kdump-emergency.service" "$initdir/$systemdsystemunitdir/emergency.service"
    # Also redirect dracut-emergency to kdump error handler
    ln_r "$systemdsystemunitdir/emergency.service" "$systemdsystemunitdir/dracut-emergency.service"

    # Check for all the devices and if any device is iscsi, bring up iscsi
    # target. Ideally all this should be pushed into dracut iscsi module
    # at some point of time.
    kdump_check_iscsi_targets
}

installkernel() {
    wdt=$(lsmod|cut -f1 -d' '|grep "wdt$")
    if [ -n "$wdt" ]; then
        [ "$wdt" = "iTCO_wdt" ] && instmods lpc_ich
        instmods $wdt
    fi
}
