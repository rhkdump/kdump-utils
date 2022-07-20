#!/bin/sh
#
# This comes from the dracut-logger.sh
#
# The logger defined 4 logging levels:
#   - ddebug (4)
#     The DEBUG Level designates fine-grained informational events that are most
#     useful to debug an application.
#   - dinfo (3)
#     The INFO level designates informational messages that highlight the
#     progress of the application at coarse-grained level.
#   - dwarn (2)
#     The WARN level designates potentially harmful situations.
#   - derror (1)
#     The ERROR level designates error events that might still allow the
#     application to continue running.
#
# Logging is controlled by following global variables:
#   - @var kdump_stdloglvl - logging level to standard error (console output)
#   - @var kdump_sysloglvl - logging level to syslog (by logger command)
#   - @var kdump_kmsgloglvl - logging level to /dev/kmsg (only for boot-time)
#
# If any of the variables is not set, the function dlog_init() sets it to default:
#   - In the first kernel:
#     - @var kdump_stdloglvl = 3 (info)
#     - @var kdump_sysloglvl = 0 (no logging)
#     - @var kdump_kmsgloglvl = 0 (no logging)
#
#   -In the second kernel:
#    - @var kdump_stdloglvl = 0 (no logging)
#    - @var kdump_sysloglvl = 3 (info)
#    - @var kdump_kmsgloglvl = 0 (no logging)
#
# First of all you have to start with dlog_init() function which initializes
# required variables. Don't call any other logging function before that one!
#
# The code in this file might be run in an environment without bash.
# Any code added must be POSIX compliant.

# Define vairables for the log levels in this module.
kdump_stdloglvl=""
kdump_sysloglvl=""
kdump_kmsgloglvl=""

# The dracut-lib.sh is only available in the second kernel, and it won't
# be used in the first kernel because the dracut-lib.sh is invisible in
# the first kernel.
if [ -f /lib/dracut-lib.sh ]; then
	. /lib/dracut-lib.sh
fi

# @brief Get the log level from kernel command line.
# @retval 1 if something has gone wrong
# @retval 0 on success.
#
get_kdump_loglvl()
{
	[ -f /lib/dracut-lib.sh ] && kdump_sysloglvl=$(getarg rd.kdumploglvl)
	[ -z "$kdump_sysloglvl" ] && return 1

	if [ -f /lib/dracut-lib.sh ] && ! isdigit "$kdump_sysloglvl"; then
		return 1
	fi

	return 0
}

# @brief Check the log level.
# @retval 1 if something has gone wrong
# @retval 0 on success.
#
check_loglvl()
{
	case "$1" in
	0 | 1 | 2 | 3 | 4)
		return 0
		;;
	*)
		return 1
		;;
	esac
}

# @brief Initializes Logger.
# @retval 1 if something has gone wrong
# @retval 0 on success.
#
dlog_init()
{
	ret=0

	if [ -s /proc/vmcore ]; then
		if ! get_kdump_loglvl; then
			logger -t "kdump[$$]" -p warn -- "Kdump is using the default log level(3)."
			kdump_sysloglvl=3
		fi
		kdump_stdloglvl=0
		kdump_kmsgloglvl=0
	else
		kdump_stdloglvl=$KDUMP_STDLOGLVL
		kdump_sysloglvl=$KDUMP_SYSLOGLVL
		kdump_kmsgloglvl=$KDUMP_KMSGLOGLVL
	fi

	[ -z "$kdump_stdloglvl" ] && kdump_stdloglvl=3
	[ -z "$kdump_sysloglvl" ] && kdump_sysloglvl=0
	[ -z "$kdump_kmsgloglvl" ] && kdump_kmsgloglvl=0

	for loglvl in "$kdump_stdloglvl" "$kdump_kmsgloglvl" "$kdump_sysloglvl"; do
		if ! check_loglvl "$loglvl"; then
			echo "Illegal log level: $kdump_stdloglvl $kdump_kmsgloglvl $kdump_sysloglvl"
			return 1
		fi
	done

	# Skip initialization if it's already done.
	[ -n "$kdump_maxloglvl" ] && return 0

	if [ "$UID" -ne 0 ]; then
		kdump_kmsgloglvl=0
		kdump_sysloglvl=0
	fi

	if [ "$kdump_sysloglvl" -gt 0 ]; then
		if [ -d /run/systemd/journal ] &&
			systemd-cat --version 1> /dev/null 2>&1 &&
			systemctl --quiet is-active systemd-journald.socket 1> /dev/null 2>&1; then
			readonly _systemdcatfile="/var/tmp/systemd-cat"
			mkfifo "$_systemdcatfile" 1> /dev/null 2>&1
			readonly _dlogfd=15
			systemd-cat -t 'kdump' --level-prefix=true < "$_systemdcatfile" &
			exec 15> "$_systemdcatfile"
		elif ! [ -S /dev/log ] && [ -w /dev/log ] || ! command -v logger > /dev/null; then
			# We cannot log to syslog, so turn this facility off.
			kdump_kmsgloglvl=$kdump_sysloglvl
			kdump_sysloglvl=0
			ret=1
			errmsg="No '/dev/log' or 'logger' included for syslog logging"
		fi
	fi

	kdump_maxloglvl=0
	for _dlog_lvl in $kdump_stdloglvl $kdump_sysloglvl $kdump_kmsgloglvl; do
		[ $_dlog_lvl -gt $kdump_maxloglvl ] && kdump_maxloglvl=$_dlog_lvl
	done
	readonly kdump_maxloglvl
	export kdump_maxloglvl

	if [ $kdump_stdloglvl -lt 4 ] && [ $kdump_kmsgloglvl -lt 4 ] && [ $kdump_sysloglvl -lt 4 ]; then
		unset ddebug
		ddebug()
		{
			:
		}
	fi

	if [ $kdump_stdloglvl -lt 3 ] && [ $kdump_kmsgloglvl -lt 3 ] && [ $kdump_sysloglvl -lt 3 ]; then
		unset dinfo
		dinfo()
		{
			:
		}
	fi

	if [ $kdump_stdloglvl -lt 2 ] && [ $kdump_kmsgloglvl -lt 2 ] && [ $kdump_sysloglvl -lt 2 ]; then
		unset dwarn
		dwarn()
		{
			:
		}
		unset dwarning
		dwarning()
		{
			:
		}
	fi

	if [ $kdump_stdloglvl -lt 1 ] && [ $kdump_kmsgloglvl -lt 1 ] && [ $kdump_sysloglvl -lt 1 ]; then
		unset derror
		derror()
		{
			:
		}
	fi

	[ -n "$errmsg" ] && derror "$errmsg"

	return $ret
}

## @brief Converts numeric level to logger priority defined by POSIX.2.
#
# @param $1: Numeric logging level in range from 1 to 4.
# @retval 1 if @a lvl is out of range.
# @retval 0 if @a lvl is correct.
# @result Echoes logger priority.
_lvl2syspri()
{
	case "$1" in
	1) echo error ;;
	2) echo warning ;;
	3) echo info ;;
	4) echo debug ;;
	*) return 1 ;;
	esac
}

## @brief Converts logger numeric level to syslog log level
#
# @param $1: Numeric logging level in range from 1 to 4.
# @retval 1 if @a lvl is out of range.
# @retval 0 if @a lvl is correct.
# @result Echoes kernel console numeric log level
#
# Conversion is done as follows:
#
# <tt>
#   none     -> LOG_EMERG (0)
#   none     -> LOG_ALERT (1)
#   none     -> LOG_CRIT (2)
#   ERROR(1) -> LOG_ERR (3)
#   WARN(2)  -> LOG_WARNING (4)
#   none     -> LOG_NOTICE (5)
#   INFO(3)  -> LOG_INFO (6)
#   DEBUG(4) -> LOG_DEBUG (7)
# </tt>
#
# @see /usr/include/sys/syslog.h
_dlvl2syslvl()
{
	case "$1" in
	1) set -- 3 ;;
	2) set -- 4 ;;
	3) set -- 6 ;;
	4) set -- 7 ;;
	*) return 1 ;;
	esac

	# The number is constructed by multiplying the facility by 8 and then
	# adding the level.
	# About The Syslog Protocol, please refer to the RFC5424 for more details.
	echo $((24 + $1))
}

## @brief Prints to stderr, to syslog and/or /dev/kmsg given message with
#  given level (priority).
#
# @param $1: Numeric logging level.
# @param $2: Message.
# @retval 0 It's always returned, even if logging failed.
#
# @note This function is not supposed to be called manually. Please use
# dinfo(), ddebug(), or others instead which wrap this one.
#
# This is core logging function which logs given message to standard error
# and/or syslog (with POSIX shell command <tt>logger</tt>) and/or to /dev/kmsg.
# The format is following:
#
# <tt>X: some message</tt>
#
# where @c X is the first letter of logging level. See module description for
# details on that.
#
# Message to syslog is sent with tag @c kdump. Priorities are mapped as
# following:
#   - @c ERROR to @c error
#   - @c WARN to @c warning
#   - @c INFO to @c info
#   - @c DEBUG to @c debug
_do_dlog()
{
	[ "$1" -le $kdump_stdloglvl ] && printf -- 'kdump: %s\n' "$2" >&2

	if [ "$1" -le $kdump_sysloglvl ]; then
		if [ "$_dlogfd" ]; then
			printf -- "<%s>%s\n" "$(($(_dlvl2syslvl "$1") & 7))" "$2" 1>&$_dlogfd
		else
			logger -t "kdump[$$]" -p "$(_lvl2syspri "$1")" -- "$2"
		fi
	fi

	[ "$1" -le $kdump_kmsgloglvl ] &&
		echo "<$(_dlvl2syslvl "$1")>kdump[$$] $2" > /dev/kmsg
}

## @brief Internal helper function for _do_dlog()
#
# @param $1: Numeric logging level.
# @param $2 [...]: Message.
# @retval 0 It's always returned, even if logging failed.
#
# @note This function is not supposed to be called manually. Please use
# dinfo(), ddebug(), or others instead which wrap this one.
#
# This function calls _do_dlog() either with parameter msg, or if
# none is given, it will read standard input and will use every line as
# a message.
#
# This enables:
# dwarn "This is a warning"
# echo "This is a warning" | dwarn
dlog()
{
	[ -z "$kdump_maxloglvl" ] && return 0
	[ "$1" -le "$kdump_maxloglvl" ] || return 0

	if [ $# -gt 1 ]; then
		_dlog_lvl=$1
		shift
		_do_dlog "$_dlog_lvl" "$*"
	else
		while read -r line || [ -n "$line" ]; do
			_do_dlog "$1" "$line"
		done
	fi
}

## @brief Logs message at DEBUG level (4)
#
# @param msg Message.
# @retval 0 It's always returned, even if logging failed.
ddebug()
{
	set +x
	dlog 4 "$@"
	if [ -n "$debug" ]; then
		set -x
	fi
}

## @brief Logs message at INFO level (3)
#
# @param msg Message.
# @retval 0 It's always returned, even if logging failed.
dinfo()
{
	set +x
	dlog 3 "$@"
	if [ -n "$debug" ]; then
		set -x
	fi
}

## @brief Logs message at WARN level (2)
#
# @param msg Message.
# @retval 0 It's always returned, even if logging failed.
dwarn()
{
	set +x
	dlog 2 "$@"
	if [ -n "$debug" ]; then
		set -x
	fi
}

## @brief It's an alias to dwarn() function.
#
# @param msg Message.
# @retval 0 It's always returned, even if logging failed.
dwarning()
{
	set +x
	dwarn "$@"
	if [ -n "$debug" ]; then
		set -x
	fi
}

## @brief Logs message at ERROR level (1)
#
# @param msg Message.
# @retval 0 It's always returned, even if logging failed.
derror()
{
	set +x
	dlog 1 "$@"
	if [ -n "$debug" ]; then
		set -x
	fi
}
