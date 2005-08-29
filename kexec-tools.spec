Name: kexec-tools
Version: 1.101
Release: 2
License: GPL
Group: Applications/System
Summary: The kexec/kdump userspace component.
ExclusiveArch: %{ix86}
Source0: %{name}-%{version}.tar.gz
BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-buildroot

#
# Patches 0 through 100 are meant for x86 kexec-tools enablement
#
Patch1: kexec-tools-1.101-kdump.patch

#
# Patches 101 through 200 are meant for x86_64 kexec-tools enablement
#

#
# Patches 201 through 300 are meant for ia64 kexec-tools enablement
#

#
# Patches 301 through 400 are meant for ppc64 kexec-tools enablement
#

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

%build
%configure
rm -f kexec-tools.spec.in
make

%install
rm -rf $RPM_BUILD_ROOT
make install DESTDIR=$RPM_BUILD_ROOT

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(-,root,root,-)
%{_sbindir}/kexec
%{_sbindir}/kdump
%{_libdir}/kexec-tools/kexec_test
%doc News
%doc COPYING
%doc TODO

%changelog
* Thu Aug 25 2005 Ananth Mavinakayanahalli <amavin@redhat.com>
- Initial prototype for RH/FC5
