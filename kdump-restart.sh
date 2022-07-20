#!/bin/bash
export PATH="$PATH:/usr/bin:/usr/sbin"

exec >> /var/log/kdump-migration.log 2>&1

echo "kdump: Partition Migration detected. Rebuilding initramfs image to reload."
/usr/bin/kdumpctl rebuild
/usr/bin/kdumpctl reload
