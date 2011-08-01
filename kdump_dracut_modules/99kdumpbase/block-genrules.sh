#!/bin/sh

. /lib/dracut-lib.sh

while read config_opt config_val;
do
    case "$config_opt" in
    ext[234]|xfs|btrfs|minix|raw)
        udevmatch $config_val >> $UDEVRULESD/99-localfs.rules
    ;;
    esac
done < /etc/kdump.conf


