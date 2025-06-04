#!/bin/sh

if ! systemctl is-active kdump; then
	exit 0
fi

/usr/lib/kdump/kdump-restart.sh
