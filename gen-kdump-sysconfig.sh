#!/bin/bash
# $1: target arch

SED_EXP=""

generate()
{
	sed "$SED_EXP" << EOF
# Kernel Version string for the -kdump kernel, such as 2.6.13-1544.FC5kdump
# If no version is specified, then the init script will try to find a
# kdump kernel with the same version number as the running kernel.
KDUMP_KERNELVER=""

# The kdump commandline is the command line that needs to be passed off to
# the kdump kernel.  This will likely match the contents of the grub kernel
# line.  For example:
#   KDUMP_COMMANDLINE="ro root=LABEL=/"
# Dracut depends on proper root= options, so please make sure that appropriate
# root= options are copied from /proc/cmdline. In general it is best to append
# command line options using "KDUMP_COMMANDLINE_APPEND=".
# If a command line is not specified, the default will be taken from
# /proc/cmdline
KDUMP_COMMANDLINE=""

# This variable lets us remove arguments from the current kdump commandline
# as taken from either KDUMP_COMMANDLINE above, or from /proc/cmdline
# NOTE: some arguments such as crashkernel will always be removed
KDUMP_COMMANDLINE_REMOVE="hugepages hugepagesz slub_debug quiet log_buf_len swiotlb cma hugetlb_cma ignition.firstboot"

# This variable lets us append arguments to the current kdump commandline
# after processed by KDUMP_COMMANDLINE_REMOVE
KDUMP_COMMANDLINE_APPEND="irqpoll maxcpus=1 reset_devices novmcoredd cma=0 hugetlb_cma=0"

# Any additional kexec arguments required.  In most situations, this should
# be left empty
#
# Example:
#   KEXEC_ARGS="--elf32-core-headers"
KEXEC_ARGS=""

#Where to find the boot image
#KDUMP_BOOTDIR="/boot"

#What is the image type used for kdump
KDUMP_IMG="vmlinuz"

#What is the images extension.  Relocatable kernels don't have one
KDUMP_IMG_EXT=""

# Logging is controlled by following variables in the first kernel:
#   - @var KDUMP_STDLOGLVL - logging level to standard error (console output)
#   - @var KDUMP_SYSLOGLVL - logging level to syslog (by logger command)
#   - @var KDUMP_KMSGLOGLVL - logging level to /dev/kmsg (only for boot-time)
#
# In the second kernel, kdump will use the rd.kdumploglvl option to set the
# log level in the above KDUMP_COMMANDLINE_APPEND.
#   - @var rd.kdumploglvl - logging level to syslog (by logger command)
#   - for example: add the rd.kdumploglvl=3 option to KDUMP_COMMANDLINE_APPEND
#
# Logging levels: no logging(0), error(1),warn(2),info(3),debug(4)
#
# KDUMP_STDLOGLVL=3
# KDUMP_SYSLOGLVL=0
# KDUMP_KMSGLOGLVL=0
EOF
}

update_param()
{
	SED_EXP="${SED_EXP}s/^$1=.*$/$1=\"$2\"/;"
}

case "$1" in
aarch64)
	update_param KEXEC_ARGS "-s"
	update_param KDUMP_COMMANDLINE_APPEND \
		"irqpoll nr_cpus=1 reset_devices cgroup_disable=memory udev.children-max=2 panic=10 swiotlb=noforce novmcoredd cma=0 hugetlb_cma=0"
	;;
i386)
	update_param KDUMP_COMMANDLINE_APPEND \
		"irqpoll nr_cpus=1 reset_devices numa=off udev.children-max=2 panic=10 transparent_hugepage=never novmcoredd cma=0 hugetlb_cma=0"
	;;
ppc64)
	update_param KEXEC_ARGS "--dt-no-old-root"
	update_param KDUMP_COMMANDLINE_REMOVE \
		"hugepages hugepagesz slub_debug quiet log_buf_len swiotlb hugetlb_cma ignition.firstboot"
	update_param KDUMP_COMMANDLINE_APPEND \
		"irqpoll maxcpus=1 noirqdistrib reset_devices cgroup_disable=memory numa=off udev.children-max=2 ehea.use_mcs=0 panic=10 kvm_cma_resv_ratio=0 transparent_hugepage=never novmcoredd hugetlb_cma=0"
	;;
ppc64le)
	update_param KEXEC_ARGS "--dt-no-old-root -s"
	update_param KDUMP_COMMANDLINE_REMOVE \
		"hugepages hugepagesz slub_debug quiet log_buf_len swiotlb hugetlb_cma ignition.firstboot"
	update_param KDUMP_COMMANDLINE_APPEND \
		"irqpoll maxcpus=1 noirqdistrib reset_devices cgroup_disable=memory numa=off udev.children-max=2 ehea.use_mcs=0 panic=10 kvm_cma_resv_ratio=0 transparent_hugepage=never novmcoredd hugetlb_cma=0"
	;;
s390x)
	update_param KEXEC_ARGS "-s"
	update_param KDUMP_COMMANDLINE_REMOVE \
		"hugepages hugepagesz slub_debug quiet log_buf_len swiotlb vmcp_cma cma hugetlb_cma prot_virt ignition.firstboot"
	update_param KDUMP_COMMANDLINE_APPEND \
		"nr_cpus=1 cgroup_disable=memory numa=off udev.children-max=2 panic=10 transparent_hugepage=never novmcoredd vmcp_cma=0 cma=0 hugetlb_cma=0"
	;;
x86_64)
	update_param KEXEC_ARGS "-s"
	update_param KDUMP_COMMANDLINE_APPEND \
		"irqpoll nr_cpus=1 reset_devices cgroup_disable=memory mce=off numa=off udev.children-max=2 panic=10 acpi_no_memhotplug transparent_hugepage=never nokaslr hest_disable novmcoredd cma=0 hugetlb_cma=0"
	;;
*)
	echo "Warning: Unknown architecture '$1', using default sysconfig template."
	;;
esac

generate
