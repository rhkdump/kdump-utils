#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k

# shellcheck source=/dev/null
. /usr/share/beakerlib/beakerlib.sh || exit 1

rlJournalStart

if [ "$TMT_REBOOT_COUNT" == 0 ]; then
    rlPhaseStartTest
    rlRun "kdumpctl reset-crashkernel --kernel=ALL"
    rlRun "tmt-reboot"
    rlPhaseEnd

elif [ "$TMT_REBOOT_COUNT" == 1 ]; then
    rlPhaseStartTest
    _default_crashkernel=$(kdumpctl get-default-crashkernel)
    rlRun "grep crashkernel=$_default_crashkernel /proc/cmdline"
    rlPhaseEnd
fi

rlJournalEnd
