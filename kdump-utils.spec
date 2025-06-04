# kdump-utils has no debug source
%global debug_package %{nil}
Name: kdump-utils
Version: 1.0.44
Release: %autorelease
Summary: Kernel crash dump collection utilities

License: GPL-2.0-only
URL: https://github.com/rhkdump/kdump-utils
Source0: https://github.com/rhkdump/kdump-utils/archive/v%{version}/%{name}-%{version}.tar.gz

%ifarch ppc64 ppc64le
Requires(post): servicelog
Recommends: keyutils
%endif
Requires(pre): coreutils
Requires(pre): sed
Requires: kexec-tools >= 2.0.28-8
Requires: makedumpfile
Requires: dracut >= 058
Requires: dracut-network >= 058
Requires: dracut-squash >= 058
Requires: ethtool
Requires: gawk
Requires: util-linux
# Needed for UKI support
Recommends: binutils
Recommends: grubby
Recommends: hostname
BuildRequires: make
BuildRequires: systemd-rpm-macros

%ifnarch s390x
Requires: systemd-udev%{?_isa}
%endif
%description
kdump-utils is responsible for collecting the crash kernel dump. It builds and
loads the kdump initramfs so when a kernel crashes, the system will boot the
kdump kernel and initramfs to save the collected crash kernel dump to specified
target.

%prep
%autosetup -p1

%install
%make_install sbindir=%_sbindir


%post
# kdumpctl will only set up default crashkernel when kdump.service is enabled
%systemd_post kdump.service

touch /etc/kdump.conf

%ifarch ppc64 ppc64le
servicelog_notify --remove --command=/usr/lib/kdump/kdump-migrate-action.sh 2>/dev/null
servicelog_notify --add --command=/usr/lib/kdump/kdump-migrate-action.sh --match='refcode="#MIGRATE" and serviceable=0' --type=EVENT --method=pairs_stdin >/dev/null
%endif

# RPM scriptlet should always return 0. Otherwise it can break
# installs/upgrades/erases.
:


%postun
%systemd_postun_with_restart kdump.service

%preun
%ifarch ppc64 ppc64le
servicelog_notify --remove --command=/usr/lib/kdump/kdump-migrate-action.sh >/dev/null
%endif
%systemd_preun kdump.service

%posttrans
# Try to reset kernel crashkernel value to new default value or set up
# crasherkernel value for new install
#
# Note
#  1. Skip ostree systems as they are not supported.
#  2. For Fedora 36 and RHEL9, "[ $1 == 1 ]" in posttrans scriptlet means both install and upgrade;
#     For Fedora > 36, "[ $1 == 1 ]" only means install and "[ $1 == 2 ]" means upgrade
#  3. osbuild depends on "kdumpctl _reset-crashkernel-for-installed_kernel" to set up crashkernel
if [ ! -f /run/ostree-booted ] && [ $1 == 1 -o $1 == 2 ]; then
  kdumpctl _reset-crashkernel-after-update
  :
fi

%files
%ifarch ppc64 ppc64le
%{_sbindir}/mkfadumprd
%{_prefix}/lib/kernel/install.d/60-fadump.install
%endif
%{_bindir}/kdumpctl
%{_sbindir}/mkdumprd
%{_prefix}/lib/kdump
%config(noreplace,missingok) %{_sysconfdir}/sysconfig/kdump
%config(noreplace,missingok) %verify(not mtime) %{_sysconfdir}/kdump.conf
%ifnarch s390x
%{_udevrulesdir}
%{_udevrulesdir}/../kdump-udev-throttler
%endif
%{_prefix}/lib/dracut/modules.d/*
%dir %{_localstatedir}/crash
%dir %{_sysconfdir}/kdump
%dir %{_sysconfdir}/kdump/pre.d
%dir %{_sysconfdir}/kdump/post.d
%dir %{_sharedstatedir}/kdump
%{_mandir}/man8/kdumpctl.8*
%{_mandir}/man8/mkdumprd.8*
%{_mandir}/man5/kdump.conf.5*
%{_unitdir}/kdump.service
%{_prefix}/lib/systemd/system-generators/kdump-dep-generator.sh
%{_prefix}/lib/kernel/install.d/60-kdump.install
%{_prefix}/lib/kernel/install.d/92-crashkernel.install
%license COPYING
%doc kexec-kdump-howto.txt
%doc early-kdump-howto.txt
%doc fadump-howto.txt
%doc kdump-in-cluster-environment.txt
%doc live-image-kdump-howto.txt
%doc crashkernel-howto.txt
%doc supported-kdump-targets.txt

%changelog
%autochangelog
