#!/bin/sh

KDUMP_PATH="/var/crash"
CORE_COLLECTOR="makedumpfile -d 31 -c"

read_kdump_conf()
{
    local conf_file="/etc/kdump.conf"
    if [ -f "$conf_file" ]; then
        while read config_opt config_val;
        do
	    case "$config_opt" in
	    path)
                KDUMP_PATH="$config_val"
	        ;;
            core_collector)
		CORE_COLLECTOR="$config_val"
                ;;
            default)
                ;;
	    esac
        done < $conf_file
    fi
}

do_default_action()
{
    return
}

