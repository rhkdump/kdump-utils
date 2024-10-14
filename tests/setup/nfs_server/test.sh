#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
. /usr/share/beakerlib/beakerlib.sh || exit 1

rlJournalStart
    rlPhaseStartTest
        rlRun "dnf -y install nfs-utils"
        rlRun "mkdir -p /var/tmp/nfsshare/var/crash"
        rlRun "echo '/var/tmp/nfsshare 192.168.0.0/16(rw,no_root_squash)' >> /etc/exports"
        rlRun "systemctl enable --now rpcbind nfs-server"
    rlPhaseEnd

rlJournalEnd
