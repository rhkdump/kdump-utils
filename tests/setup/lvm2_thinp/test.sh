#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k

# shellcheck source=/dev/null
. /usr/share/beakerlib/beakerlib.sh || exit 1

rlJournalStart

if [ "$TMT_REBOOT_COUNT" == 0 ]; then
    rlPhaseStartTest
    VG=vg00
    LV_THINPOOL=thinpool
    LV_VOLUME=thinlv
    VMCORE_PATH=/var/crash

    cat << EOF > /etc/lvm/lvm.conf
activation {
        thin_pool_autoextend_threshold = 70
        thin_pool_autoextend_percent = 20
        monitoring = 1
}
EOF

    vgcreate $VG /dev/vdb
    # Create a small thinpool which is definitely not enough for
    # vmcore, then create a thin volume which is definitely enough
    # for vmcore, so we can make sure thinpool should be autoextend
    # during runtime.
    lvcreate -L 10M -T $VG/$LV_THINPOOL
    lvcreate -V 300M -T $VG/$LV_THINPOOL -n $LV_VOLUME
    mkfs.ext4 /dev/$VG/$LV_VOLUME
    mount /dev/$VG/$LV_VOLUME /mnt
    # Prevent an empty /etc/lvm/devices/system.devices file after a kernel
    # panic which will cause failure of pvscan
    rm -f /etc/lvm/devices/system.devices
    mkdir -p /mnt/$VMCORE_PATH

    cat << EOF > /etc/kdump.conf
ext4 /dev/$VG/$LV_VOLUME
path $VMCORE_PATH
core_collector makedumpfile -l --message-level 7 -d 31
EOF
    rlPhaseEnd
fi

rlJournalEnd
