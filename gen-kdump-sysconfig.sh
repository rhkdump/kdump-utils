#!/bin/bash
#
# Generate /etc/sysconfig/kdump content for different architectures.
#
# Usage:
#       $0 [arch]
#
# if [arch] is not specified, the default values will be used.
#

declare -A KEXEC_ARGS=(
	[default]=""
	[aarch64]="-s"
	[ppc64]="--dt-no-old-root"
	[ppc64le]="-s"
	[s390x]="-s"
	[x86_64]="-s"
)

declare -A KDUMP_COMMANDLINE_REMOVE=(
	[default]="hugepages hugepagesz slub_debug quiet log_buf_len swiotlb cma hugetlb_cma ignition.firstboot"
	[ppc64]="hugepages hugepagesz slub_debug quiet log_buf_len swiotlb hugetlb_cma ignition.firstboot"
	[ppc64le]="hugepages hugepagesz slub_debug quiet log_buf_len swiotlb hugetlb_cma ignition.firstboot"
	[s390x]="hugepages hugepagesz slub_debug quiet log_buf_len swiotlb vmcp_cma cma hugetlb_cma prot_virt ignition.firstboot zfcp.allow_lun_scan"
)

declare -A KDUMP_COMMANDLINE_APPEND=(
	[default]="irqpoll maxcpus=1 reset_devices novmcoredd cma=0 hugetlb_cma=0 initramfs_options=size=90%"
	[aarch64]="irqpoll nr_cpus=1 reset_devices cgroup_disable=memory udev.children-max=2 panic=10 swiotlb=noforce novmcoredd cma=0 hugetlb_cma=0 kfence.sample_interval=0 initramfs_options=size=90%"
	[i386]="irqpoll nr_cpus=1 reset_devices numa=off udev.children-max=2 panic=10 transparent_hugepage=never novmcoredd cma=0 hugetlb_cma=0 kfence.sample_interval=0 initramfs_options=size=90%"
	[ppc64]="irqpoll maxcpus=1 noirqdistrib reset_devices cgroup_disable=memory numa=off udev.children-max=2 ehea.use_mcs=0 panic=10 kvm_cma_resv_ratio=0 transparent_hugepage=never novmcoredd hugetlb_cma=0 kfence.sample_interval=0 initramfs_options=size=90%"
	[ppc64le]="irqpoll nr_cpus=16 noirqdistrib reset_devices cgroup_disable=memory numa=off udev.children-max=2 ehea.use_mcs=0 panic=10 kvm_cma_resv_ratio=0 transparent_hugepage=never novmcoredd hugetlb_cma=0 kfence.sample_interval=0 initramfs_options=size=90%"
	[s390x]="nr_cpus=1 cgroup_disable=memory numa=off udev.children-max=2 panic=10 transparent_hugepage=never novmcoredd vmcp_cma=0 cma=0 hugetlb_cma=0 kfence.sample_interval=0 initramfs_options=size=90%"
	[x86_64]="irqpoll nr_cpus=1 reset_devices cgroup_disable=memory mce=off numa=off udev.children-max=2 panic=10 acpi_no_memhotplug transparent_hugepage=never nokaslr hest_disable novmcoredd cma=0 hugetlb_cma=0 pcie_ports=compat kfence.sample_interval=0 initramfs_options=size=90%"
)

declare -A FADUMP_COMMANDLINE_APPEND=(
	[default]=""
	[ppc64le]="nr_cpus=16 numa=off cgroup_disable=memory cma=0 kvm_cma_resv_ratio=0 hugetlb_cma=0 transparent_hugepage=never novmcoredd udev.children-max=2"
)

arch="$1"
declare -A known_arches_map=([aarch64]=1 [i386]=1 [ppc64]=1 [ppc64le]=1 [s390x]=1 [x86_64]=1)
if [[ -z $arch || -z ${known_arches_map[$arch]} ]]; then
	echo "Warning: Unknown architecture '$arch', using default sysconfig template." >&2
	arch="default"
fi

#
# Generate the config file
#
cat << EOF
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
KDUMP_COMMANDLINE_REMOVE="${KDUMP_COMMANDLINE_REMOVE[$arch]-${KDUMP_COMMANDLINE_REMOVE[default]}}"

# This variable lets us append arguments to the current kdump commandline
# after processed by KDUMP_COMMANDLINE_REMOVE
KDUMP_COMMANDLINE_APPEND="${KDUMP_COMMANDLINE_APPEND[$arch]-${KDUMP_COMMANDLINE_APPEND[default]}}"

# This variable lets us append arguments to fadump (powerpc) capture kernel,
# further to the parameters passed via the bootloader.
FADUMP_COMMANDLINE_APPEND="${FADUMP_COMMANDLINE_APPEND[$arch]-${FADUMP_COMMANDLINE_APPEND[default]}}"

# Any additional kexec arguments required.  In most situations, this should
# be left empty
#
# Example:
#   KEXEC_ARGS="--elf32-core-headers"
KEXEC_ARGS="${KEXEC_ARGS[$arch]-${KEXEC_ARGS[default]}}"

#Where to find the boot image
#KDUMP_BOOTDIR="/boot"

#What is the image type used for kdump
KDUMP_IMG="vmlinuz"

#What is the images extension.  Relocatable kernels don't have one
KDUMP_IMG_EXT=""

# Enable vmcore creation notification by default, disable by setting
# VMCORE_CREATION_NOTIFICATION=""
VMCORE_CREATION_NOTIFICATION="yes"

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
