#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k

# shellcheck source=/dev/null
. /usr/share/beakerlib/beakerlib.sh || exit 1

rlJournalStart

if [ "$TMT_TEST_RESTART_COUNT" == 0 ]; then
    rlPhaseStartTest
    rlRun "kdumpctl restart" || rlDie "Failed to restart kdump"
    rlRun "sync"
    rlRun "echo 1 > /proc/sys/kernel/sysrq"
    rlRun "echo c > /proc/sysrq-trigger"
    rlPhaseEnd
fi

rlJournalEnd
