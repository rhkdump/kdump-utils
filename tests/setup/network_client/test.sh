#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k

# shellcheck source=/dev/null
. /usr/share/beakerlib/beakerlib.sh || exit 1

# get_IP and assign_server_roles are adapated from keylime-tests
# https://github.com/RedHat-SP-Security/keylime-tests/blob/e3117dd17bc01c5bf1fcbd8986d0683a0952d738/Multihost/basic-attestation/test.sh#L46
get_IP() {
    if echo "$1" | grep -E -q '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+'; then
        echo "$1"
    else
        host "$1" | sed -n -e 's/.*has address //p' | head -n 1
    fi
}

assign_server_roles() {
    if [ -n "${TMT_TOPOLOGY_BASH}" ] && [ -f "${TMT_TOPOLOGY_BASH}" ]; then
        # assign roles based on tmt topology data
        cat "${TMT_TOPOLOGY_BASH}"
        # shellcheck source=/dev/null
        . "${TMT_TOPOLOGY_BASH}"

        CLIENT=${TMT_GUESTS["client.hostname"]}
        export CLIENT
        SERVER=${TMT_GUESTS["server.hostname"]}
        export SERVER
        MY_IP="${TMT_GUEST['hostname']}"
    elif [ -n "$SERVERS" ]; then
        # assign roles using SERVERS and CLIENTS variables
        # shellcheck disable=SC2153 # CLIENTS is an env variable
        SERVER=$(echo "$SERVERS $CLIENTS" | awk '{ print $1 }')
        export SERVER
        CLIENT=$(echo "$SERVERS $CLIENTS" | awk '{ print $2 }')
        export CLIENT
    fi

    [ -z "$MY_IP" ] && MY_IP=$(hostname -I | awk '{ print $1 }')
    [ -n "$SERVER" ] && SERVER_IP=$(get_IP "$SERVER") && export SERVER_IP
    [ -n "$CLIENT" ] && CLIENT_IP=$(get_IP "$CLIENT") && export CLIENT_IP
}

rlJournalStart

rlPhaseStartSetup
assign_server_roles
rlLog "SERVER: $SERVER ${SERVER_IP}"
rlLog "CLIENT: ${CLIENT} ${CLIENT}"
rlLog "This system is: $(hostname) ${MY_IP}"
rlPhaseEnd

rlPhaseStartTest
if [[ $REMOTE_TYPE == NFS ]]; then
    rlRun "echo nfs $SERVER:/var/tmp/nfsshare > /etc/kdump.conf"
elif [[ $REMOTE_TYPE == SSH ]]; then
    TMT_TEST_PLAN_ROOT=${TMT_PLAN_DATA%data}
    SERVER_SSH_KEY=${TMT_TEST_PLAN_ROOT}/provision/server/id_ecdsa
    if test -f "$SERVER_SSH_KEY"; then
        rlRun "ssh-keyscan -H $SERVER > /root/.ssh/known_hosts"
        rlRun "ssh root@$SERVER -i $SERVER_SSH_KEY 'mkdir /var/crash'"
        rlRun "echo ssh root@$SERVER > /etc/kdump.conf"
        rlRun "echo sshkey $SERVER_SSH_KEY >> /etc/kdump.conf"
        rlRun "echo core_collector makedumpfile -l --message-level 7 -d 31 -F >> /etc/kdump.conf"
    else
        rlDie "Server SSH Key not found, something wrong"
    fi
fi
rlPhaseEnd

rlJournalEnd
