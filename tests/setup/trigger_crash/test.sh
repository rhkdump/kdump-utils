#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
. /usr/share/beakerlib/beakerlib.sh || exit 1

rlJournalStart

  if [ $TMT_REBOOT_COUNT == 0 ]; then
    rlPhaseStartTest
        rlRun "kdumpctl restart" || rlDie "Failed to restart kdump"
        rlRun "sync"
        rlRun "echo 1 > /proc/sys/kernel/sysrq"
        tmt-reboot -c "echo c > /proc/sysrq-trigger"
    rlPhaseEnd
  fi
rlJournalEnd
