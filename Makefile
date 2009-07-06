# Makefile for source rpm: kexec-tools
# $Id$
NAME := kexec-tools
SPECFILE = $(firstword $(wildcard *.spec))

SUBDIRS = kcp

define find-makefile-common
for d in common ../common ../../common ; do if [ -f $$d/Makefile.common ] ; then if [ -f $$d/CVS/Root -a -w $$/Makefile.common ] ; then cd $$d ; cvs -Q update ; fi ; echo "$$d/Makefile.common" ; break ; fi ; done
endef

MAKEFILE_COMMON := $(shell $(find-makefile-common))

ifeq ($(MAKEFILE_COMMON),)
# attempt a checkout
define checkout-makefile-common
test -f CVS/Root && { cvs -Q -d $$(cat CVS/Root) checkout common && echo "common/Makefile.common" ; } || { echo "ERROR: I can't figure out how to checkout the 'common' module." ; exit -1 ; } >&2
endef

MAKEFILE_COMMON := $(shell $(checkout-makefile-common))
endif

mkdumprd2_tarball:
	mkdir stage
	ln -s ../kdump_build_helpers stage/kdump_build_helpers
	ln -s ../kdump_runtime_helpers stage/kdump_runtime_helpers
	ln -s ../kdump_initscripts stage/kdump_initscripts
	ln -s ../kdump_sample_manifests stage/kdump_sample_manifests
	ln -s ../mkdumprd2_functions stage/mkdumprd2_functions
	tar -C stage -j -h -c --exclude=CVS -f ./mkdumprd2-files.tbz2 .
	rm -rf stage

include $(MAKEFILE_COMMON)
