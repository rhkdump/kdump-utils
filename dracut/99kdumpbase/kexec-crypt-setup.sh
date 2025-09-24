#!/bin/sh
#
LUKS_CONFIGFS_RESTORE=/sys/kernel/config/crash_dm_crypt_keys/restore
RESTORED=1
MAX_WAIT_TIME=10
wait_time=0

while [ $wait_time -lt $MAX_WAIT_TIME ]; do
    [ -e $LUKS_CONFIGFS_RESTORE ] && break
    sleep 1
    wait_time=$((wait_time + 1))
done

if [ $wait_time -ge $MAX_WAIT_TIME ]; then
    echo "$LUKS_CONFIGFS_RESTORE isn't ready after ${MAX_WAIT_TIME}s, something wrong!"
    exit 1
fi

if ! grep -q "$RESTORED" "$LUKS_CONFIGFS_RESTORE"; then
    echo $RESTORED > $LUKS_CONFIGFS_RESTORE
fi
