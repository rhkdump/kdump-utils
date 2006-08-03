Name: kexec-tools
Version: 1.101
Release: 37%{dist}.1
License: GPL
Group: Applications/System
Summary: The kexec/kdump userspace component.
Source0: %{name}-%{version}.tar.gz
Source1: kdump.init
Source2: kdump.sysconfig
Source3: mkdumprd
Source4: kdump.conf
Source5: kcp.c
Source6: Makefile.kcp
Source7: makedumpfile.tar.gz
BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-buildroot
Requires(pre): coreutils chkconfig sed
BuildRequires: zlib-devel elfutils-libelf-devel glib2-devel pkgconfig

#
# Patches 0 through 100 are meant for x86 kexec-tools enablement
#
Patch1: kexec-tools-1.101-kdump.patch

#
# Patches 101 through 200 are meant for x86_64 kexec-tools enablement
#
Patch101: kexec-tools-1.101-disable-kdump-x8664.patch

#
# Patches 201 through 300 are meant for ia64 kexec-tools enablement
#
Patch201: kexec-tools-1.101-ia64-fixup.patch

#
# Patches 301 through 400 are meant for ppc64 kexec-tools enablement
#
Patch301: kexec-ppc64-ingnore-args-linux.patch

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
Patch602: kexec-tools-1.101-Makefile-kcp.patch
Patch603: kexec-tools-1.101-et-dyn.patch
Patch604: kexec-tools-1.101-add-makedumpfile1.patch
Patch605: kexec-tools-1.101-add-makedumpfile2.patch

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
%patch101 -p1
%patch201 -p1
%patch301 -p1
%patch401 -p1
%patch501 -p1
%patch601 -p1
%patch602 -p1
%patch603 -p1

cp $RPM_SOURCE_DIR/kdump.init .
cp $RPM_SOURCE_DIR/kdump.sysconfig .
cp $RPM_SOURCE_DIR/kdump.conf .
cp $RPM_SOURCE_DIR/mkdumprd .
mkdir -p -m755 kcp
cp $RPM_SOURCE_DIR/kcp.c kcp/kcp.c
cp $RPM_SOURCE_DIR/Makefile.kcp kcp/Makefile
mkdir makedumpfile 
tar -C makedumpfile -z -x -v -f $RPM_SOURCE_DIR/makedumpfile.tar.gz

%patch604 -p1
%patch605 -p1

%build
%configure --sbindir=/sbin
rm -f kexec-tools.spec.in
make
make -C makedumpfile

%install
rm -rf $RPM_BUILD_ROOT
make install DESTDIR=$RPM_BUILD_ROOT
mkdir -p -m755 $RPM_BUILD_ROOT/etc/rc.d/init.d
mkdir -p -m755 $RPM_BUILD_ROOT/etc/sysconfig
install -m 644 kdump.sysconfig $RPM_BUILD_ROOT/etc/sysconfig/kdump
install -m 755 kdump.init $RPM_BUILD_ROOT/etc/rc.d/init.d/kdump
install -m 755 mkdumprd $RPM_BUILD_ROOT/sbin/mkdumprd
install -m 755 kdump.conf $RPM_BUILD_ROOT/etc/kdump.conf
install -m 755 makedumpfile/makedumpfile $RPM_BUILD_ROOT/sbin/makedumpfile

%clean
rm -rf $RPM_BUILD_ROOT

%post
touch /etc/kdump.conf
/sbin/chkconfig --add kdump

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

%files
%defattr(-,root,root,-)
/sbin/*
%config(noreplace,missingok) /etc/sysconfig/kdump
%config(noreplace,missingok) /etc/kdump.conf
%config /etc/rc.d/init.d/kdump
%ifarch %{ix86} x86_64
%{_libdir}/kexec-tools/kexec_test
%endif
%doc News
%doc COPYING
%doc TODO

%changelog
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
- Modify spec/sysconfig to not autobuild kdump kernel command line
- Add dist to revision tag
- Build for all arches

* Wed Jun 28 2006 Karsten Hopp <karsten@redhat.de> 1.101-20
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
