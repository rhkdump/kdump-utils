#
# Makefile for the PO files (translation) catalog
#
# $Id: Makefile,v 1.1.1.1 2007/03/08 02:27:37 ccheng Exp $

# What is this package?
NLSPACKAGE	= kexec-tools
POTFILE		= $(NLSPACKAGE).pot
INSTALL		= /usr/bin/install -c
INSTALL_DATA	= $(INSTALL) -m 644
INSTALL_DIR	= /usr/bin/install -d

# destination directory
INSTALL_NLS_DIR = $(DESTDIR)/usr/share/locale

# PO catalog handling
MSGMERGE	= msgmerge -v --update
XGETTEXT	= xgettext --default-domain=$(NLSPACKAGE) \
		  --add-comments		  
MSGFMT		= msgfmt --statistics --verbose

# What do we need to do
POFILES		= $(wildcard *.po)
MOFILES		= $(patsubst %.po,%.mo,$(POFILES))
PYSRC		= $(wildcard ../*.py)
SRCFILES	= $(PYSRC)

#default:: clean

all:: $(MOFILES)

clean:
	@rm -fv *mo *~ .depend

install: $(MOFILES)
	@for n in $(MOFILES); do \
	    l=`basename $$n .mo`; \
	    $(INSTALL_DIR) $(INSTALL_NLS_DIR)/$$l/LC_MESSAGES; \
	    $(INSTALL_DATA) --verbose $$n $(INSTALL_NLS_DIR)/$$l/LC_MESSAGES/$(NLSPACKAGE).mo; \
	done

%.mo: %.po
	$(MSGFMT) -o $@ $<

$(POTFILE): $(SRCFILES)
	$(XGETTEXT) --output=$(POTFILE) $(SRCFILES)

merge: $(POTFILE) $(POFILES)
	for file in $(POFILES); do \
		base=`basename $$file`; \
		echo "$(MSGMERGE) $$base $(NLSPACKAGE).pot"; \
		$(MSGMERGE) $$base $(NLSPACKAGE).pot; \
	done

tgz:
	@rm -rf ../kexec-tools-po
	@mkdir ../kexec-tools-po
	@cp $(POFILES) Makefile ../kexec-tools-po
	@tar -czvf ../kexec-tools-po-$(shell date +%Y%m%d).tgz ../kexec-tools-po

.PHONY: missing depend
