#!/bin/bash
# $1: target arch

SED_EXP=""

generate()
{
	sed "$SED_EXP" << EOF
# This file contains a series of commands to perform (in order) in the kdump
# kernel after a kernel crash in the crash kernel(1st kernel) has happened.
#
# Directives in this file are only applicable to the kdump initramfs, and have
# no effect once the root filesystem is mounted and the normal init scripts are
# processed.
#
# Currently, only one dump target and path can be specified.  If the dumping to
# the configured target fails, the failure action which can be configured via
# the "failure_action" directive will be performed.
#
# Supported options:
#
# auto_reset_crashkernel <yes|no>
#           - whether to reset kernel crashkernel to new default value
#             or not when kdump-utils updates the default crashkernel value and
#             existing kernels using the old default kernel crashkernel value.
#             The default value is yes. Note the user-specified value will be
#             overwritten to the default crahskernel value.
#
# raw <partition>
#           - Will dd /proc/vmcore into <partition>.
#             Use persistent device names for partition devices,
#             such as /dev/vg/<devname>.
#
# nfs <nfs mount>
#           - Will mount nfs to <mnt>, and copy /proc/vmcore to
#             <mnt>/<path>/%HOST-%DATE/, supports DNS.
#
# ssh <user@server>
#           - Will save /proc/vmcore to <user@server>:<path>/%HOST-%DATE/,
#             supports DNS.
#             NOTE: make sure the user has write permissions on the server.
#
# sshkey <path>
#           - Will use the sshkey to do ssh dump.
#             Specify the path of the ssh key to use when dumping
#             via ssh. The default value is /root/.ssh/kdump_id_rsa.
#
# <fs type> <partition>
#           - Will mount -t <fs type> <partition> <mnt>, and copy
#             /proc/vmcore to <mnt>/<path>/%HOST_IP-%DATE/.
#             NOTE: <partition> can be a device node, label or uuid.
#             It's recommended to use persistent device names
#             such as /dev/vg/<devname>.
#             Otherwise it's suggested to use label or uuid.
#             Supported fs types: ext[234], xfs, btrfs, minix, virtiofs
#
# path <path>
#           - "path" represents the file system path in which vmcore
#             will be saved.  If a dump target is specified in
#             kdump.conf, then "path" is relative to the specified
#             dump target.
#
#             Interpretation of "path" changes a bit if the user didn't
#             specify any dump target explicitly in kdump.conf.  In this
#             case, "path" represents the absolute path from root. The
#             dump target and adjusted path are arrived at automatically
#             depending on what's mounted in the current system.
#
#             Ignored for raw device dumps.  If unset, will use the default
#             "/var/crash".
#
# core_collector <command> <options>
#           - This allows you to specify the command to copy
#             the vmcore.  The default is makedumpfile, which on
#             some architectures can drastically reduce vmcore size.
#             See /sbin/makedumpfile --help for a list of options.
#             Note that the -i and -g options are not needed here,
#             as the initrd will automatically be populated with a
#             config file appropriate for the running kernel.
#             The default core_collector for raw/ssh dump is:
#             "makedumpfile -F -l --message-level 7 -d 31".
#             The default core_collector for other targets is:
#             "makedumpfile -l --message-level 7 -d 31".
#
#             "makedumpfile -F" will create a flattened vmcore.
#             You need to use "makedumpfile -R" to rearrange the dump data to
#             a normal dumpfile readable with analysis tools.  For example:
#             "makedumpfile -R vmcore < vmcore.flat".
#
#             For core_collector format details, you can refer to
#             kexec-kdump-howto.txt or kdump.conf manpage.
#
# kdump_post <binary | script>
#           - This directive allows you to run a executable binary
#             or script after the vmcore dump process terminates.
#             The exit status of the current dump process is fed to
#             the executable binary or script as its first argument.
#             All files under /etc/kdump/post.d are collectively sorted
#             and executed in lexical order, before binary or script
#             specified kdump_post parameter is executed.
#
# kdump_pre <binary | script>
#           - Works like the "kdump_post" directive, but instead of running
#             after the dump process, runs immediately before it.
#             Exit status of this binary is interpreted as follows:
#               0 - continue with dump process as usual
#               non 0 - run the final action (reboot/poweroff/halt)
#             All files under /etc/kdump/pre.d are collectively sorted and
#             executed in lexical order, after binary or script specified
#             kdump_pre parameter is executed.
#             Even if the binary or script in /etc/kdump/pre.d directory
#             returns non 0 exit status, the processing is continued.
#
# extra_bins <binaries | shell scripts>
#           - This directive allows you to specify additional binaries or
#             shell scripts to be included in the kdump initrd.
#             Generally they are useful in conjunction with a kdump_post
#             or kdump_pre binary or script which depends on these extra_bins.
#
# extra_modules <module(s)>
#           - This directive allows you to specify extra kernel modules
#             that you want to be loaded in the kdump initrd.
#             Multiple modules can be listed, separated by spaces, and any
#             dependent modules will automatically be included.
#
# failure_action <reboot | halt | poweroff | shell | dump_to_rootfs>
#           - Action to perform in case dumping fails.
#             reboot:   Reboot the system.
#             halt:     Halt the system.
#             poweroff: Power down the system.
#             shell:    Drop to a bash shell.
#                       Exiting the shell reboots the system by default,
#                       or perform "final_action".
#             dump_to_rootfs:  Dump vmcore to rootfs from initramfs context and
#                       reboot by default or perform "final_action".
#                       Useful when non-root dump target is specified.
#             The default option is "reboot".
#
# default <reboot | halt | poweroff | shell | dump_to_rootfs>
#           - Same as the "failure_action" directive above, but this directive
#             is obsolete and will be removed in the future.
#
# final_action <reboot | halt | poweroff>
#           - Action to perform in case dumping succeeds. Also performed
#             when "shell" or "dump_to_rootfs" failure action finishes.
#             Each action is same as the "failure_action" directive above.
#             The default is "reboot".
#
# force_rebuild <0 | 1>
#           - By default, kdump initrd will only be rebuilt when necessary.
#             Specify 1 to force rebuilding kdump initrd every time when kdump
#             service starts.
#
# force_no_rebuild <0 | 1>
#           - By default, kdump initrd will be rebuilt when necessary.
#             Specify 1 to bypass rebuilding of kdump initrd.
#
#             force_no_rebuild and force_rebuild options are mutually
#             exclusive and they should not be set to 1 simultaneously.
#
# dracut_args <arg(s)>
#           - Pass extra dracut options when rebuilding kdump initrd.
#
# fence_kdump_args <arg(s)>
#           - Command line arguments for fence_kdump_send (it can contain
#             all valid arguments except hosts to send notification to).
#
# fence_kdump_nodes <node(s)>
#           - List of cluster node(s) except localhost, separated by spaces,
#             to send fence_kdump notifications to.
#             (this option is mandatory to enable fence_kdump).
#

#raw /dev/vg/lv_kdump
#ext4 /dev/vg/lv_kdump
#ext4 LABEL=/boot
#ext4 UUID=03138356-5e61-4ab3-b58e-27507ac41937
#virtiofs myfs
#nfs my.server.com:/export/tmp
#nfs [2001:db8::1:2:3:4]:/export/tmp
#ssh user@my.server.com
#ssh user@2001:db8::1:2:3:4
#sshkey /root/.ssh/kdump_id_rsa
auto_reset_crashkernel yes
path /var/crash
core_collector makedumpfile -l --message-level 7 -d 31
#core_collector scp
#kdump_post /var/crash/scripts/kdump-post.sh
#kdump_pre /var/crash/scripts/kdump-pre.sh
#extra_bins /usr/bin/lftp
#extra_modules gfs2
#failure_action shell
#force_rebuild 1
#force_no_rebuild 1
#dracut_args --omit-drivers "cfg80211 snd" --add-drivers "ext2 ext3"
#fence_kdump_args -p 7410 -f auto -c 0 -i 10
#fence_kdump_nodes node1 node2
EOF
}

update_param()
{
	SED_EXP="${SED_EXP}s/^$1.*$/$1 $2/;"
}

case "$1" in
aarch64) ;;

i386) ;;

ppc64) ;;

ppc64le) ;;

s390x)
	update_param core_collector \
		"makedumpfile -c --message-level 7 -d 31"
	;;
x86_64) ;;

*)
	echo "Warning: Unknown architecture '$1', using default kdump.conf template." >&2
	;;
esac

generate
