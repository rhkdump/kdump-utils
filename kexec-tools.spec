Name: kexec-tools
Version: 2.0.8
Release: 6%{?dist}
License: GPLv2
Group: Applications/System
Summary: The kexec/kdump userspace component
Source0: http://kernel.org/pub/linux/utils/kernel/kexec/%{name}-%{version}.tar.xz
Source1: kdumpctl
Source2: kdump.sysconfig
Source3: kdump.sysconfig.x86_64
Source4: kdump.sysconfig.i386
Source5: kdump.sysconfig.ppc64
Source7: mkdumprd
Source8: kdump.conf
Source9: http://downloads.sourceforge.net/project/makedumpfile/makedumpfile/1.5.7/makedumpfile-1.5.7.tar.gz
Source10: kexec-kdump-howto.txt
Source12: mkdumprd.8
Source14: 98-kexec.rules
Source15: kdump.conf.5
Source16: kdump.service
Source17: rhcrashkernel-param
Source18: kdump.sysconfig.s390x
Source19: eppic_030413.tar.gz
Source20: kdump-lib.sh
Source21: kdump-in-cluster-environment.txt
Source22: kdump-dep-generator.sh
Source23: kdump-anaconda-addon-005-2-g86366ae.tar.gz
Source24: kdump-lib-initramfs.sh
Source25: kdump.sysconfig.ppc64le

#######################################
# These are sources for mkdumpramfs
# Which is currently in development
#######################################
Source100: dracut-kdump.sh
Source101: dracut-module-setup.sh
Source102: dracut-monitor_dd_progress
Source103: dracut-kdump-error-handler.sh
Source104: dracut-kdump-emergency.service
Source105: dracut-kdump-error-handler.service
Source106: dracut-kdump-capture.service

Requires(post): systemd-units
Requires(preun): systemd-units
Requires(postun): systemd-units
Requires(pre): coreutils sed zlib 
Requires: dracut, dracut-network, ethtool
BuildRequires: zlib-devel zlib zlib-static elfutils-devel-static glib2-devel bzip2-devel ncurses-devel bison flex lzo-devel snappy-devel
BuildRequires: pkgconfig intltool gettext 
BuildRequires: systemd-units
%ifarch %{ix86} x86_64 ppc64 ppc s390x ppc64le
Obsoletes: diskdumputils netdump kexec-tools-eppic
%endif

ExcludeArch: aarch64

#START INSERT

#
# Patches 0 through 100 are meant for x86 kexec-tools enablement
#

#
# Patches 101 through 200 are meant for x86_64 kexec-tools enablement
#

#
# Patches 301 through 400 are meant for ppc64 kexec-tools enablement
#

#
# Patches 401 through 500 are meant for s390 kexec-tools enablement
#
#
# Patches 501 through 600 are meant for ppc kexec-tools enablement
#

#
# Patches 601 onward are generic patches
#
Patch601: kexec-tools-2.0.3-disable-kexec-test.patch

%description
kexec-tools provides /sbin/kexec binary that facilitates a new
kernel to boot using the kernel's kexec feature either on a
normal or a panic reboot. This package contains the /sbin/kexec
binary and ancillary utilities that together form the userspace
component of the kernel's kexec feature.

%package anaconda-addon
Summary:        Kdump configuration anaconda addon
Requires:       anaconda >= 21.33
%description anaconda-addon
Kdump anaconda addon

%prep
%setup -q 

mkdir -p -m755 kcp
tar -z -x -v -f %{SOURCE9}
tar -z -x -v -f %{SOURCE19}
tar -z -x -v -f %{SOURCE23}


%patch601 -p1

%ifarch ppc
%define archdef ARCH=ppc
%endif

%build

%configure \
%ifarch ppc64
    --host=powerpc64-redhat-linux-gnu \
    --build=powerpc64-redhat-linux-gnu \
%endif
%ifarch ppc64le
    --host=powerpc64le-redhat-linux-gnu \
    --build=powerpc64le-redhat-linux-gnu \
%endif
    --sbindir=/sbin
rm -f kexec-tools.spec.in
# setup the docs
cp %{SOURCE10} .
cp %{SOURCE21} .

make
%ifarch %{ix86} x86_64 ppc64 s390x ppc64le
make -C eppic/libeppic
make -C makedumpfile-1.5.7 LINKTYPE=dynamic USELZO=on USESNAPPY=on
make -C makedumpfile-1.5.7 LDFLAGS="-I../eppic/libeppic -L../eppic/libeppic" eppic_makedumpfile.so
%endif
make -C kdump-anaconda-addon/po

%install
make install DESTDIR=$RPM_BUILD_ROOT
mkdir -p -m755 $RPM_BUILD_ROOT%{_sysconfdir}/sysconfig
mkdir -p -m755 $RPM_BUILD_ROOT%{_localstatedir}/crash
mkdir -p -m755 $RPM_BUILD_ROOT%{_mandir}/man8/
mkdir -p -m755 $RPM_BUILD_ROOT%{_mandir}/man5/
mkdir -p -m755 $RPM_BUILD_ROOT%{_docdir}
mkdir -p -m755 $RPM_BUILD_ROOT%{_datadir}/kdump
mkdir -p -m755 $RPM_BUILD_ROOT%{_udevrulesdir}
mkdir -p $RPM_BUILD_ROOT%{_unitdir}
mkdir -p -m755 $RPM_BUILD_ROOT%{_bindir}
mkdir -p -m755 $RPM_BUILD_ROOT%{_libdir}
mkdir -p -m755 $RPM_BUILD_ROOT%{_prefix}/lib/kdump
install -m 755 %{SOURCE1} $RPM_BUILD_ROOT%{_bindir}/kdumpctl

SYSCONFIG=$RPM_SOURCE_DIR/kdump.sysconfig.%{_target_cpu}
[ -f $SYSCONFIG ] || SYSCONFIG=$RPM_SOURCE_DIR/kdump.sysconfig.%{_arch}
[ -f $SYSCONFIG ] || SYSCONFIG=$RPM_SOURCE_DIR/kdump.sysconfig
install -m 644 $SYSCONFIG $RPM_BUILD_ROOT%{_sysconfdir}/sysconfig/kdump

install -m 755 %{SOURCE7} $RPM_BUILD_ROOT/sbin/mkdumprd
install -m 644 %{SOURCE8} $RPM_BUILD_ROOT%{_sysconfdir}/kdump.conf
install -m 644 kexec/kexec.8 $RPM_BUILD_ROOT%{_mandir}/man8/kexec.8
install -m 644 %{SOURCE12} $RPM_BUILD_ROOT%{_mandir}/man8/mkdumprd.8
install -m 755 %{SOURCE20} $RPM_BUILD_ROOT%{_prefix}/lib/kdump/kdump-lib.sh
install -m 755 %{SOURCE24} $RPM_BUILD_ROOT%{_prefix}/lib/kdump/kdump-lib-initramfs.sh
%ifnarch s390x
# For s390x the ELF header is created in the kdump kernel and therefore kexec
# udev rules are not required
install -m 644 %{SOURCE14} $RPM_BUILD_ROOT%{_udevrulesdir}/98-kexec.rules
%endif
install -m 644 %{SOURCE15} $RPM_BUILD_ROOT%{_mandir}/man5/kdump.conf.5
install -m 644 %{SOURCE16} $RPM_BUILD_ROOT%{_unitdir}/kdump.service
install -m 755 -D %{SOURCE22} $RPM_BUILD_ROOT%{_prefix}/lib/systemd/system-generators/kdump-dep-generator.sh
mkdir -p $RPM_BUILD_ROOT/usr/sbin
install -m 755 %{SOURCE17} $RPM_BUILD_ROOT/usr/sbin/rhcrashkernel-param

%ifarch %{ix86} x86_64 ppc64 s390x ppc64le
install -m 755 makedumpfile-1.5.7/makedumpfile $RPM_BUILD_ROOT/sbin/makedumpfile
install -m 644 makedumpfile-1.5.7/makedumpfile.8.gz $RPM_BUILD_ROOT/%{_mandir}/man8/makedumpfile.8.gz
install -m 644 makedumpfile-1.5.7/makedumpfile.conf.5.gz $RPM_BUILD_ROOT/%{_mandir}/man5/makedumpfile.conf.5.gz
install -m 644 makedumpfile-1.5.7/makedumpfile.conf $RPM_BUILD_ROOT/%{_sysconfdir}/makedumpfile.conf.sample
install -m 755 makedumpfile-1.5.7/eppic_makedumpfile.so $RPM_BUILD_ROOT/%{_libdir}/eppic_makedumpfile.so
mkdir -p $RPM_BUILD_ROOT/usr/share/makedumpfile/eppic_scripts/
install -m 644 makedumpfile-1.5.7/eppic_scripts/* $RPM_BUILD_ROOT/usr/share/makedumpfile/eppic_scripts/
%endif
make -C kdump-anaconda-addon install DESTDIR=$RPM_BUILD_ROOT
%find_lang kdump-anaconda-addon

%define remove_dracut_prefix() %(echo -n %1|sed 's/.*dracut-//g')

# deal with dracut modules
mkdir -p -m755 $RPM_BUILD_ROOT/etc/kdump-adv-conf/kdump_dracut_modules/99kdumpbase
cp %{SOURCE100} $RPM_BUILD_ROOT/etc/kdump-adv-conf/kdump_dracut_modules/99kdumpbase/%{remove_dracut_prefix %{SOURCE100}}
cp %{SOURCE101} $RPM_BUILD_ROOT/etc/kdump-adv-conf/kdump_dracut_modules/99kdumpbase/%{remove_dracut_prefix %{SOURCE101}}
cp %{SOURCE102} $RPM_BUILD_ROOT/etc/kdump-adv-conf/kdump_dracut_modules/99kdumpbase/%{remove_dracut_prefix %{SOURCE102}}
cp %{SOURCE103} $RPM_BUILD_ROOT/etc/kdump-adv-conf/kdump_dracut_modules/99kdumpbase/%{remove_dracut_prefix %{SOURCE103}}
cp %{SOURCE104} $RPM_BUILD_ROOT/etc/kdump-adv-conf/kdump_dracut_modules/99kdumpbase/%{remove_dracut_prefix %{SOURCE104}}
cp %{SOURCE105} $RPM_BUILD_ROOT/etc/kdump-adv-conf/kdump_dracut_modules/99kdumpbase/%{remove_dracut_prefix %{SOURCE105}}
cp %{SOURCE106} $RPM_BUILD_ROOT/etc/kdump-adv-conf/kdump_dracut_modules/99kdumpbase/%{remove_dracut_prefix %{SOURCE106}}
chmod 755 $RPM_BUILD_ROOT/etc/kdump-adv-conf/kdump_dracut_modules/99kdumpbase/%{remove_dracut_prefix %{SOURCE100}}
chmod 755 $RPM_BUILD_ROOT/etc/kdump-adv-conf/kdump_dracut_modules/99kdumpbase/%{remove_dracut_prefix %{SOURCE101}}


%define dracutlibdir %{_prefix}/lib/dracut
#and move the custom dracut modules to the dracut directory
mkdir -p $RPM_BUILD_ROOT/%{dracutlibdir}/modules.d/
mv $RPM_BUILD_ROOT/etc/kdump-adv-conf/kdump_dracut_modules/* $RPM_BUILD_ROOT/%{dracutlibdir}/modules.d/

%post
# Initial installation
%systemd_post kdump.service

touch /etc/kdump.conf
# This portion of the script is temporary.  Its only here
# to fix up broken boxes that require special settings 
# in /etc/sysconfig/kdump.  It will be removed when 
# These systems are fixed.

if [ -d /proc/bus/mckinley ]
then
	# This is for HP zx1 machines
	# They require machvec=dig on the kernel command line
	sed -e's/\(^KDUMP_COMMANDLINE_APPEND.*\)\("$\)/\1 machvec=dig"/' \
	/etc/sysconfig/kdump > /etc/sysconfig/kdump.new
	mv /etc/sysconfig/kdump.new /etc/sysconfig/kdump
elif [ -d /proc/sgi_sn ]
then
	# This is for SGI SN boxes
	# They require the --noio option to kexec 
	# since they don't support legacy io
	sed -e's/\(^KEXEC_ARGS.*\)\("$\)/\1 --noio"/' \
	/etc/sysconfig/kdump > /etc/sysconfig/kdump.new
	mv /etc/sysconfig/kdump.new /etc/sysconfig/kdump
fi


%postun
%systemd_postun_with_restart kdump.service

%preun
# Package removal, not upgrade
%systemd_preun kdump.service

%triggerun -- kexec-tools < 2.0.2-3
# Save the current service runlevel info
# User must manually run systemd-sysv-convert --apply kdump
# to migrate them to systemd targets
/usr/bin/systemd-sysv-convert --save kdump >/dev/null 2>&1 ||:

# Run these because the SysV package being removed won't do them
/sbin/chkconfig --del kdump >/dev/null 2>&1 || :
/bin/systemctl try-restart kdump.service >/dev/null 2>&1 || :


%triggerin -- kernel-kdump
touch %{_sysconfdir}/kdump.conf


%triggerpostun -- kernel kernel-xen kernel-debug kernel-PAE kernel-kdump
# List out the initrds here, strip out version nubmers
# and search for corresponding kernel installs, if a kernel
# is not found, remove the corresponding kdump initrd


IMGDIR=/boot
for i in `ls $IMGDIR/initramfs*kdump.img 2>/dev/null`
do
	KDVER=`echo $i | sed -e's/^.*initramfs-//' -e's/kdump.*$//'`
	if [ ! -e $IMGDIR/vmlinuz-$KDVER ]
	then
		# We have found an initrd with no corresponding kernel
		# so we should be able to remove it
		rm -f $i
	fi
done

%files
/sbin/*
/usr/sbin/*
%{_bindir}/*
%{_datadir}/kdump
%{_prefix}/lib/kdump
%ifarch %{ix86} x86_64 ppc64 s390x ppc64le
%{_sysconfdir}/makedumpfile.conf.sample
%endif
%config(noreplace,missingok) %{_sysconfdir}/sysconfig/kdump
%config(noreplace,missingok) %{_sysconfdir}/kdump.conf
%ifnarch s390x
%config %{_udevrulesdir}
%endif
%{dracutlibdir}/modules.d/*
%dir %{_localstatedir}/crash
%{_mandir}/man8/*
%{_mandir}/man5/*
%{_unitdir}/kdump.service
%{_prefix}/lib/systemd/system-generators/kdump-dep-generator.sh
%doc News
%doc COPYING
%doc TODO
%doc kexec-kdump-howto.txt
%doc kdump-in-cluster-environment.txt
%ifarch %{ix86} x86_64 ppc64 s390x ppc64le
%{_libdir}/eppic_makedumpfile.so
/usr/share/makedumpfile/eppic_scripts/
%endif

%files anaconda-addon -f kdump-anaconda-addon.lang
%{_datadir}/anaconda/addons/com_redhat_kdump
%doc

%changelog
* Tue Jan 13 2015 WANG Chao <chaowang@redhat.com> - 2.0.8-6
- mount fail if its mount point doesn't exist in /sysroot
- rebuild initrd dependency during kdump restart
- fix a dump path issue

* Tue Jan 06 2015 WANG Chao <chaowang@redhat.com> - 2.0.8-5
- remove panic_on_warn kernel param in 2nd kernel
- remove sysctl.conf to restore sysctl default values in 2nd kernel
- fix a core_collector issue in ssh and raw dump case
- update to kdump-anaconda-addon-005-2-g86366ae.tar.gz
- some cleanups

* Tue Nov 04 2014 WANG Chao <chaowang@redhat.com> - 2.0.8-4
- Fix ppc64le installation issue
- Fix get_option_value function

* Tue Oct 28 2014 WANG Chao <chaowang@redhat.com> - 2.0.8-3
- fix static route corner case
- fadump fix

* Tue Oct 21 2014 WANG Chao <chaowang@redhat.com> - 2.0.8-2
- Fix build issue on ARM

* Mon Oct 20 2014 WANG Chao <chaowang@redhat.com> - 2.0.8-1
- Rebase kexec-tools-2.0.8
- Remove subpackage kexec-tools-eppic
- Rebase kdump-anaconda-addon-005

* Fri Sep 26 2014 WANG Chao <chaowang@redhat.com> - 2.0.7-11
- Fix build failure on ppc64le
- Fix an issue on iscsi boot environment

* Tue Sep 23 2014 WANG Chao <chaowang@redhat.com> - 2.0.7-10
- Enable ppc64le arch.
- Rebase makedumpfile-1.5.7
- add sample eppic scripts to kexec-tools-eppic package
- Restart kdump service on cpu ADD/REMOVE events

* Wed Sep 10 2014 Baoquan He <bhe@redhat.com> - 2.0.7-9
- kdumpctl: Use kexec file based syscall for secureboot enabled machines
- kdumpctl: Use kexec file based mode to unload kdump kernel
- kdumpctl: Do not redirect error messages to /dev/null
- kexec: Provide an option to use new kexec system call

* Fri Aug 29 2014 WANG Chao <chaowang@redhat.com> - 2.0.7-8
- use absolute path for executable in systemd service
- update to kdump-anaconda-addon-003
- remove dead kdump firstboot module and po files

* Thu Aug 21 2014 WANG Chao <chaowang@redhat.com> - 2.0.7-7
- install 98-kexec.rules to /usr/lib/
- update kdump-anaconda-addon-0.2

* Sat Aug 16 2014 Fedora Release Engineering <rel-eng@lists.fedoraproject.org> - 2.0.7-6
- Rebuilt for https://fedoraproject.org/wiki/Fedora_21_22_Mass_Rebuild

* Wed Aug 06 2014 WANG Chao <chaowang@redhat.com> - 2.0.7-5
- rework of kdump error handling
- add fadump support
- add static route support
- systemd will take care of shutdown and umount filesystems

* Thu Jul 24 2014 WANG Chao <chaowang@redhat.com> - 2.0.7-4
- update to kdump-anaconda-addon-001-4-g03898ef.tar.gz
- prefix "kdump-" to eth name

* Mon Jul 21 2014 WANG Chao <chaowang@redhat.com> - 2.0.7-3
- update to kdump-anaconda-addon-20140721.tar.gz

* Wed Jul 16 2014 WANG Chao <chaowang@redhat.com> - 2.0.7-2
- Fix makedumpfile OOM issue

* Tue Jun 10 2014 WANG Chao <chaowang@redhat.com> - 2.0.7-1
- Rebase kexec-tools-2.0.7

* Sun Jun 08 2014 Fedora Release Engineering <rel-eng@lists.fedoraproject.org> - 2.0.6-9
- Rebuilt for https://fedoraproject.org/wiki/Fedora_21_Mass_Rebuild

* Thu May 22 2014 WANG Chao <chaowang@redhat.com> - 2.0.6-8
- re-construct anaconda-addon file hierarchy

* Wed May 21 2014 WANG Chao <chaowang@redhat.com> - 2.0.6-7
- fix a typo in kexec-tools.spec

* Tue May 20 2014 WANG Chao <chaowang@redhat.com> - 2.0.6-6
- New package kdump-anaconda-addon
- fixes for udev event based service restart

* Wed Apr 30 2014 WANG Chao <chaowang@redhat.com> - 2.0.6-5
- Remove nofail mount option
- Rebase makedumpfile-1.5.6

* Thu Apr 17 2014 WANG Chao <chaowang@redhat.com> - 2.0.6-4
- generate kdump service dependencies on the fly
- kdump.conf: a standalone path directive becomes a relative path to it's backed disk.

* Wed Apr 02 2014 WANG Chao <chaowang@redhat.com> - 2.0.6-3
- Add README to git repo
- Add fence_kdump support for generic clusters

* Thu Mar 27 2014 Peter Robinson <pbrobinson@fedoraproject.org> 2.0.6-2
- Exclude AArch64

* Wed Mar 26 2014 WANG Chao <chaowang@redhat.com> - 2.0.6-1
- Rebase kexec-tools-2.0.6
- fix an issue when dump path is mounted on nfs
- vmcore-dmesg: stack smashing fix
- get_ssh_size fix for localized df output

* Mon Mar 10 2014 WANG Chao <chaowang@redhat.com> - 2.0.5-2
- Warn about save vmcore patch mounted by another disk
- Omit dracut resume module

* Tue Mar 04 2014 WANG Chao <chaowang@redhat.com> - 2.0.5-1
- Rebase kexec-tools-2.0.5
- backport several patches from upstream for i386 build

* Mon Mar 03 2014 WANG Chao <chaowang@redhat.com> - 2.0.4-25
- Pass disable_cpu_apicid to kexec of capture kernel
- Relax restriction of dumping on encrypted target
- regression fix on wdt kernel drivers instal

* Mon Feb 17 2014 WANG Chao <chaowang@redhat.com> - 2.0.4-24
- add kdump-in-cluster-environment.txt to rpm pkg
- Secure Boot status check warning
- Some watchdog driver support

* Wed Jan 29 2014 WANG Chao <chaowang@redhat.com> - 2.0.4-23
- ssh dump: create random-seed manually
- makedumpfile: memset() in cyclic bitmap initialization introduce segment fault.
- Add acpi_no_memhotplug to kdump kernel
- Add fence kdump support

* Tue Jan 28 2014 WANG Chao <chaowang@redhat.com> - 2.0.4-22
- Rebase makedumpfile-1.5.5

* Wed Jan 22 2014 WANG Chao <chaowang@redhat.com> - 2.0.4-21
- makedumpfile: Improve progress information for huge memory system
- s390: use nr_cpus=1 instead of maxcpus=1

* Fri Jan 17 2014 WANG Chao <chaowang@redhat.com> - 2.0.4-20
- vmcore-dmesg: fix timestamp error in vmcore-dmesg.txt
- makedumpfile: re-enable mmap() and introduce --non-mmap
- kdump.conf uncomment default core_collector line
- fix an issue when 'ssh' directive appearing in kdump.conf, the rest part of
  lines in this file are ignored

* Tue Dec 24 2013 WANG Chao <chaowang@redhat.com> - 2.0.4-18
- update translation files
- makedumpfile: default to lzo compression
- makedumpfile: add makedumpfile.conf.sample and its manpage

* Sat Dec 21 2013 Ville Skyttä <ville.skytta@iki.fi> - 2.0.4-15
- Fix Tamil (India) locale subdir name.
- Fix bogus date in %%changelog.

* Tue Dec 03 2013 WANG Chao <chaowang@redhat.com> - 2.0.4-14
- Add rd.memdebug in kdump module
- kdumpctl: Avoid leaking fd to subshell
- makedumpfile: Understand >= v3.11-rc4 dmesg
- makedumpfile, ppc: Support to filter dump for kernels that use CONFIG_SPARSEMEM_VMEMMAP.

* Fri Nov 15 2013 WANG Chao <chaowang@redhat.com> - 2.0.4-13
- makedumpfile: disable mmap()

* Tue Oct 29 2013 WANG Chao <chaowang@redhat.com> - 2.0.4-12
- fix sadump format phys_base calculating error
- kdump, x86: Process multiple Crash kernel in /proc/iomem
- makedumpfile: wrong cyclic buffer size recalculation causes bitmap data corruption
- Fix max_mapnr issue on system has over 44-bit addressing.

* Sat Oct 12 2013 Baoquan He <bhe@redhat.com> -2.0.4-11
- kdump-lib.sh: strip_comments is not implemented correcty

* Fri Sep 27 2013 Baoquan He <bhe@redhat.com> - 2.0.4-10
- Back port 2 revert commits
- kdump.sysconfig: default to "nofail" mount

* Fri Sep 27 2013 Baoquan He <bhe@redhat.com> - 2.0.4-9
- Strip inline comments from the kdump config file before use
- kdump-lib.sh: add common function strip_comments
- Introduce kdump-lib.sh for kdump shared functions
- kdump.service: Start kdump after network is online and remote fs is mounted
- dracut-module-setup: _dev to be a local variable
- kdumpctl: Run multiple kdumpctl instances one by one in serial order

* Wed Aug 21 2013 Baoquan He <bhe@redhat.com> - 2.0.4-8
- remove 98selinux dependency

* Fri Aug 2  2013 Baoquan He <bhe@redhat.com> - 2.0.4-7
- dracut-kdump.sh: add do_dump() and error out if dump vmcore fails
- dracut-module-setup.sh: setup correct system time and time zone in 2nd kernel.
- kernel cmdline: Remove hugepage allocations
- Use /lib/dracut/no-emergency-shell to control action on fail
- Revert: kdump.sysconfig: Add option action_on_fail and set its default as continue
- dracut-kdump.sh: Redirect kdump script stdout/stderr to /dev/console
- makedumpfile: Add vmap_area_list definition for ppc/ppc64.

* Fri Jul 12 2013 Baoquan He <bhe@redhat.com> - 2.0.4-6
- add snappy build
- add lzo build
- pull makedumpfile-1.5.4
- mkdumprd: check return value of subshell
- mkdumprd: get_persistent_dev() return original dev if no persistent dev exists.
- dracut-kdump.sh: Merge dump_to_rootfs() to dump_fs()
- dracut-kdump.sh: explicitly sync after each dump
- Correct wrong weekday of changelog
- kexec-tools.spec: Remove incorrect description in changelog

* Tue Jun 25 2013 Baoquan He <bhe@redhat.com> - 2.0.4-5
- monitor-dd-progress fix
- rawdump: only show dd progress bar when core_collector is not makedumpfile
- kexec-tools.spec: replaces scriptlets with new systemd macros
- dracut-kdump.sh: umount fs right before kdump exit
- dracut-kdump.sh: recursively umount fs and its submounts
- dracut-kdump.sh: cleanup - using local variable names instead of $1/$2 in functions
- dracut-kdump.sh: name the invalid vmcore to vmcore-incomplete
- dracut-kdump.sh: Output top level information about the kdump progress.
- kexec-kdump-howto: Add a section for debugging tips

* Tue Jun 18 2013 Baoquan He <bhe@redhat.com> - 2.0.4-4
- dracut-module-setup.sh: improve the approach to get a bridged interface list
- dracut-module-setup.sh: cleanup - use kdump_get_mac_addr() function
- dracut-module-setup.sh: use kernel exported mac address in kdump_get_mac_addr()
- dracut-module-setup.sh: use perm addr of slaves to setup bonding network
- kdump: Do not output debug messages by default
- dracut-module-setup.sh: kdump module depends on drm module
- mkdumprd: return error if no write permission on save path of server for ssh

* Thu Jun 13 2013 Baoquan He <bhe@redhat.com> - 2.0.4-3
- mkdumprd: remove -M option for dracut
- kdumpctl: add selinux relabel when service startup
- depends on dracut selinux module
- dracut-kdump.sh: umount rootfs after dump_to_rootfs
- kdump.sysconfig: append "panic=10" to kdump cmdline
- kexec-kdump-howto: grubby is suggested modifing kernel cmdline
- kexec-tools.spec: removes kexec udev rules for s390
- kdump.sysconfig: Add option action_on_fail and set its default as continue
- Add tab key as delimiter for core_collector in kdump.conf
- redirect stdout to stderr

* Tue May 14 2013 Baoquan He <bhe@redhat.com> - 2.0.4-2
- kdump: Save vmcore-dmesg.txt before saving vmcore
- Remove "ip=" overwrite to 40ip.conf
- Add support for bridge over bond/team/vlan.
- Fix bonding options syntax and get all specified options from ifcfg file.
- add dracut_args option to kdump.conf
- kexec-tools.spec: Add ethtool to dependency.
- error out if dump target is encrypted

* Wed Apr  3 2013 Baoquan He <bhe@redhat.com> - 2.0.4-1
- Delete several patches which have been merged into kexec-tools-2.0.4
- Revert: Release 2.0.3-72
- Release 2.0.3-72
- Pull kexec-tools-2.0.4
- Check if block device as dump target is resettable
- mkdumprd: add function perror_exit
- Deprecate blacklist option

* Wed Mar 27 2013 Baoquan He <bhe@redhat.com> - 2.0.3-71
- Remove eppic support on ppc and s390 arch

* Mon Mar 18 2013 Baoquan He <bhe@redhat.com> - 2.0.3-70
- Change rules related to eppic in kexec-tools.spec

* Thu Mar 14 2013 Baoquan He <bhe@redhat.com> - 2.0.3-69
- Support for eppic language as a subpackage
 
* Thu Mar 14 2013 Baoquan He <bhe@redhat.com> - 2.0.3-68
- tune sysconfig to save memory usage
- Remove useless codes related to LOGGER in kdumpctl
- kdumpctl:print out the service status
- Return to start() function when check_ssh_target failed
- use findmnt instead of blkid in mkdumprd
- check dump target mounting earlier
- kdumpctl: rename function name check_config
- add function to check kdump config file
- dracut-module-setup.sh: remove UUID/LABEL quotes before using it
- Change dump_to_rootfs to be a default option and reboot to be default action
- Remove "-F" in CORE_COLLECTOR when dump_to_rootfs

* Tue Feb 19 2013 Baoquan He <bhe@redhat.com> - 2.0.3-67
- Remove comma which is redundant
- Modify codes related to dump dir to make it clearer
- Rectify the get_host_ip implementation
- Revert: Merge an upstream patch for fix a ppc64 makedumpfile bug with with CONFIG_SPARSEMEM_EXTREME
- pull makedumpfile 1.5.3

* Tue Feb 5 2013 Dave Young <ruyang@redhat.com> - 2.0.3-66
- Spec: remove kdump image when a corresponding kernel is removed
- Merge an upstream patch for fix a ppc64 makedumpfile bug

* Mon Jan 28 2013 Dave Young <ruyang@redhat.com> - 2.0.3-65
- Add support for team devices
- Update translation file po/it.po
- remove wait for net ok function
- add bootdev cmdline param
- kdumpnic cmdline file name cleanup

* Fri Jan 4 2013 Dave Young <ruyang@redhat.com> - 2.0.3-64
- fix issue of exec on stack for ppc32

* Fri Dec 21 2012 Dave Young <ruyang@redhat.com> - 2.0.3-63
- revert explictly handling of PIPESTATUS
- enable pipefail bash option
- wrong ssh key fix
- build fix: Update 3 po files: po/gu.po po/or.po po/zh_CN.po

* Fri Dec 21 2012 Dave Young <ruyang@redhat.com> - 2.0.3-62
- Pull translated po files from zanata
- Optimize redundent code fetching server of network dump
- change the dump dir format to be more readable

* Wed Dec 12 2012 Dave Young <ruyang@redhat.com> - 2.0.3-61
- firstboot:fix reserve mem ui spinbox step size
- handle readonly mounted filesystem

* Mon Dec 10 2012 Dave Young <ruyang@redhat.com> - 2.0.3-60
- makedumpfile 1.5.1
- Update po tar.gz
- Add a notes for zanata process
- Add two xmls file for po zanata translation
- Cleanup and recreate po files

* Fri Nov 16 2012 Dave Young <ruyang@redhat.com> - 2.0.3-59
- Enable kdump service after installation
- get MEM_RESERVED from sysfs attribute
- get_ssh_size: use -n to redirect stdin from /dev/null
- add random feeding code for ssh dump
- kdump option space checking improvement
- kdumpctl: multi dump target checking fix

* Thu Oct 25 2012 Dave Young <ruyang@redhat.com> - 2.0.3-58
- pull in two upstream patches

* Thu Oct 11 2012 Dave Young <ruyang@redhat.com> - 2.0.3-57
- improve persistent name handling

* Sat Sep 29 2012 Dave Young <ruyang@redhat.com> - 2.0.3-56
- Pull vmcore-dmesg patches from vivek
- ppc/ppc64: compile purgatory with gcc option msoft-float
- Update to support f18 grub2 efi config file
- pass persistent name to dracut --device
- pass persistent name to dracut --mount
- use persistent name in kdump.conf of initramfs
- mkdumprd: add function get_persistent_dev
- remove useless uuid and label handling

* Thu Sep 06 2012 Dave Young <ruyang@redhat.com> - 2.0.3-55
- doc fix for mount dump target before mkdumprd
- pull makedumpfile 1.5.0

* Wed Aug 29 2012 Dave Young <ruyang@redhat.com> - 2.0.3-54
- pass raw device as dracut argument
- iscsi setup fix
- firstboot: add automatic and manual memory reservation for rhel
- firstboot: remove unnecessary underline shortkey
- firstboot: fix gtk warning about non-zero page size
- firstboot: update all kernels config in grubbyCmd
- firstboot: add actual reserved memory widget
- firstboot code cleanup
- rhcrashkernel-param: echo crashkernel=auto for rhel7
- Remove the kernel-kdump handling
- s390x firstboot fix
- remove elilo support
- grub2 fix in firstboot
- Take closing the reboot dialog as no
- Handle new crashkernel= syntax in firstboot
- Fix a localized string in firstboot
- Configure kdump in firstboot
- fix firstboot to ensure kdump svc is disabled properly
- firstboot text domain fix
- Update to use systemctl instead of sysv chkconfig
- port force_rebuild kdump.conf option
- Change return value to indicate the result of dump_raw() correctly.
- call dracut function for default shell

* Mon Jul 23 2012 Dave Young <ruyang@redhat.com> - 2.0.3-53
- refactor net option
- use fstab-sys to mount nfs
- rename function dump_localfs
- dump_localfs error path fix
- update kexec-kdump-howto.txt about systemctl commands
- ssh propagate alert message fix
- remove useless dracut cmdline '-c /dev/null'
- remove useless dracut cmdline for kernel-modules and kdumpbase
- install core_collector in module-setup.sh
- install extra_bins in module-setup.sh
- remove busybox dependency
- improve warning message of space checking
- do not mount root twice
- do not add fstab-sys module in dracut cmdline
- omit dash module
- network dns config fix
- shell exit value fix 

* Thu Jul 19 2012 Fedora Release Engineering <rel-eng@lists.fedoraproject.org> - 2.0.3-52
- Rebuilt for https://fedoraproject.org/wiki/Fedora_18_Mass_Rebuild

* Thu Jul 5 2012 Dave Young <ruyang@redhat.com> - 2.0.3-51
- add s390x netdev setup
- Add s390x support
- Cleanup temp file leaved at /tmp/
- add check_size function for fs dump
- add ssh check_size
- blacklist patch apply fix
- Respect bonding mode
- Support dump over vlan tagged bonding

* Fri Jun 22 2012 Dave Young <ruyang@redhat.com> - 2.0.3-50
- add blacklist option, Resolves: bz805774
- Add kdump_post and kdump_pre support, Resolves: bz805773
- Port check_config from rhel6, Resolves: bz805778
- raw core_collector fix
- ssh core_collector fix
- drcut-kdump.sh: cleanup kdump.conf check

* Tue Jun 12 2012 Dave Young <ruyang@redhat.com> - 2.0.3-49
- cleanup DUMP_INSTRUCTION handling
- final reboot behavior fix
- dump_rootfs for default target fix
- add vlan support
- fix and refactor bond handling code
- fix and refactor bridge handling code
- core_collector doc basic fix
- omit plymouth module, Resolves: bz821997
- mkdumprd manpage cleanup manpage
- mkdumprd: remove --debug
- mkdumprd: remove noconf
- makedumprd: remove -d
- kdump.conf add sshkey
- kdump.conf remove disk_timeout
- kdump.conf make path uncommented
- kdump.conf.5 add default poweroff
- kdump.conf default shell fix
- kdump.conf default default action fix
- kdump.conf.5 remove module option
- kdump.conf remove kdump_pre/kdump_post
- kdump.conf: remove link_delay

* Mon May 28 2012 Dave Young <ruyang@redhat.com> - 2.0.3-48
- do_default_action cleanup, Resolves: bz805773
- add rhcrashkernel-param for anaconda use, Resolves: bz707441
- Basic iscsi target dump support (software initiator), Resolves bz822701
- Static ip configuratio support, Resolves: bz822739
- udev rules fix, Resolves: bz808817

* Thu May 3 2012 Dave Young <ruyang@redhat.com> - 2.0.3-47
- remove dracut-files.tgz2

* Wed May 2 2012 Dave Young <ruyang@redhat.com> - 2.0.3-46
- mkdumprd: Start using --hostonly and --add kdumpbase while calling dracut
- get_mp function cleanup
- move kdump script order to the end of pre pivot
- port raw dump from rhel6
- remove multi dump

* Mon Apr 23 2012 Dave Young <ruyang@redhat.com> - 2.0.3-45
- update dracut-files.tbz2

* Thu Apr 19 2012 Dave Young <dyoung@redhat.com> - 2.0.3-44
- update ppc64 sysconfig, resolve bug 811449
- deal with nic rename issue, resolve bug 810107
- update x86_64 sysconfig, resolve bug 813711

* Wed Apr 11 2012 Cong Wang <xiyou.wangcong@gmail.com> - 2.0.3-43
- variable name fix from Dave Young.

* Fri Mar 30 2012 Cong Wang <xiyou.wangcong@gmail.com> - 2.0.3-42
- get ip addr with getent
- spec: depends on dracut-network
- Handle net option for nfs in kdump.conf correctly

* Mon Feb 27 2012 Cong Wang <xiyou.wangcong@gmail.com> - 2.0.3-41
- Bump this version.

* Wed Feb 22 2012 Cong Wang <xiyou.wangcong@gmail.com> - 2.0.2-40
- Fixup sysytemd service file.

* Wed Feb 22 2012 Dave Young <ruyang@redhat.com> - 2.0.2-39
- Add ssh dump support, resolve bug 789253.

* Fri Jan 27 2012 Cong Wang <xiyou.wangcong@gmail.com> - 2.0.2-38
- Pull the latest makedumpfile release, 1.4.2.

* Fri Jan 27 2012 Cong Wang <xiyou.wangcong@gmail.com> - 2.0.2-37
- Add initial NFS dump support, experimental.

* Wed Jan 25 2012 Cong Wang <xiyou.wangcong@gmail.com> - 2.0.2-36
- Really upload the dracut module.

* Wed Jan 25 2012 Cong Wang <xiyou.wangcong@gmail.com> - 2.0.2-35
- Fix various bugs for nfs dump.

* Wed Jan 25 2012 Cong Wang <xiyou.wangcong@gmail.com> - 2.0.2-34
- kdump.sh cleanup for fstab handling, from Dave Young.

* Wed Jan 25 2012 Cong Wang <xiyou.wangcong@gmail.com> - 2.0.2-33
- Handle rootfs correctly.

* Tue Jan 10 2012 Cong Wang <xiyou.wangcong@gmail.com> - 2.0.2-32
- Fix add_dracut_arg in mkdumprd.

* Tue Jan 10 2012 Cong Wang <xiyou.wangcong@gmail.com> - 2.0.2-31
- Update kdump dracut module with the latest dracut kdump branch.

* Fri Dec 16 2011 Cong Wang <xiyou.wangcong@gmail.com> - 2.0.2-30
- Update kdump dracut module to use the latest dracut feature.

* Fri Sep 9 2011 Tom Callaway <spot@fedoraproject.org> - 2.0.2-29
- fix systemd scriptlets

* Wed Sep 7 2011 Cong Wang <xiyou.wangcong@gmail.com> - 2.0.2-28
- Rename mkdumprd2 to mkdumpramfs.

* Wed Aug 31 2011 Cong Wang <xiyou.wangcong@gmail.com> - 2.0.2-27
- Add debug_mem_level debugging option, from Jan Stancek.
  Resolve Bug 731395.

* Mon Aug 15 2011 Cong Wang <xiyou.wangcong@gmail.com> - 2.0.2-26
- Fix several issues caused by the previous revert.

* Mon Aug 15 2011 Cong Wang <xiyou.wangcong@gmail.com> - 2.0.2-25
- Switch back to old mkdumprd and also keep the new one.

* Tue Aug 2 2011 Cong Wang <xiyou.wangcong@gmail.com> - 2.0.2-24
- Fix default action handling.

* Tue Aug 2 2011 Cong Wang <xiyou.wangcong@gmail.com> - 2.0.2-23
- Install modified kdump.conf in initrd.

* Tue Aug 2 2011 Cong Wang <xiyou.wangcong@gmail.com> - 2.0.2-22
- Handle lvm in pre-pivot hook.

* Tue Aug 2 2011 Cong Wang <xiyou.wangcong@gmail.com> - 2.0.2-21
- Fix udev rules in module-setup.sh

* Mon Aug 1 2011 Cong Wang <xiyou.wangcong@gmail.com> - 2.0.2-20
- Generate udev rules in module-setup.sh

* Mon Aug 1 2011 Cong Wang <xiyou.wangcong@gmail.com> - 2.0.2-19
- Generate udev rules to handle device names.

* Mon Aug 1 2011 Cong Wang <xiyou.wangcong@gmail.com> - 2.0.2-18
- Fix dump to local filesystem and raw dump.

* Mon Aug 1 2011 Cong Wang <xiyou.wangcong@gmail.com> - 2.0.2-17
- Depend on dracut-network.

* Mon Aug 1 2011 Cong Wang <xiyou.wangcong@gmail.com> - 2.0.2-16
- Move dracut module detection code to module-setup.sh.

* Thu Jul 28 2011 Cong Wang <xiyou.wangcong@gmail.com> - 2.0.2-15
- Use shutdown module of dracut to handle reboot/shutdown/halt.

* Wed Jul 27 2011 Cong Wang <xiyou.wangcong@gmail.com> - 2.0.2-14
- Wait for loginit.

* Wed Jul 27 2011 Cong Wang <xiyou.wangcong@gmail.com> - 2.0.2-13
- Use absolute path of reboot/halt/poweroff.

* Wed Jul 27 2011 Cong Wang <xiyou.wangcong@gmail.com> - 2.0.2-12
- Don't use consolehelper, use real reboot/halt/poweroff.

* Wed Jul 27 2011 Cong Wang <xiyou.wangcong@gmail.com> - 2.0.2-11
- Rename initrd to initramfs.

* Wed Jul 27 2011 Cong Wang <xiyou.wangcong@gmail.com> - 2.0.2-10
- Don't depend on busybox, as it doesn't save much space.

* Tue Jul 26 2011 Cong Wang <xiyou.wangcong@gmail.com> - 2.0.2-9
- Parse default action.

* Mon Jul 25 2011 Cong Wang <xiyou.wangcong@gmail.com> - 2.0.2-8
- Move path/core_collector/default parsing code to initrd.

* Mon Jul 25 2011 Cong Wang <xiyou.wangcong@gmail.com> - 2.0.2-7
- Remove obsolete code in kdumpctl.

* Mon Jul 25 2011 Cong Wang <xiyou.wangcong@gmail.com> - 2.0.2-6
- Support core_collector and extran_bins.

* Thu Jul 21 2011 Cong Wang <xiyou.wangcong@gmail.com> - 2.0.2-5
- Bypass '-d' option.

* Thu Jul 21 2011 Cong Wang <xiyou.wangcong@gmail.com> - 2.0.2-4
- Update initramfs infrastructure to make it working
  with dracut.

* Wed Jul 06 2011 Neil Horman <nhorman@redhat.com> - 2.0.2-3
- Removed sysv init script from package

* Mon Jul 04 2011 Neil Horman <nhorman@redhat.com> - 2.0.2-2
- Added systemd unit file (bz 716994)

* Fri Jun 24 2011 Neil Horman <nhorman@redhat.com> - 2.0.2-1
- Updated to upstream version 2.0.2

* Thu Jun 02 2011 Neil Horman <nhorman@redhat.com> - 2.0.0-47
- Fixed misuse of readlink command after directory change (bz 710744)

* Tue Apr 26 2011 Neil Horman <nhorman@redhat.com> - 2.0.0-46
- Fix some grammer in man page (bz 673817)

* Mon Mar 28 2011 Neil Horman <nhorman@redhat.com> - 2.0.0-45
- Fix misuse of basename in mkdumprd (bz 683769)

* Thu Mar 10 2011 Neil Horman <nhorman@redhat.com> - 2.0.0-44
- Fix build break in purgatory makefile

* Thu Mar 10 2011 Neil Horman <nhorman@redhat.com> - 2.0.0-43
- Remove vestigual emitdms code and call from mkdumprd

* Mon Feb 07 2011 Fedora Release Engineering <rel-eng@lists.fedoraproject.org> - 2.0.0-42
- Rebuilt for https://fedoraproject.org/wiki/Fedora_15_Mass_Rebuild

* Fri Oct 22 2010 Neil Horman <nhorman@redhat.com> - 2.0.0-41
- Fixed dhcp retry mechanism (bz 645734)

* Wed Sep 29 2010 jkeating - 2.0.0-40
- Rebuilt for gcc bug 634757

* Wed Sep 22 2010 Neil Horman <nhorman@redhat.com> - 2.0.0-39
- fix finding modalias/mkdumprd hang (bz 635893)

* Wed Aug 11 2010 David Malcolm <dmalcolm@redhat.com> - 2.0.0-38
- recompiling .py files against Python 2.7 (rhbz#623327)

* Sun Jun 13 2010 Lubomir Rintel <lkundrak@v3.sk> - 2.0.0-37
- Fix a syntax error in kdump init script

* Sun Jun 13 2010 Lubomir Rintel <lkundrak@v3.sk> - 2.0.0-36
- Cosmetic mkdumprd fixes (drop an unused function, streamline another)

* Sat May 29 2010 CAI Qian <caiqian@redhat.com> - 2.0.0-35
- Forward-port from F13
- Fixed kernel text area search in kcore (bz 587750)

* Sat May 29 2010 CAI Qian <caiqian@redhat.com> - 2.0.0-34
- Massive forward-port from RHEL6
- Update kexec-kdump-howto.txt
- Update docs to reflect use of ext4
- Update mkdumprd to pull in all modules needed
- Fix mkdumprd typo
- Removed universal add of ata_piix from mkdumprd
- Fix infinite loop from modprobe changes
- Fixed kexec-kdump-howto.doc for RHEL6
- Update makedumpfile to 1.3.5
- Improved mkdumprd run time
- Cai's fix for broken regex
- Fixing crashkernel syntax parsing
- Fix initscript to return proper LSB return codes
- Fixed bad call to resolve_dm_name
- Added poweroff option to mkdumprd
- Fixed readlink issue
- Fixed x86_64 page_offset specifictaion
- Fixed lvm setup loop to not hang
- Added utsname support to makedumpfile for 2.6.32
- Fix critical_disks list to exclude cciss/md
- Add help info for -b option
- Add ability to handle firmware hotplug events
- Update mkdumprd to deal with changes in busybox fsck
- Vitaly's fix to detect need for 64 bit elf
- Fix major/minor numbers on /dev/rtc
- Fix ssh id propogation w/ selinux
- Add blacklist feature to kdump.conf
- Removed rhpl code from firstboot
- Fixed firstboot enable sense
- Remove bogus debug comment from mkdumprd.
- Handle SPARSEMEM properly
- Fix scp monitoring script
- Fix firstboot to find grub on EFI systems
- Fixed mkdumprd to remove dup insmod
- Fixed kdump fsck pause
- Fixed kdump option handling
- fixed raid5 module detection

* Thu Mar 11 2010 Neil Horman <nhorman@redhat.com> - 2.0.0-33
- Remove nash references from mkdumprd

* Wed Feb 17 2010 Neil Horman <nhorman@redhat.com> - 2.0.0-32
- Fixed spec file error

* Wed Feb 17 2010 Neil Horman <nhorman@redhat.com> - 2.0.0-31
- Adding kdump.conf man page
- Adding disk timeout parameter (bz 566135)

* Tue Dec 01 2009 Neil Horman <nhorman@redhat.com> - 2.0.0-30
- Fix raid support in mkdumprd (bz 519767)

* Mon Nov 23 2009 Neil Horman <nhorman@redhat.com> - 2.0.0-29
- Updating firstboot script to RHEL-6 version (bz 539812)

* Fri Nov 06 2009 Neil Horman <nhorman@redhat.com> - 2.0.0-28
- Added abrt infrastructure to kdump init script (bz 533370)

* Tue Sep 15 2009 Neil Horman <nhorman@redhat.com> - 2.0.0-27
- Fixing permissions on dracut module files

* Fri Sep 11 2009 Neil Horman <nhorman@redhat.com> - 2.0.0-26
- Rebuild for translation team (bz 522415)

* Thu Sep 10 2009 Neil Horman <nhorman@redhat.com> - 2.0.0-25
- Fix dracut module check file (bz 522486)

* Thu Aug 13 2009 Neil Horman <nhorman@redhat.com> - 2.0.0-24
- update kdump adv conf init script & dracut module

* Wed Jul 29 2009 Neil Horman <nhorman@redhat.com> - 2.0,0-23
- Remove mkdumprd2 and start replacement with dracut

* Fri Jul 24 2009 Fedora Release Engineering <rel-eng@lists.fedoraproject.org> - 2.0.0-22
- Rebuilt for https://fedoraproject.org/wiki/Fedora_12_Mass_Rebuild

* Mon Jul 06 2009 Neil Horman <nhorman@redhat.com> 2.0.0-21
- Fixed build break

* Mon Jul 06 2009 Neil Horman <nhorman@redhat.com> 2.0.0-20
- Make makedumpfile a dynamic binary

* Mon Jul 06 2009 Neil Horman <nhorman@redhat.com> 2.0.0-19
- Fix build issue 

* Mon Jul 06 2009 Neil Horman <nhorman@redhat.com> 2.0.0-18
- Updated initscript to use mkdumprd2 if manifest is present
- Updated spec to require dash
- Updated sample manifest to point to correct initscript
- Updated populate_std_files helper to fix sh symlink

* Mon Jul 06 2009 Neil Horman <nhorman@redhat.com> 2.0.0-17
- Fixed mkdumprd2 tarball creation

* Tue Jun 23 2009 Neil Horman <nhorman@redhat.com> 2.0.0-16
- Fix up kdump so it works with latest firstboot

* Mon Jun 15 2009 Neil Horman <nhorman@redhat.com> 2.0.0-15
- Fixed some stat drive detect bugs by E. Biederman (bz505701)

* Wed May 20 2009 Neil Horman <nhorman@redhat.com> 2.0.0-14
- Put early copy of mkdumprd2 out in the wild (bz 466392)

* Fri May 08 2009 Neil Horman <nhorman@redhat.com> - 2.0.0-13
- Update makedumpfile to v 1.3.3 (bz 499849)

* Tue Apr 07 2009 Neil Horman <nhorman@redhat.com> - 2.0.0-12
- Simplifed rootfs mounting code in mkdumprd (bz 494416)

* Sun Apr 05 2009 Lubomir Rintel <lkundrak@v3.sk> - 2.0.0-11
- Install the correct configuration for i586

* Fri Apr 03 2009 Neil Horman <nhorman@redhat.com> - 2.0.0-10
- Fix problem with quoted CORE_COLLECTOR string (bz 493707)

* Thu Apr 02 2009 Orion Poplawski <orion@cora.nwra.com> - 2.0.0-9
- Add BR glibc-static

* Wed Feb 25 2009 Fedora Release Engineering <rel-eng@lists.fedoraproject.org> - 2.0.0-8
- Rebuilt for https://fedoraproject.org/wiki/Fedora_11_Mass_Rebuild

* Thu Dec 04 2008 Ignacio Vazquez-Abrams <ivazqueznet+rpm@gmail.com> - 2.0.0-7
- Rebuild for Python 2.6

* Mon Dec 01 2008 Neil Horman <nhorman@redhat.com> - 2.0.0.6
- adding makedumpfile man page updates (bz 473212)

* Mon Dec 01 2008 Ignacio Vazquez-Abrams <ivazqueznet+rpm@gmail.com> - 2.0.0-5
- Rebuild for Python 2.6

* Wed Nov 05 2008 Neil Horman <nhorman@redhat.com> - 2.0.0-3
- Correct source file to use proper lang package (bz 335191)

* Wed Oct 29 2008 Neil Horman <nhorman@redhat.com> - 2.0.0-2
- Fix mkdumprd typo (bz 469001)

* Mon Sep 15 2008 Neil Horman <nhorman@redhat.com> - 2.0.0-2
- Fix sysconfig files to not specify --args-linux on x86 (bz 461615)

* Wed Aug 27 2008 Neil Horman <nhorman@redhat.com> - 2.0.0-1
- Update kexec-tools to latest upstream version

* Wed Aug 27 2008 Neil Horman <nhorman@redhat.com> - 1.102pre-16
- Fix mkdumprd to properly use UUID/LABEL search (bz 455998)

* Tue Aug  5 2008 Tom "spot" Callaway <tcallawa@redhat.com> - 1.102pre-15
- fix license tag

* Mon Jul 28 2008 Neil Horman <nhorman@redhat.com> - 1.102pre-14
- Add video reset section to docs (bz 456572)

* Fri Jul 11 2008 Neil Horman <nhorman@redhat.com> - 1.102pre-13
- Fix mkdumprd to support dynamic busybox (bz 443878)

* Wed Jun 11 2008 Neil Horman <nhorman@redhat.com> - 1.102pre-12
- Added lvm to bin list (bz 443878)

* Thu Jun 05 2008 Neil Horman <nhorman@redhat.com> - 1.102pre-11
- Update to latest makedumpfile from upstream
- Mass import of RHEL fixes missing in rawhide

* Thu Apr 24 2008 Neil Horman <nhorman@redhat.com> - 1.102pre-10
- Fix mkdumprd to properly pull in libs for lvm/mdadm (bz 443878)

* Wed Apr 16 2008 Neil Horman <nhorman@redhat.com> - 1.102pre-9
- Fix cmdline length issue

* Tue Mar 25 2008 Neil Horman <nhorman@redhat.com> - 1.102pre-8
- Fixing ARCH definition for bz 438661

* Mon Mar 24 2008 Neil Horman <nhorman@redhat.com> - 1.102pre-7
- Adding patches for bz 438661

* Fri Feb 22 2008 Neil Horman <nhorman@redhat.com> - 1.102pre-6
- Bringing rawhide up to date with bugfixes from RHEL5
- Adding patch to prevent kexec buffer overflow on ppc (bz 428684)

* Tue Feb 19 2008 Neil Horman <nhorman@redhat.com> - 1.102pre-5
- Modifying mkdumprd to include dynamic executibles (bz 433350)

* Tue Feb 12 2008 Neil Horman <nhorman@redhat.com> - 1.102pre-4
- bumping rev number for rebuild

* Wed Jan 02 2008 Neil Horman <nhorman@redhat.com> - 1.102pre-3
- Fix ARCH placement in kdump init script (bz 427201)
- Fix BuildRequires
- Fix Makedumpfile to build with new libelf

* Mon Oct 01 2007 Neil Horman <nhorman@redhat.com> - 1.102pre-2
- Fix triggerpostun script (bz 308151)

* Thu Aug 30 2007 Neil Horman <nhorman@redhat.com> - 1.102pre-1
- Bumping kexec version to latest horms tree (bz 257201)
- Adding trigger to remove initrds when a kernel is removed

* Wed Aug 22 2007 Neil Horman <nhorman@redhat.com> - 1.101-81
- Add xen-syms patch to makedumpfile (bz 250341)

* Wed Aug 22 2007 Neil Horman <nhorman@redhat.com> - 1.101-80
- Fix ability to determine space on nfs shares (bz 252170)

* Tue Aug 21 2007 Neil Horman <nhorman@redhat.com> - 1.101-79
- Update kdump.init to always create sparse files (bz 253714)

* Fri Aug 10 2007 Neil Horman <nhorman@redhat.com> - 1.101-78
- Update init script to handle xen kernel cmdlnes (bz 250803)

* Wed Aug 01 2007 Neil Horman <nhorman@redhat.com> - 1.101-77
- Update mkdumprd to suppres notifications /rev makedumpfile (bz 250341)

* Thu Jul 19 2007 Neil Horman <nhorman@redhat.com> - 1.101-76
- Fix mkdumprd to suppress informative messages (bz 248797)

* Wed Jul 18 2007 Neil Horman <nhorman@redhat.com> - 1.101-75
- Updated fr.po translations (bz 248287)

* Tue Jul 17 2007 Neil Horman <nhorman@redhat.com> - 1.101-74
- Fix up add_buff to retry locate_hole on segment overlap (bz 247989)

* Mon Jul 09 2007 Neil Horman <nhorman@redhat.com> - 1.101-73
- Fix up language files for kexec (bz 246508)

* Thu Jul 05 2007 Neil Horman <nhorman@redhat.com> - 1.101-72
- Fixing up initscript for LSB (bz 246967)

* Tue Jun 19 2007 Neil Horman <nhorman@redhat.com> - 1.101-71
- Fixed conflict in mkdumprd in use of /mnt (bz 222911)

* Mon Jun 18 2007 Neil Horman <nhorman@redhat.com> - 1.101-70
- Fixed kdump.init to properly read cmdline (bz 244649)

* Wed Apr 11 2007 Neil Horman <nhorman@redhat.com> - 1.101-69
- Fixed up kdump.init to enforce mode 600 on authorized_keys2 (bz 235986)

* Tue Apr 10 2007 Neil Horman <nhorman@redhat.com> - 1.101-68
- Fix alignment of bootargs and device-tree structures on ppc64

* Tue Apr 10 2007 Neil Horman <nhorman@redhat.com> - 1.101-67
- Allow ppc to boot ppc64 kernels (bz 235608)

* Tue Apr 10 2007 Neil Horman <nhorman@redhat.com> - 1.101-66
- Reduce rmo_top to 0x7c000000 for PS3 (bz 235030)

* Mon Mar 26 2007 Neil Horman <nhorman@redhat.com> - 1.101-65
- Fix spec to own kexec_tools directory (bz 219035)

* Wed Mar 21 2007 Neil Horman <nhorman@redhat.com> - 1.101-64
- Add fix for ppc memory region computation (bz 233312)

* Thu Mar 15 2007 Neil Horman <nhorman@redhat.com> - 1.101-63
- Adding extra check to avoid oom kills on nfs mount failure (bz 215056)

* Tue Mar 06 2007 Neil Horman <nhorman@redhat.com> - 1.101-62
- Updating makedumpfile to version 1.1.1 (bz 2223743)

* Thu Feb 22 2007 Neil Horman <nhorman@redhat.com> - 1.101-61
- Adding multilanguage infrastructure to firstboot_kdump (bz 223175)

* Mon Feb 12 2007 Neil Horman <nhorman@redhat.com> - 1.101-60
- Fixing up file permissions on kdump.conf (bz 228137)

* Fri Feb 09 2007 Neil Horman <nhorman@redhat.com> - 1.101-59
- Adding mkdumprd man page to build

* Thu Jan 25 2007 Neil Horman <nhorman@redhat.com> - 1.101-58
- Updating kdump.init and mkdumprd with most recent RHEL5 fixes
- Fixing BuildReq to require elfutils-devel-static

* Thu Jan 04 2007 Neil Horman <nhorman@redhat.com> - 1.101-56
- Fix option parsing problem for bzImage files (bz 221272)

* Fri Dec 15 2006 Neil Horman <nhorman@redhat.com> - 1.101-55
- Wholesale update of RHEL5 revisions 55-147

* Tue Aug 29 2006 Neil Horman <nhorman@redhat.com> - 1.101-54
- integrate default elf format patch

* Tue Aug 29 2006 Neil Horman <nhorman@redhat.com> - 1.101-53
- Taking Viveks x86_64 crashdump patch (rcv. via email)

* Tue Aug 29 2006 Neil Horman <nhorman@redhat.com> - 1.101-52
- Taking ia64 tools patch for bz 181358

* Mon Aug 28 2006 Neil Horman <nhorman@redhat.com> - 1.101-51
- more doc updates
- added patch to fix build break from kernel headers change

* Thu Aug 24 2006 Neil Horman <nhorman@redhat.com> - 1.101-50
- repo patch to enable support for relocatable kernels.

* Thu Aug 24 2006 Neil Horman <nhorman@redhat.com> - 1.101-49
- rewriting kcp to properly do ssh and scp
- updating mkdumprd to use new kcp syntax

* Wed Aug 23 2006 Neil Horman <nhorman@redhat.com> - 1.101-48
- Bumping revision number 

* Tue Aug 22 2006 Jarod Wilson <jwilson@redhat.com> - 1.101-47
- ppc64 no-more-platform fix

* Mon Aug 21 2006 Jarod Wilson <jwilson@redhat.com> - 1.101-46
- ppc64 fixups:
  - actually build ppc64 binaries (bug 203407)
  - correct usage output
  - avoid segfault in command-line parsing
- install kexec man page
- use regulation Fedora BuildRoot

* Fri Aug 18 2006 Neil Horman <nhorman@redhat.com> - 1.101-45
- fixed typo in mkdumprd for bz 202983
- fixed typo in mkdumprd for bz 203053
- clarified docs in kdump.conf with examples per bz 203015

* Tue Aug 15 2006 Neil Horman <nhorman@redhat.com> - 1.101-44
- updated init script to implement status function/scrub err messages
 
* Wed Aug 09 2006 Jarod Wilson <jwilson@redhat.com> - 1.101-43
- Misc spec cleanups and macro-ifications

* Wed Aug 09 2006 Jarod Wilson <jwilson@redhat.com> - 1.101-42
- Add %dir /var/crash, so default kdump setup works

* Thu Aug 03 2006 Neil Horman <nhorman@redhat.com> - 1.101-41
- fix another silly makefile error for makedumpfile 

* Thu Aug 03 2006 Neil Horman <nhorman@redhat.com> - 1.101-40
- exclude makedumpfile from build on non-x86[_64] arches 

* Thu Aug 03 2006 Neil Horman <nhorman@redhat.com> - 1.101-39
- exclude makedumpfile from build on non-x86[_64] arches 

* Thu Aug 03 2006 Neil Horman <nhorman@redhat.com> - 1.101-38
- updating makedumpfile makefile to use pkg-config on glib-2.0

* Thu Aug 03 2006 Neil Horman <nhorman@redhat.com> - 1.101-37
- updating makedumpfile makefile to use pkg-config

* Thu Aug 03 2006 Neil Horman <nhorman@redhat.com> - 1.101-36
- Removing unneeded deps after Makefile fixup for makedumpfile

* Thu Aug 03 2006 Neil Horman <nhorman@redhat.com> - 1.101-35
- fixing up FC6/RHEL5 BuildRequires line to build in brew

* Wed Aug 02 2006 Neil Horman <nhorman@redhat.com> - 1.101-34
- enabling makedumpfile in build

* Wed Aug 02 2006 Neil Horman <nhorman@redhat.com> - 1.101-33
- added makedumpfile source to package

* Mon Jul 31 2006 Neil Horman <nhorman@redhat.com> - 1.101-32
- added et-dyn patch to allow loading of relocatable kernels

* Thu Jul 27 2006 Neil Horman <nhorman@redhat.com> - 1.101-30
- fixing up missing patch to kdump.init

* Wed Jul 19 2006 Neil Horman <nhorman@redhat.com> - 1.101-30
- add kexec frontend (bz 197695)

* Wed Jul 12 2006 Jesse Keating <jkeating@redhat.com> - 1.101-29
- rebuild

* Fri Jul 07 2006 Neil Horman <nhorman@redhat.com> 1.101-27.fc6
- Buildrequire zlib-devel

* Thu Jun 22 2006 Neil Horman <nhorman@redhat.com> -1.101-19
- Bumping rev number

* Thu Jun 22 2006 Neil Horman <nhorman@redhat.com> -1.101-17
- Add patch to allow ppc64 to ignore args-linux option

* Wed Mar 08 2006 Bill Nottingham <notting@redhat.com> - 1.101-16
- fix scriptlet - call chkconfig --add, change the default in the
  script itself (#183633)

* Wed Mar 08 2006 Thomas Graf <tgraf@redhat.com> - 1.101-15
- Don't add kdump service by default, let the user manually add it to
  avoid everyone seeing a warning.

* Tue Mar 07 2006 Thomas Graf <tgraf@redhat.com> - 1.101-14
- Fix kdump.init to call kexec from its new location

* Mon Mar  6 2006 Jeremy Katz <katzj@redhat.com> - 1.101-13
- proper requires for scriptlets

* Mon Mar 06 2006 Thomas Graf <tgraf@redhat.com> - 1.101-12
- Move kexec and kdump binaries to /sbin

* Thu Mar 02 2006 Thomas Graf <tgraf@redhat.com> - 1.101-11
- Fix argument order when stopping kexec

* Mon Feb 27 2006 Thomas Graf <tgraf@redhat.com> - 1.101-10
- kdump7.patch
   o Remove elf32 core headers support for x86_64
   o Fix x86 prepare elf core header routine
   o Fix ppc64 kexec -p failure for gcc 4.10
   o Fix few warnings for gcc 4.10
   o Add the missing --initrd option for ppc64
   o Fix ppc64 persistent root device bug
- Remove --elf32-core-headers from default configuration, users
  may re-add it via KEXEC_ARGS.
- Remove obsolete KEXEC_HEADERS
* Wed Feb 22 2006 Thomas Graf <tgraf@redhat.com> - 1.101-9
- Remove wrong quotes around --command-line in kdump.init

* Fri Feb 17 2006 Jeff Moyer <jmoyer@redhat.com> - 1.101-8
- Fix the service stop case.  It was previously unloading the wrong kernel.
- Implement the "restart" function.
- Add the "irqpoll" option as a default kdump kernel commandline parameter.
- Create a default kernel command line in the sysconfig file upon rpm install.

* Tue Feb 07 2006 Jesse Keating <jkeating@redhat.com> - 1.101-7.1.1
- rebuilt for new gcc4.1 snapshot and glibc changes

* Thu Feb 02 2006 Thomas Graf <tgraf@redhat.com> - 1.101-7.1
- Add patch to enable the kdump binary for x86_64
* Wed Feb 01 2006 Thomas Graf <tgraf@redhat.com>
- New kdump patch to support s390 arch + various fixes
- Include kdump in x86_64 builds
* Mon Jan 30 2006 Thomas Graf <tgraf@redhat.com>
- New kdump patch to support x86_64 userspace

* Fri Dec 16 2005 Jesse Keating <jkeating@redhat.com>
- rebuilt for new gcj

* Wed Nov 16 2005 Thomas Graf <tgraf@redhat.com> - 1.101-5
- Report missing kdump kernel image as warning
 
* Thu Nov  3 2005 Jeff Moyer <jmoyer@redhat.com> - 1.101-4
- Build for x86_64 as well.  Kdump support doesn't work there, but users
  should be able to use kexec.

* Fri Sep 23 2005 Jeff Moyer <jmoyer@redhat.com> - 1.101-3
- Add a kdump sysconfig file and init script
- Spec file additions for pre/post install/uninstall

* Thu Aug 25 2005 Jeff Moyer <jmoyer@redhat.com>
- Initial prototype for RH/FC5
