#!/bin/bash -eux

ovs_configure_script=/usr/local/bin/configure-ovs.sh

extract_configure-ovs-script() {
    local _script_url

    _script_url=https://github.com/openshift/machine-config-operator/raw/refs/heads/master/templates/common/_base/files/configure-ovs-network.yaml

    if curl -sL $_script_url | grep -A2000 '#!/bin/bash' > "$ovs_configure_script"; then
        chmod +x "$ovs_configure_script"
    else
        return 1
    fi
}

create_bond_network() {
    local _ifname

    _ifname=$(ip route show default | awk '{print $5}') || return 1
    nmcli con add type bond ifname bond0
    nmcli con add type ethernet ifname "$_ifname" master bond0
    nmcli con up "bond-slave-$_ifname"
}

systemctl enable --now openvswitch
# restart NM so the ovs plugin can be activated
systemctl restart NetworkManager

mkdir -p /etc/ovnk
echo bond0 > /etc/ovnk/iface_default_hint

extract_configure-ovs-script
create_bond_network
"$ovs_configure_script" OVNKubernetes

# make the connections persistent
cp /run/NetworkManager/system-connections/* /etc/NetworkManager/system-connections/
