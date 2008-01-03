Name: kexec-tools
Version: 1.102pre 
Release: 3%{?dist}
License: GPL
Group: Applications/System
Summary: The kexec/kdump userspace component.
Source0: %{name}-testing-20070330.tar.bz2
Source1: kdump.init
Source2: kdump.sysconfig
Source3: kdump.sysconfig.x86_64
Source4: kdump.sysconfig.i386
Source5: kdump.sysconfig.ppc64
Source6: kdump.sysconfig.ia64
Source7: mkdumprd
Source8: kdump.conf
Source9: makedumpfile-1.1.5.tar.gz
Source10: kexec-kdump-howto.txt
Source11: firstboot_kdump.py
Source12: mkdumprd.8
Source13: kexec-tools-po.tar.gz
BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
Requires(pre): coreutils chkconfig sed 
Requires: busybox >= 1.2.0
BuildRequires: zlib-devel elfutils-devel-static glib2-devel 
BuildRequires: pkgconfig intltool gettext 
%ifarch %{ix86} x86_64 ppc64 ia64 ppc
Obsoletes: diskdumputils netdump
%endif

#
# Patches 0 through 100 are meant for x86 kexec-tools enablement
#
Patch1: kexec-tools-1.102pre-elf-core-type.patch
Patch2: kexec-tools-1.102pre-bzimage-options.patch

#
# Patches 101 through 200 are meant for x86_64 kexec-tools enablement
#
Patch101: kexec-tools-1.101-disable-kdump-x8664.patch
Patch102: kexec-tools-1.101-x86_64-exactmap.patch

#
# Patches 201 through 300 are meant for ia64 kexec-tools enablement
#

#
# Patches 301 through 400 are meant for ppc64 kexec-tools enablement
#
Patch301: kexec-tools-1.102pre-ppc64_rmo_top.patch

#
# Patches 401 through 500 are meant for s390 kexec-tools enablement
#

#
# Patches 501 through 600 are meant for ppc kexec-tools enablement
#
Patch501: kexec-tools-1.102pre-ppc-fixup.patch

#
# Patches 601 onward are generic patches
#
Patch601: kexec-tools-1.102pre-elf-format.patch
Patch602: kexec-tools-1.102pre-x86-add_buffer_retry.patch
Patch603: kexec-tools-1.102pre-makedumpfile-xen-syms.patch
Patch604: kexec-tools-1.102pre-disable-kexec-test.patch
Patch605: kexec-tools-1.102pre-makedumpfile-makefile.patch

%description
kexec-tools provides /sbin/kexec binary that facilitates a new
kernel to boot using the kernel's kexec feature either on a
normal or a panic reboot. This package contains the /sbin/kexec
binary and ancillary utilities that together form the userspace
component of the kernel's kexec feature.

%prep
%setup -q -n %{name}-testing-20070330
rm -f ../kexec-tools-1.101.spec
%patch1 -p1
%patch2 -p1

%patch301 -p1

%patch501 -p1

mkdir -p -m755 kcp
tar -z -x -v -f %{SOURCE9}


%patch601 -p1
%patch602 -p1
%patch603 -p1 
%patch604 -p1
%patch605 -p1

tar -z -x -v -f %{SOURCE13}

%ifarch ppc
%define archdef ARCH=ppc
%endif

%build
%configure \
%ifarch ppc64
    --host=powerpc64-redhat-linux-gnu \
    --build=powerpc64-redhat-linux-gnu \
%endif
    --sbindir=/sbin
rm -f kexec-tools.spec.in
cp %{SOURCE10} . 
make %{?archdef}
%ifarch %{ix86} x86_64 ia64 ppc64 ppc
make -C makedumpfile
%endif
make -C kexec-tools-po

%install
rm -rf $RPM_BUILD_ROOT
make install %{?archdef} DESTDIR=$RPM_BUILD_ROOT
mkdir -p -m755 $RPM_BUILD_ROOT%{_sysconfdir}/rc.d/init.d
mkdir -p -m755 $RPM_BUILD_ROOT%{_sysconfdir}/sysconfig
mkdir -p -m755 $RPM_BUILD_ROOT%{_localstatedir}/crash
mkdir -p -m755 $RPM_BUILD_ROOT%{_mandir}/man8/
mkdir -p -m755 $RPM_BUILD_ROOT%{_docdir}
mkdir -p -m755 $RPM_BUILD_ROOT%{_datadir}/kdump
install -m 755 %{SOURCE1} $RPM_BUILD_ROOT%{_sysconfdir}/rc.d/init.d/kdump
if [ -f $RPM_SOURCE_DIR/kdump.sysconfig.%{_target_cpu} ]; then
	install -m 644 $RPM_SOURCE_DIR/kdump.sysconfig.%{_target_cpu} $RPM_BUILD_ROOT%{_sysconfdir}/sysconfig/kdump
else
	install -m 644 %{SOURCE2} $RPM_BUILD_ROOT%{_sysconfdir}/sysconfig/kdump
fi
install -m 755 %{SOURCE7} $RPM_BUILD_ROOT/sbin/mkdumprd
install -m 644 %{SOURCE8} $RPM_BUILD_ROOT%{_sysconfdir}/kdump.conf
install -m 644 kexec/kexec.8 $RPM_BUILD_ROOT%{_mandir}/man8/kexec.8
install -m 755 %{SOURCE11} $RPM_BUILD_ROOT%{_datadir}/kdump/firstboot_kdump.py
install -m 644 %{SOURCE12} $RPM_BUILD_ROOT%{_mandir}/man8/mkdumprd.8
%ifarch %{ix86} x86_64 ia64 ppc64 ppc
install -m 755 makedumpfile/makedumpfile $RPM_BUILD_ROOT/sbin/makedumpfile
install -m 755 makedumpfile/makedumpfile-R.pl $RPM_BUILD_ROOT/sbin/makedumpfile-reasm
%endif
make -C kexec-tools-po install DESTDIR=$RPM_BUILD_ROOT
%find_lang %{name}

%clean
rm -rf $RPM_BUILD_ROOT


%post
touch /etc/kdump.conf
/sbin/chkconfig --add kdump
#This portion of the script is temporary.  Its only here
#to fix up broken boxes that require special settings 
#in /etc/sysconfig/kdump.  It will be removed when 
#These systems are fixed.

#This is for HP zx1 machines
#They require machvec=dig on the kernel command line
if [ -d /proc/bus/mckinley ]
then
	sed -e's/\(^KDUMP_COMMANDLINE_APPEND.*\)\("$\)/\1 machvec=dig"/' \
	/etc/sysconfig/kdump > /etc/sysconfig/kdump.new
	mv /etc/sysconfig/kdump.new /etc/sysconfig/kdump
fi


%postun

if [ "$1" -ge 1 ]; then
	/sbin/service kdump condrestart > /dev/null 2>&1 || :
fi

%preun
if [ "$1" = 0 ]; then
	/sbin/service kdump stop > /dev/null 2>&1 || :
	/sbin/chkconfig --del kdump
fi
exit 0

%triggerin -- firstboot
if [ ! -e %{_datadir}/firstboot/modules/firstboot_kdump.py ]
then
	ln -s %{_datadir}/kdump/firstboot_kdump.py %{_datadir}/firstboot/modules/firstboot_kdump.py
fi


%triggerun -- firstboot
rm -f %{_datadir}/firstboot/modules/firstboot_kdump.py

%triggerpostun -- kernel
# List out the initrds here, strip out version nubmers
# and search for corresponding kernel installs, if a kernel
# is not found, remove the corresponding kdump initrd

#start by getting a list of all the kdump initrds
for i in /boot/initrd*kdump.img
do
	[ -e "$i" ] || continue
	KDVER="${i##*initrd-}" ; KDVER="${KDVER%%kdump*}"
	if [ ! -e /boot/vmlinuz-$KDVER ]
	then
		# We have found an initrd with no corresponding kernel
		# so we should be able to remove it
		rm -f $i
	fi
done


%files -f %{name}.lang
%defattr(-,root,root,-)
/sbin/*
%{_datadir}/kdump
%config(noreplace,missingok) %{_sysconfdir}/sysconfig/kdump
%config(noreplace,missingok) %{_sysconfdir}/kdump.conf
%config %{_sysconfdir}/rc.d/init.d/kdump
%dir %{_localstatedir}/crash
%{_mandir}/man8/*
%doc News
%doc COPYING
%doc TODO
%doc kexec-kdump-howto.txt

%changelog
* Wed Jan 02 2008 Neil Horman <nhorman@redhat.com> - 1.102pre-3
- Fix ARCH placement in kdump init script (bz 427201)
- Fix BuildRequires
- Fix Makedumpfile to build with new libelf

* Mon Oct 01 2007 Neil Horman <nhorman@redhat.com> - 1.102pre-2
- Fix triggerpostun script (bz 308151)

* Mon Aug 30 2007 Neil Horman <nhorman@redhat.com> - 1.102pre-1
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

* Wed Aug 01 2007 Neil Horman <nhorman@redhat.com> - 1.101-77%{dist}
- Update mkdumprd to suppres notifications /rev makedumpfile (bz 250341)

* Thu Jul 19 2007 Neil Horman <nhorman@redhat.com> - 1.101-76%{dist}
- Fix mkdumprd to suppress informative messages (bz 248797)

* Wed Jul 18 2007 Neil Horman <nhorman@redhat.com> - 1.101-75%{dist}
- Updated fr.po translations (bz 248287)

* Mon Jul 17 2007 Neil Horman <nhorman@redhat.com> - 1.101-74%{dist}
- Fix up add_buff to retry locate_hole on segment overlap (bz 247989)

* Mon Jul 09 2007 Neil Horman <nhorman@redhat.com> - 1.101-73%{dist}
- Fix up language files for kexec (bz 246508)

* Thu Jul 05 2007 Neil Horman <nhorman@redhat.com> - 1.101-72%{dist}
- Fixing up initscript for LSB (bz 246967)

* Tue Jun 19 2007 Neil Horman <nhorman@redhat.com> - 1.101-71%{dist}
- Fixed conflict in mkdumprd in use of /mnt (bz 222911)

* Mon Jun 18 2007 Neil Horman <nhorman@redhat.com> - 1.101-70%{dist}
- Fixed kdump.init to properly read cmdline (bz 244649)

* Wed Apr 11 2007 Neil Horman <nhorman@redhat.com> - 1.101-69%{dist}
- Fixed up kdump.init to enforce mode 600 on authorized_keys2 (bz 235986)

* Tue Apr 10 2007 Neil Horman <nhorman@redhat.com> - 1.101-68%{dist}
- Fix alignment of bootargs and device-tree structures on ppc64

* Tue Apr 10 2007 Neil Horman <nhorman@redhat.com> - 1.101-67%{dist}
- Allow ppc to boot ppc64 kernels (bz 235608)

* Tue Apr 10 2007 Neil Horman <nhorman@redhat.com> - 1.101-66%{dist}
- Reduce rmo_top to 0x7c000000 for PS3 (bz 235030)

* Mon Mar 26 2007 Neil Horman <nhorman@redhat.com> - 1.101-65%{dist}
- Fix spec to own kexec_tools directory (bz 219035)

* Wed Mar 21 2007 Neil Horman <nhorman@redhat.com> - 1.101-64%{dist}
- Add fix for ppc memory region computation (bz 233312)

* Thu Mar 15 2007 Neil Horman <nhorman@redhat.com> - 1.101-63%{dist}
- Adding extra check to avoid oom kills on nfs mount failure (bz 215056)

* Tue Mar 06 2007 Neil Horman <nhorman@redhat.com> - 1.101-62%{dist}
- Updating makedumpfile to version 1.1.1 (bz 2223743)

* Mon Feb 22 2007 Neil Horman <nhorman@redhat.com> - 1.101-61%{dist}
- Adding multilanguage infrastructure to firstboot_kdump (bz 223175)

* Mon Feb 12 2007 Neil Horman <nhorman@redhat.com> - 1.101-60%{dist}
- Fixing up file permissions on kdump.conf (bz 228137)

* Fri Feb 09 2007 Neil Horman <nhorman@redhat.com> - 1.101-59%{dist}
- Adding mkdumprd man page to build

* Wed Jan 25 2007 Neil Horman <nhorman@redhat.com> - 1.101-58%{dist}
- Updating kdump.init and mkdumprd with most recent RHEL5 fixes
- Fixing BuildReq to require elfutils-devel-static

* Thu Jan 04 2007 Neil Horman <nhorman@redhat.com> - 1.101-56%{dist}
- Fix option parsing problem for bzImage files (bz 221272)

* Fri Dec 15 2006 Neil Horman <nhorman@redhat.com> - 1.101-55%{dist}
- Wholesale update of RHEL5 revisions 55-147

* Tue Aug 29 2006 Neil Horman <nhorman@redhat.com> - 1.101-54%{dist}
- integrate default elf format patch

* Tue Aug 29 2006 Neil Horman <nhorman@redhat.com> - 1.101-53%{dist}
- Taking Viveks x86_64 crashdump patch (rcv. via email)

* Tue Aug 29 2006 Neil Horman <nhorman@redhat.com> - 1.101-52%{dist}
- Taking ia64 tools patch for bz 181358

* Mon Aug 28 2006 Neil Horman <nhorman@redhat.com> - 1.101-51%{dist}
- more doc updates
- added patch to fix build break from kernel headers change

* Thu Aug 24 2006 Neil Horman <nhorman@redhat.com> - 1.101-50%{dist}
- repo patch to enable support for relocatable kernels.

* Thu Aug 24 2006 Neil Horman <nhorman@redhat.com> - 1.101-49%{dist}
- rewriting kcp to properly do ssh and scp
- updating mkdumprd to use new kcp syntax

* Wed Aug 23 2006 Neil Horman <nhorman@redhat.com> - 1.101-48%{dist}
- Bumping revision number 

* Tue Aug 22 2006 Jarod Wilson <jwilson@redhat.com> - 1.101-47%{dist}
- ppc64 no-more-platform fix

* Mon Aug 21 2006 Jarod Wilson <jwilson@redhat.com> - 1.101-46%{dist}
- ppc64 fixups:
  - actually build ppc64 binaries (bug 203407)
  - correct usage output
  - avoid segfault in command-line parsing
- install kexec man page
- use regulation Fedora BuildRoot

* Fri Aug 18 2006 Neil Horman <nhorman@redhat.com> - 1.101-45%{dist}
- fixed typo in mkdumprd for bz 202983
- fixed typo in mkdumprd for bz 203053
- clarified docs in kdump.conf with examples per bz 203015

* Tue Aug 15 2006 Neil Horman <nhorman@redhat.com> - 1.101-44%{dist}
- updated init script to implement status function/scrub err messages
 
* Wed Aug 09 2006 Jarod Wilson <jwilson@redhat.com> - 1.101-43%{dist}
- Misc spec cleanups and macro-ifications

* Wed Aug 09 2006 Jarod Wilson <jwilson@redhat.com> - 1.101-42%{dist}
- Add %dir /var/crash, so default kdump setup works

* Thu Aug 03 2006 Neil Horman <nhorman@redhat.com> - 1.101-41%{dist}.1
- fix another silly makefile error for makedumpfile 

* Thu Aug 03 2006 Neil Horman <nhorman@redhat.com> - 1.101-40%{dist}.1
- exclude makedumpfile from build on non-x86[_64] arches 

* Thu Aug 03 2006 Neil Horman <nhorman@redhat.com> - 1.101-39%{dist}.1
- exclude makedumpfile from build on non-x86[_64] arches 

* Thu Aug 03 2006 Neil Horman <nhorman@redhat.com> - 1.101-38%{dist}.1
- updating makedumpfile makefile to use pkg-config on glib-2.0

* Thu Aug 03 2006 Neil Horman <nhorman@redhat.com> - 1.101-37%{dist}.1
- updating makedumpfile makefile to use pkg-config

* Thu Aug 03 2006 Neil Horman <nhorman@redhat.com> - 1.101-36%{dist}.1
- Removing unneeded deps after Makefile fixup for makedumpfile

* Thu Aug 03 2006 Neil Horman <nhorman@redhat.com> - 1.101-35%{dist}.1
- fixing up FC6/RHEL5 BuildRequires line to build in brew

* Wed Aug 02 2006 Neil Horman <nhorman@redhat.com> - 1.101-34%{dist}.1
- enabling makedumpfile in build

* Wed Aug 02 2006 Neil Horman <nhorman@redhat.com> - 1.101-33%{dist}.1
- added makedumpfile source to package

* Mon Jul 31 2006 Neil Horman <nhorman@redhat.com> - 1.101-32%{dist}.1
- added et-dyn patch to allow loading of relocatable kernels

* Thu Jul 27 2006 Neil Horman <nhorman@redhat.com> - 1.101-30%{dist}.1
- fixing up missing patch to kdump.init

* Wed Jul 19 2006 Neil Horman <nhorman@redhat.com> - 1.101-30%{dist}.1
- add kexec frontend (bz 197695)

* Wed Jul 12 2006 Jesse Keating <jkeating@redhat.com> - 1.101-29%{dist}.1
- rebuild

* Wed Jul 07 2006 Neil Horman <nhorman@redhat.com> 1.101-27.fc6
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
