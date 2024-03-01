prefix ?= /usr
libdir ?= ${prefix}/lib
datadir ?= ${prefix}/share
pkglibdir ?= ${libdir}/kdump
sysconfdir ?= /etc
bindir ?= ${prefix}/bin
sbindir ?= ${prefix}/sbin
mandir ?= ${prefix}/share/man
localstatedir ?= /var
sharedstatedir ?= /var/lib
udevrulesdir ?=  ${libdir}/udev/rules.d
systemdsystemunitdir ?= ${libdir}/systemd/system/
ARCH ?= $(shell uname -m)
dracutmoddir = $(DESTDIR)${libdir}/dracut/modules.d
kdumpbasemoddir = $(dracutmoddir)/99kdumpbase

dracut-modules:
	mkdir -p $(dracutmoddir)
	mkdir -p -m755 $(kdumpbasemoddir)

	install -m 755 dracut-kdump.sh $(kdumpbasemoddir)/kdump.sh
	install -m 755 dracut-module-setup.sh $(kdumpbasemoddir)/module-setup.sh
	install -m 755 dracut-monitor_dd_progress.sh $(kdumpbasemoddir)/monitor_dd_progress.sh
	install -m 644 dracut-kdump-emergency.service $(kdumpbasemoddir)/kdump-emergency.service
	install -m 644 dracut-kdump-capture.service $(kdumpbasemoddir)/kdump-capture.service
	install -m 644 dracut-kdump-emergency.target $(kdumpbasemoddir)/kdump-emergency.target

	mkdir -p -m755 $(dracutmoddir)/99earlykdump
	install -m 755 dracut-early-kdump.sh $(dracutmoddir)/99earlykdump/kdump.sh
	install -m 755 dracut-early-kdump-module-setup.sh $(dracutmoddir)/99earlykdump/kdump-module-setup.sh

ifeq ($(ARCH), $(filter ppc64le ppc64,$(ARCH)))
	mkdir -p -m755 $(dracutmoddir)/99zz-fadumpinit
	install -m 755 dracut-fadump-init-fadump.sh $(dracutmoddir)/99zz-fadumpinit/init-fadump.sh
	install -m 755 dracut-fadump-module-setup.sh $(dracutmoddir)/99zz-fadumpinit/module-setup.sh
endif

kdump-conf: gen-kdump-conf.sh
	./gen-kdump-conf.sh $(ARCH) > kdump.conf

kdump-sysconfig: gen-kdump-sysconfig.sh
	./gen-kdump-sysconfig.sh $(ARCH) > kdump.sysconfig

manpages:
	install -D -m 644 mkdumprd.8 kdumpctl.8 -t $(DESTDIR)$(mandir)/man8
	install -D -m 644 kdump.conf.5 $(DESTDIR)$(mandir)/man5/kdump.conf.5

install: dracut-modules kdump-conf kdump-sysconfig manpages
	mkdir -p $(DESTDIR)$(pkglibdir)
	mkdir -p -m755 $(DESTDIR)$(sysconfdir)/kdump/pre.d
	mkdir -p -m755 $(DESTDIR)$(sysconfdir)/kdump/post.d
	mkdir -p -m755 $(DESTDIR)$(localstatedir)/crash
	mkdir -p -m755 $(DESTDIR)$(udevrulesdir)
	mkdir -p -m755 $(DESTDIR)$(sharedstatedir)/kdump
	mkdir -p -m755 $(DESTDIR)$(libdir)/kernel/install.d/

	install -D -m 755 kdumpctl $(DESTDIR)$(bindir)/kdumpctl
	install -D -m 755 mkdumprd $(DESTDIR)$(sbindir)/mkdumprd
	install -D -m 644 kdump.conf $(DESTDIR)$(sysconfdir)
	install -D -m 644 kdump.sysconfig $(DESTDIR)$(sysconfdir)/sysconfig/kdump
	install -D -m 755 kdump-lib.sh kdump-lib-initramfs.sh kdump-logger.sh -t $(DESTDIR)$(pkglibdir)

ifeq ($(ARCH), $(filter ppc64le ppc64,$(ARCH)))
	install -m 755 mkfadumprd $(DESTDIR)$(sbindir)
	install -m 755 kdump-migrate-action.sh  kdump-restart.sh -t $(DESTDIR)$(pkglibdir)
	install -m 755 60-fadump.install $(DESTDIR)$(libdir)/kernel/install.d/
endif

ifneq ($(ARCH),s390x)
	install -m 755 kdump-udev-throttler $(DESTDIR)$(udevrulesdir)/../kdump-udev-throttler
	# For s390x the ELF header is created in the kdump kernel and therefore kexec
	# udev rules are not required
ifeq ($(ARCH), $(filter ppc64le ppc64,$(ARCH)))
	install -m 644 98-kexec.rules.ppc64 $(DESTDIR)$(udevrulesdir)/98-kexec.rules
else
	install -m 644 98-kexec.rules $(DESTDIR)$(udevrulesdir)/98-kexec.rules
endif
endif

	install -D -m 644 kdump.service $(DESTDIR)$(systemdsystemunitdir)/kdump.service
	install -m 755 -D kdump-dep-generator.sh $(DESTDIR)$(libdir)/systemd/system-generators/kdump-dep-generator.sh
	install -m 755 60-kdump.install $(DESTDIR)$(libdir)/kernel/install.d/
	install -m 755 92-crashkernel.install $(DESTDIR)$(libdir)/kernel/install.d/
