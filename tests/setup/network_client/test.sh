#!/bin/sh -eux
function get_IP() {
    if echo $1 | grep -E -q '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+'; then
        echo $1
    else
        host $1 | sed -n -e 's/.*has address //p' | head -n 1
    fi
}

function assign_server_roles() {
    if [ -n "${TMT_TOPOLOGY_BASH}" ] && [ -f ${TMT_TOPOLOGY_BASH} ]; then
        # assign roles based on tmt topology data
        cat ${TMT_TOPOLOGY_BASH}
        . ${TMT_TOPOLOGY_BASH}

        export CLIENT=${TMT_GUESTS["client.hostname"]}
        export SERVER=${TMT_GUESTS["server.hostname"]}
        MY_IP="${TMT_GUEST['hostname']}"
    elif [ -n "$SERVERS" ]; then
        # assign roles using SERVERS and CLIENTS variables
        export SERVER=$( echo "$SERVERS $CLIENTS" | awk '{ print $1 }')
        export CLIENT=$( echo "$SERVERS $CLIENTS" | awk '{ print $2 }')
    fi

    [ -z "$MY_IP" ] && MY_IP=$( hostname -I | awk '{ print $1 }' )
    [ -n "$SERVER" ] && export SERVER_IP=$( get_IP $SERVER )
    [ -n "$CLIENT" ] && export CLIENT_IP=$( get_IP $CLIENT )
}

assign_server_roles
echo "SERVER: $SERVER ${SERVER_IP}"
echo "CLIENT: ${CLIENT} ${CLIENT}"
echo "This system is: $(hostname) ${MY_IP}"

if [[ $REMOTE_TYPE == NFS ]]; then
    echo nfs $SERVER:/var/tmp/nfsshare >> /etc/kdump.conf
elif [[ $REMOTE_TYPE == NFS_EARLY ]]; then
    if [ $TMT_REBOOT_COUNT == 0 ]; then
       echo nfs $SERVER:/var/tmp/nfsshare > /etc/kdump.conf
       echo core_collector makedumpfile -l --message-level 7 -d 31 >> /etc/kdump.conf
       kdumpctl start || exit 1
       earlykdump_path="/usr/lib/dracut/modules.d/99earlykdump/early-kdump.sh"
       tmp_file="/tmp/.tmp-file"
       cat << EOF > $tmp_file
echo 1 > /proc/sys/kernel/sysrq
echo c > /proc/sysrq-trigger
EOF
       sed -i "/early_kdump_load$/r $tmp_file" $earlykdump_path
       cp /boot/initramfs-$(uname -r).img /boot/initramfs-$(uname -r).img.bak
       dracut -f --add earlykdump
       mv /boot/initramfs-$(uname -r).img /boot/initramfs-$(uname -r).img.new
       mv /boot/initramfs-$(uname -r).img.bak /boot/initramfs-$(uname -r).img
       sync
       kexec -s -l /boot/vmlinuz-$(uname -r) --initrd=/boot/initramfs-$(uname -r).img.new --reuse-cmdline  --append=rd.earlykdump
       tmt-reboot -c "systemctl kexec"
  fi
elif [[ $REMOTE_TYPE == SSH ]]; then
  TMT_TEST_PLAN_ROOT=${TMT_PLAN_DATA%data}
  SERVER_SSH_KEY=${TMT_TEST_PLAN_ROOT}/provision/server/id_ecdsa
  if test -f $SERVER_SSH_KEY; then
    ssh-keyscan -H $SERVER > /root/.ssh/known_hosts
    ssh root@$SERVER -i $SERVER_SSH_KEY 'mkdir /var/crash'
    echo ssh root@$SERVER > /etc/kdump.conf
    echo sshkey $SERVER_SSH_KEY >> /etc/kdump.conf
    echo core_collector makedumpfile -l --message-level 7 -d 31 -F >> /etc/kdump.conf
  else
    exit 1
  fi
fi
