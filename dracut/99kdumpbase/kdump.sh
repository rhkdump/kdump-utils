#!/bin/sh
#
# The main kdump routine in capture kernel, bash may not be the
# default shell. Any code added must be POSIX compliant.

# shellcheck source=/dev/null
. /lib/dracut-lib.sh
# shellcheck source=SCRIPTDIR/../../kdump-logger.sh
. /lib/kdump-logger.sh
# shellcheck source=SCRIPTDIR/../../kdump-lib-initramfs.sh
. /lib/kdump-lib-initramfs.sh

#initiate the kdump logger
if ! dlog_init; then
    echo "failed to initiate the kdump logger."
    exit 1
fi

KDUMP_PATH="/var/crash"
KDUMP_LOG_FILE="/run/initramfs/kexec-dmesg.log"
KDUMP_LOG_DEST=""
KDUMP_LOG_OP=""
KDUMP_TEST_ID=""
KDUMP_TEST_STATUS=""
CORE_COLLECTOR=""
DEFAULT_CORE_COLLECTOR="makedumpfile -l --message-level 7 -d 31"
DMESG_COLLECTOR="/sbin/vmcore-dmesg"
FAILURE_ACTION="systemctl reboot -f"
HOST_IP='127.0.0.1'
DUMP_INSTRUCTION=""
SSH_KEY=$DEFAULT_SSHKEY
DD_BLKSIZE=512
FINAL_ACTION="systemctl reboot -f"
KDUMP_PRE=""
KDUMP_POST=""
NEWROOT="/sysroot"
OPALCORE=""
KDUMP_CONF_PARSED="/tmp/kdump.conf.$$"

# POSIX doesn't have pipefail, only apply when using bash
# shellcheck disable=SC3040
[ -n "$BASH" ] && set -o pipefail

DUMP_RETVAL=0

kdump_read_conf > $KDUMP_CONF_PARSED

get_kdump_confs() {
    while read -r config_opt config_val; do
        # remove inline comments after the end of a directive.
        case "$config_opt" in
            path)
                KDUMP_PATH="$config_val"
                ;;
            core_collector)
                [ -n "$config_val" ] && CORE_COLLECTOR="$config_val"
                ;;
            sshkey)
                if [ -f "$config_val" ]; then
                    SSH_KEY=$config_val
                fi
                ;;
            kdump_pre)
                KDUMP_PRE="$config_val"
                ;;
            kdump_post)
                KDUMP_POST="$config_val"
                ;;
            fence_kdump_args)
                FENCE_KDUMP_ARGS="$config_val"
                ;;
            fence_kdump_nodes)
                FENCE_KDUMP_NODES="$config_val"
                ;;
            failure_action | default)
                case $config_val in
                    shell)
                        FAILURE_ACTION="kdump_emergency_shell"
                        ;;
                    reboot)
                        FAILURE_ACTION="systemctl reboot -f && exit"
                        ;;
                    halt)
                        FAILURE_ACTION="halt && exit"
                        ;;
                    poweroff)
                        FAILURE_ACTION="systemctl poweroff -f && exit"
                        ;;
                    dump_to_rootfs)
                        FAILURE_ACTION="dump_to_rootfs"
                        ;;
                esac
                ;;
            final_action)
                case $config_val in
                    reboot)
                        FINAL_ACTION="systemctl reboot -f"
                        ;;
                    halt)
                        FINAL_ACTION="halt"
                        ;;
                    poweroff)
                        FINAL_ACTION="systemctl poweroff -f"
                        ;;
                esac
                ;;
        esac
    done < "$KDUMP_CONF_PARSED"

    if [ -z "$CORE_COLLECTOR" ]; then
        CORE_COLLECTOR="$DEFAULT_CORE_COLLECTOR"
        if is_ssh_dump_target || is_raw_dump_target; then
            CORE_COLLECTOR="$CORE_COLLECTOR -F"
        fi
    fi
}

# store the kexec kernel log to a file.
save_log() {
    # LOG_OP is empty when log can't be saved, eg. raw target
    [ -n "$KDUMP_LOG_OP" ] || return

    dmesg -T > $KDUMP_LOG_FILE

    if command -v journalctl > /dev/null; then
        journalctl -ab >> $KDUMP_LOG_FILE
    fi
    chmod 600 $KDUMP_LOG_FILE

    dinfo "saving the $KDUMP_LOG_FILE to $KDUMP_LOG_DEST/"

    eval "$KDUMP_LOG_OP"
}

dump_fs() {
    ddebug "dump_fs _mp=$NEWROOT"

    if ! is_mounted "$NEWROOT"; then
        dinfo "dump path '$NEWROOT' is not mounted, trying to mount..."
        if ! mount --target "$NEWROOT"; then
            derror "failed to dump to '$NEWROOT', it's not a mount point!"
            return 1
        fi
    fi

    # Remove -F in makedumpfile case. We don't want a flat format dump here.
    case $CORE_COLLECTOR in
        *makedumpfile*)
            CORE_COLLECTOR=$(echo "$CORE_COLLECTOR" | sed -e "s/-F//g")
            THREADS=$(nproc)
            if [ "$THREADS" -gt 1 ]; then
                CORE_COLLECTOR="$CORE_COLLECTOR --num-threads=$THREADS"
            fi
            ;;
    esac

    dinfo "saving to $KDUMP_PATH"

    # Only remount to read-write mode if the dump target is mounted read-only.
    _dump_mnt_op=$(get_mount_info OPTIONS target "$NEWROOT" -f)
    case $_dump_mnt_op in
        ro*)
            dinfo "Remounting the dump target in rw mode."
            mount -o remount,rw "$NEWROOT" || return 1
            ;;
    esac

    mkdir -p "$KDUMP_PATH" || return 1

    save_vmcore_dmesg_fs ${DMESG_COLLECTOR} "$KDUMP_PATH"
    save_opalcore_fs "$KDUMP_PATH"

    dinfo "saving vmcore"
    KDUMP_LOG_DEST=$KDUMP_PATH/
    KDUMP_LOG_OP="mv '$KDUMP_LOG_FILE' '$KDUMP_LOG_DEST/'"

    $CORE_COLLECTOR /proc/vmcore "$KDUMP_PATH/vmcore-incomplete"
    _dump_exitcode=$?
    if [ $_dump_exitcode -eq 0 ]; then
        sync -f "$KDUMP_PATH/vmcore-incomplete"
        _sync_exitcode=$?
        if [ $_sync_exitcode -eq 0 ]; then
            mv "$KDUMP_PATH/vmcore-incomplete" "$KDUMP_PATH/vmcore"
            dinfo "saving vmcore complete"
        else
            derror "sync vmcore failed, exitcode:$_sync_exitcode"
            return 1
        fi
    else
        derror "saving vmcore failed, exitcode:$_dump_exitcode"
        return 1
    fi

    # improper kernel cmdline can cause the failure of echo, we can ignore this kind of failure
    return 0
}

# $1: dmesg collector
# $2: dump path
save_vmcore_dmesg_fs() {
    dinfo "saving vmcore-dmesg.txt to $2"
    if $1 /proc/vmcore > "$2/vmcore-dmesg-incomplete.txt"; then
        mv "$2/vmcore-dmesg-incomplete.txt" "$2/vmcore-dmesg.txt"
        chmod 600 "$2/vmcore-dmesg.txt"

        # Make sure file is on disk. There have been instances where later
        # saving vmcore failed and system rebooted without sync and there
        # was no vmcore-dmesg.txt available.
        sync
        dinfo "saving vmcore-dmesg.txt complete"
    else
        if [ -f "$2/vmcore-dmesg-incomplete.txt" ]; then
            chmod 600 "$2/vmcore-dmesg-incomplete.txt"
        fi
        derror "saving vmcore-dmesg.txt failed"
    fi
}

# $1: dump path
save_opalcore_fs() {
    [ -n "$OPALCORE" ] || return 0

    dinfo "saving opalcore:$OPALCORE to $1/opalcore"
    if ! cp $OPALCORE "$1/opalcore"; then
        derror "saving opalcore failed"
        return 1
    fi

    sync
    dinfo "saving opalcore complete"
    return 0
}

dump_to_rootfs() {

    if [ "$(systemctl status dracut-initqueue | sed -n "s/^\s*Active: \(\S*\)\s.*$/\1/p")" = "inactive" ]; then
        dinfo "Trying to bring up initqueue for rootfs mount"
        systemctl start dracut-initqueue
    fi

    dinfo "Clean up dead systemd services"
    systemctl cancel
    dinfo "Waiting for rootfs mount, will timeout after 90 seconds"
    systemctl start --no-block sysroot.mount

    _loop=0
    while [ $_loop -lt 90 ] && ! is_mounted /sysroot; do
        sleep 1
        _loop=$((_loop + 1))
    done

    if ! is_mounted /sysroot; then
        derror "Failed to mount rootfs"
        return
    fi

    KDUMP_PATH="$NEWROOT/$KDUMP_PATH/$HOST_IP-$(date +%Y-%m-%d-%T)"
    ddebug "NEWROOT=$NEWROOT"
    dump_fs
}

kdump_emergency_shell() {
    ddebug "Switching to kdump emergency shell..."

    # shellcheck source=/dev/null
    [ -f /etc/profile ] && . /etc/profile
    export PS1='kdump:${PWD}# '

    # shellcheck source=/dev/null
    . /lib/dracut-lib.sh
    if [ -f /dracut-state.sh ]; then
        # shellcheck source=/dev/null
        . /dracut-state.sh 2> /dev/null
    fi

    source_conf /etc/conf.d

    type plymouth > /dev/null 2>&1 && plymouth quit

    source_hook "emergency"
    while read -r _tty rest; do
        (
            echo
            echo
            echo 'Entering kdump emergency mode.'
            echo 'Type "journalctl" to view system logs.'
            echo 'Type "rdsosreport" to generate a sosreport, you can then'
            echo 'save it elsewhere and attach it to a bug report.'
            echo
            echo
        ) > "/dev/$_tty"
    done < /proc/consoles
    sh -i -l
    /bin/rm -f -- /.console_lock
}

do_failure_action() {
    dinfo "Executing failure action $FAILURE_ACTION"
    eval "$FAILURE_ACTION"
}

do_final_action() {
    dinfo "Executing final action $FINAL_ACTION"
    eval "$FINAL_ACTION"
}

do_dump() {
    eval "$DUMP_INSTRUCTION"
    _ret=$?

    if [ $_ret -ne 0 ]; then
        derror "saving vmcore failed"
    fi

    return $_ret
}

do_kdump_pre() {
    if [ -n "$KDUMP_PRE" ]; then
        "$KDUMP_PRE"
        _ret=$?
        if [ $_ret -ne 0 ]; then
            derror "$KDUMP_PRE exited with $_ret status"
            return $_ret
        fi
    fi

    # if any script fails, it just raises warning and continues
    if [ -d /etc/kdump/pre.d ]; then
        for file in /etc/kdump/pre.d/*; do
            "$file"
            _ret=$?
            if [ $_ret -ne 0 ]; then
                derror "$file exited with $_ret status"
            fi
        done
    fi
    return 0
}

do_kdump_post() {
    if [ -d /etc/kdump/post.d ]; then
        for file in /etc/kdump/post.d/*; do
            "$file" "$1"
            _ret=$?
            if [ $_ret -ne 0 ]; then
                derror "$file exited with $_ret status"
            fi
        done
    fi

    if [ -n "$KDUMP_POST" ]; then
        "$KDUMP_POST" "$1"
        _ret=$?
        if [ $_ret -ne 0 ]; then
            derror "$KDUMP_POST exited with $_ret status"
        fi
    fi
}

# $1: block target, eg. /dev/sda
dump_raw() {
    [ -b "$1" ] || return 1

    dinfo "saving to raw disk $1"

    if ! echo "$CORE_COLLECTOR" | grep -q makedumpfile; then
        _src_size=$(stat --format %s /proc/vmcore)
        _src_size_mb=$((_src_size / 1048576))
        /kdumpscripts/monitor_dd_progress.sh $_src_size_mb &
    fi

    if echo "$CORE_COLLECTOR" | grep -q makedumpfile; then
        THREADS=$(nproc)
        if [ "$THREADS" -gt 1 ]; then
            CORE_COLLECTOR="$CORE_COLLECTOR --num-threads=$THREADS"
        fi
    fi

    dinfo "saving vmcore"
    $CORE_COLLECTOR /proc/vmcore | dd of="$1" bs=$DD_BLKSIZE >> /tmp/dd_progress_file 2>&1 || return 1
    sync

    dinfo "saving vmcore complete"
    return 0
}

_curl() {
    curl --silent \
        --fail-early \
        --create-file-mode 0600 \
        --ftp-create-dirs \
        -u "$SSH_USER:" \
        --key "$SSH_KEY" \
        "$@"
}

# copy a file to remote host using curl
# $1: file to be copied or - (dash) when read from stdin
# $2: destination path on remote host
copy_to_remote() {
    _src="$1"; shift
    _dst="$1"; shift

    _url="sftp://$SSH_HOST"

    dinfo "saving ${_dst##*/} to $SSH_HOST:${_dst%/*}"
    _curl -T "$_src" -Q "-rename $_dst-incomplete $_dst" "$_url/$_dst-incomplete"
    _ret=$?
    if [ $_ret -ne 0 ]; then
        derror "failed to save ${_dst##*/}, exitcode $_ret"
        return $_ret
    fi

    dinfo "saving ${_dst##*/} complete"
}

dump_ssh() {
    dinfo "saving to $SSH_HOST:$KDUMP_PATH"

    cat /var/lib/random-seed > /dev/urandom

    $DMESG_COLLECTOR /proc/vmcore | copy_to_remote "-" "$KDUMP_PATH/vmcore-dmesg.txt"

    dinfo "saving vmcore"

    KDUMP_LOG_DEST=$SSH_HOST:$KDUMP_PATH/
    KDUMP_LOG_OP="copy_to_remote '$KDUMP_LOG_FILE' '$KDUMP_PATH/kexec-dmesg.log'"

    [ -n "$OPALCORE" ] && copy_to_remote "$OPALCORE" "$KDUMP_PATH/opalcore"

    if [ "${CORE_COLLECTOR%%[[:blank:]]*}" = "scp" ]; then
        copy_to_remote /proc/vmcore "$KDUMP_PATH/vmcore"
        _ret=$?
    else
        $CORE_COLLECTOR /proc/vmcore | copy_to_remote "-" "$KDUMP_PATH/vmcore.flat"
        _ret=$?
    fi

    return $_ret
}

wait_online_network() {
    # In some cases, network may still not be ready because nm-online is called
    # with "-s" which means to wait for NetworkManager startup to complete, rather
    # than waiting for network connectivity specifically. Wait 10mins more for the
    # network to be truely ready in these cases.
    _loop=0
    while [ $_loop -lt 600 ]; do
        sleep 1
        _loop=$((_loop + 1))
        if _route=$(kdump_get_ip_route "$1" 2> /dev/null); then
            printf "%s" "$_route"
            return
        else
            dwarn "Waiting for network to be ready (${_loop}s / 10min)"
        fi
    done

    derror "Oops. The network still isn't ready after waiting 10mins."
    exit 1
}

get_host_ip() {

    if ! is_nfs_dump_target && ! is_ssh_dump_target; then
        return 0
    fi

    _kdump_remote_ip=$(getarg kdump_remote_ip=)

    if [ -z "$_kdump_remote_ip" ]; then
        derror "failed to get remote IP address!"
        return 1
    fi

    if ! _route=$(wait_online_network "$_kdump_remote_ip"); then
        return 1
    fi

    _netdev=$(kdump_get_ip_route_field "$_route" "dev")

    if ! _kdumpip=$(ip addr show dev "$_netdev" | grep '[ ]*inet'); then
        derror "Failed to get IP of $_netdev"
        return 1
    fi

    _kdumpip=$(echo "$_kdumpip" | head -n 1 | awk '{print $2}')
    _kdumpip="${_kdumpip%%/*}"
    HOST_IP=$_kdumpip
}

read_kdump_confs() {
    if [ ! -f "$KDUMP_CONFIG_FILE" ]; then
        derror "$KDUMP_CONFIG_FILE not found"
        return
    fi

    get_kdump_confs

    # rescan for add code for dump target
    while read -r config_opt config_val; do
        # remove inline comments after the end of a directive.
        case "$config_opt" in
            dracut_args)
                config_val=$(get_dracut_args_target "$config_val")
                if [ -n "$config_val" ]; then
                    NEWROOT=$(get_mntpoint_from_target "$config_val")
                    DUMP_INSTRUCTION="dump_fs"
                fi
                ;;
            ext[234] | xfs | btrfs | minix | nfs | virtiofs)
                NEWROOT=$(get_mntpoint_from_target "$config_val")
                DUMP_INSTRUCTION="dump_fs"
                ;;
            raw)
                DUMP_INSTRUCTION="dump_raw $config_val"
                ;;
            ssh)
                SSH_USER="${config_val%@*}"
                SSH_HOST="${config_val#*@}"
                if is_ipv6_address "$SSH_HOST"; then
                    SSH_HOST="[$SSH_HOST]"
                fi
                DUMP_INSTRUCTION="dump_ssh"
                ;;
        esac
    done < "$KDUMP_CONF_PARSED"
}

fence_kdump_notify() {
    if [ -n "$FENCE_KDUMP_NODES" ]; then
        # shellcheck disable=SC2086
        $FENCE_KDUMP_SEND $FENCE_KDUMP_ARGS $FENCE_KDUMP_NODES &
    fi
}

kdump_test_mark_success() {
    [ -n "$KDUMP_TEST_STATUS" ] || return

    _status="success kdump_test_id=$KDUMP_TEST_ID"

    if is_ssh_dump_target; then
        echo "$_status" | _curl -T "-" "sftp://$SSH_HOST/$KDUMP_TEST_STATUS"
    else
        echo "$_status" > "$KDUMP_TEST_STATUS"
        sync -f "$KDUMP_TEST_STATUS"
    fi
}

kdump_test_init() {
    is_raw_dump_target && return

    KDUMP_TEST_ID=$(getarg kdump_test_id=)
    [ -z "$KDUMP_TEST_ID" ] && return

    KDUMP_PATH="${KDUMP_PATH%/*}"
    KDUMP_PATH="$KDUMP_PATH/kdump-test-$KDUMP_TEST_ID"
    KDUMP_TEST_STATUS="$KDUMP_PATH/vmcore-creation.status"
}

for _core in "/sys/firmware/opal/mpipl/core" "/sys/firmware/opal/core"; do
    [ -f "$_core" ] || continue
    OPALCORE="$_core"
    break
done

if [ "$1" = "--error-handler" ]; then
    get_kdump_confs
    do_failure_action
    save_log
    do_final_action

    exit $?
fi

# continue here only if we have to save dump.
if [ -f /etc/fadump.initramfs ] && [ ! -f /proc/device-tree/rtas/ibm,kernel-dump ] && [ ! -f /proc/device-tree/ibm,opal/dump/mpipl-boot ]; then
    exit 0
fi

read_kdump_confs
fence_kdump_notify

if ! get_host_ip; then
    derror "get_host_ip exited with non-zero status!"
    exit 1
fi

if [ -z "$DUMP_INSTRUCTION" ]; then
    DUMP_INSTRUCTION="dump_fs"
fi

KDUMP_PATH="$KDUMP_PATH/$HOST_IP-$(date +%Y-%m-%d-%T)"
[ "$DUMP_INSTRUCTION" = "dump_fs" ] && KDUMP_PATH="$NEWROOT/$KDUMP_PATH"
KDUMP_PATH="$(echo "$KDUMP_PATH" | tr -s /)"

kdump_test_init
if ! do_kdump_pre; then
    derror "kdump_pre script exited with non-zero status!"
    do_final_action
    # During systemd service to reboot the machine, stop this shell script running
    exit 1
fi
make_trace_mem "kdump saving vmcore" '1:shortmem' '2+:mem' '3+:slab'
do_dump
DUMP_RETVAL=$?

if ! do_kdump_post $DUMP_RETVAL; then
    derror "kdump_post script exited with non-zero status!"
fi

save_log

if [ $DUMP_RETVAL -ne 0 ]; then
    exit 1
fi

kdump_test_mark_success
do_final_action
