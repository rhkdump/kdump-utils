# Makefile for source rpm: kexec-tools
# $Id$
NAME := kexec-tools
SPECFILE = $(firstword $(wildcard *.spec))

SUBDIRS = kcp

define find-makefile-common
for d in common ../common ../../common ; do if [ -f $$d/Makefile.common ] ; then if [ -f $$d/CVS/Root -a -w $$d/Makefile.common ] ; then cd $$d ; cvs -Q update ; fi ; echo "$$d/Makefile.common" ; break ; fi ; done
endef

MAKEFILE_COMMON := $(shell $(find-makefile-common))

ifeq ($(MAKEFILE_COMMON),)
# attempt a checkout
define checkout-makefile-common
test -f CVS/Root && { cvs -Q -d $$(cat CVS/Root) checkout common && echo "common/Makefile.common" ; } || { echo "ERROR: I can't figure out how to checkout the 'common' module." ; exit -1 ; } >&2
endef

MAKEFILE_COMMON := $(shell $(checkout-makefile-common))
endif

dracut_tarball:
	mkdir stage
	ln -s ../kdump_initscripts stage/kdump_initscripts
	ln -s ../kdump_sample_manifests stage/kdump_sample_manifests
	ln -s ../kdump_dracut_modules stage/kdump_dracut_modules
	tar -C stage -j -h -c --exclude=CVS -f ./dracut-files.tbz2 .
	rm -rf stage

include $(MAKEFILE_COMMON)
