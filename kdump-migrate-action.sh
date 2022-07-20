#!/bin/sh

systemctl is-active kdump
if [ $? -ne 0 ]; then
	exit 0
fi

/usr/lib/kdump/kdump-restart.sh
