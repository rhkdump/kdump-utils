#!/bin/sh
#
_devuuid=$(getarg kdump_luks_uuid=)

if [[ -n $_devuuid ]]; then
	_key_desc=cryptsetup:$_devuuid
	echo -n "$_key_desc" > /sys/kernel/crash_dm_crypt_keys
fi
