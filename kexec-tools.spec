Name: kexec-tools
Version: 1.101
Release: 65%{?dist}
License: GPL
Group: Applications/System
Summary: The kexec/kdump userspace component.
Source0: %{name}-%{version}.tar.gz
Source1: kdump.init
Source2: kdump.sysconfig
Source3: kdump.sysconfig.x86_64
Source4: kdump.sysconfig.i386
Source5: kdump.sysconfig.ppc64
Source6: kdump.sysconfig.ia64
Source7: mkdumprd
Source8: kdump.conf
Source9: makedumpfile-1.1.1.tar.gz
Source10: kexec-kdump-howto.txt
Source11: firstboot_kdump.py
Source12: mkdumprd.8
Source13: pofiles.tar.gz
BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
Requires(pre): coreutils chkconfig sed 
Requires: busybox >= 1.2.0
BuildRequires: zlib-devel elfutils-libelf-devel glib2-devel pkgconfig
BuildRequires: elfutils-libelf-devel elfutils-devel-static gettext
ExcludeArch: ppc
%ifarch %{ix86} x86_64 ppc64 ia64
Obsoletes: diskdumputils netdump
%endif

#
# Patches 0 through 100 are meant for x86 kexec-tools enablement
#
Patch1: kexec-tools-1.101-kdump.patch
Patch2: kexec-tools-1.101-elf-core-type.patch
Patch3: kexec-tools-1.101-bzimage-options.patch
Patch4: kexec-tools-1.101-relocatable-bzimage.patch

#
# Patches 101 through 200 are meant for x86_64 kexec-tools enablement
#
Patch101: kexec-tools-1.101-disable-kdump-x8664.patch
Patch102: kexec-tools-1.101-x86_64-exactmap.patch

#
# Patches 201 through 300 are meant for ia64 kexec-tools enablement
#
Patch201: kexec-tools-1.101-ia64-fixup.patch
Patch202: kexec-tools-1.101-ia64-tools.patch
Patch203: kexec-tools-1.101-ia64-kdump.patch
Patch204: kexec-tools-1.101-ia64-EFI.patch
Patch205: kexec-tools-1.101-ia64-icache-align.patch
Patch206: kexec-tools-1.101-ia64-noio.patch
Patch207: kexec-tools-1.101-ia64-phdr-malloc.patch
Patch208: kexec-tools-1.101-ia64-load-offset.patch
Patch209: kexec-tools-1.101-ia64-noio-eat.patch
Patch210: kexec-tools-1.101-ia64-dash-l-fix.patch

#
# Patches 301 through 400 are meant for ppc64 kexec-tools enablement
#
Patch301: kexec-tools-1.101-ppc64-ignore-args.patch
Patch302: kexec-tools-1.101-ppc64-usage.patch
Patch303: kexec-tools-1.101-ppc64-cliargs.patch
Patch304: kexec-tools-1.101-ppc64-platform-fix.patch
Patch305: kexec-tools-1.101-ppc64-64k-pages.patch
Patch306: kexec-tools-1.101-ppc64-memory_regions.patch

#
# Patches 401 through 500 are meant for s390 kexec-tools enablement
#
Patch401: kexec-tools-1.101-s390-fixup.patch

#
# Patches 501 through 600 are meant for ppc kexec-tools enablement
#
Patch501: kexec-tools-1.101-ppc-fixup.patch

#
# Patches 601 onward are generic patches
#
Patch601: kexec-tools-1.101-Makefile.patch
Patch602: kexec-tools-1.101-et-dyn.patch
Patch603: kexec-tools-1.101-page_h.patch
Patch604: kexec-tools-1.101-elf-format.patch
Patch605: kexec-tools-1.101-ifdown.patch
Patch606: kexec-tools-1.101-reloc-update.patch

%description
kexec-tools provides /sbin/kexec binary that facilitates a new
kernel to boot using the kernel's kexec feature either on a
normal or a panic reboot. This package contains the /sbin/kexec
binary and ancillary utilities that together form the userspace
component of the kernel's kexec feature.

%prep
%setup -q -n %{name}-%{version}
rm -f ../kexec-tools-1.101.spec
%patch1 -p1
%patch2 -p1
%patch3 -p1
%patch4 -p1
%patch101 -p1
%patch102 -p1
%patch201 -p1
%patch202 -p1
%patch203 -p1
%patch204 -p1
%patch205 -p1
%patch206 -p1
%patch207 -p1
%patch208 -p1
%patch209 -p1
%patch210 -p1
%patch301 -p1
%patch302 -p1
%patch303 -p1
%patch304 -p1
%patch305 -p1
%patch306 -p1
%patch401 -p1
%patch501 -p1
%patch601 -p1
%patch602 -p1

mkdir -p -m755 kcp
tar -z -x -v -f %{SOURCE9}

%patch603 -p1
%patch604 -p1
%patch605 -p1
%patch606 -p1

tar -z -x -v -f %{SOURCE13}

%build
%configure \
%ifarch ppc64
    --host=powerpc64-redhat-linux-gnu \
    --build=powerpc64-redhat-linux-gnu \
%endif
    --sbindir=/sbin
rm -f kexec-tools.spec.in
cp %{SOURCE10} . 
make
%ifarch %{ix86} x86_64 ia64 ppc64
make -C makedumpfile
%endif
make -C po

%install
rm -rf $RPM_BUILD_ROOT
make install DESTDIR=$RPM_BUILD_ROOT
make -C po install DESTDIR=$RPM_BUILD_ROOT
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
%ifarch %{ix86} x86_64 ia64 ppc64
install -m 755 makedumpfile/makedumpfile $RPM_BUILD_ROOT/sbin/makedumpfile
install -m 755 makedumpfile/makedumpfile-R.pl $RPM_BUILD_ROOT/sbin/makedumpfile-reasm
%endif
CHOMP_SIZE=`echo $RPM_BUILD_ROOT | wc -c`
find $RPM_BUILD_ROOT -name '*.mo' | cut -b $CHOMP_SIZE- >> %{name}.lang

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

%files -f %{name}.lang
%defattr(-,root,root,-)
/sbin/*
%{_datadir}/kdump
%config(noreplace,missingok) %{_sysconfdir}/sysconfig/kdump
%config(noreplace,missingok) %{_sysconfdir}/kdump.conf
%config %{_sysconfdir}/rc.d/init.d/kdump
%dir %{_localstatedir}/crash
%ifarch %{ix86} x86_64
%{_libdir}/kexec-tools
%endif
%{_mandir}/man8/*
%doc News
%doc COPYING
%doc TODO
%doc kexec-kdump-howto.txt

%changelog
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
