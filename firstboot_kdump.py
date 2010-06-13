#
# firstboot_kdump.py - kdump configuration page for firstboot
# Copyright 2006 Red Hat, Inc.
# Author: Jarod Wilson <jwilson@redhat.com>
# Contributors:
#	 Neil Horman <nhorman@redhat.com>
#	 Dave Lehman <dlehman@redhat.com>
#
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

import sys
sys.path.append('/usr/share/system-config-kdump/')

from gtk import *
import string
import os
import os.path
import time
import gtk
import gobject
import commands
from firstboot.config import *
from firstboot.constants import *
from firstboot.functions import *
from firstboot.module import *
import gettext
_ = lambda x: gettext.ldgettext("firstboot", x)
N_ = lambda x: x

class moduleClass(Module):
	def __init__(self):
		Module.__init__(self)
		self.priority = 100
		self.sidebarTitle = N_("Kdump")
		self.title = N_("Kdump")
		self.reboot = False

	# runPriority determines the order in which this module runs in firstboot
	runPriority = 70
	moduleName = _("Kdump")
	windowName = moduleName
	reboot = False

	# possible bootloaders we'll need to adjust
	#			 bootloader : (config file, kdump offset)
	bootloaders = { "grub"   : (["/boot/grub/grub.conf", "/boot/efi/EFI/redhat/grub.conf"], [16, 256]),
					"yaboot" : (["/boot/etc/yaboot.conf"], [32]),
					"elilo"  : (["/boot/efi/EFI/redhat/elilo.conf"], [256]) }
	bootloader = None
	offset = 0

	# list of architectures without kdump support
	unsupportedArches = [ "ppc", "s390", "s390x", "i386", "i586" ]

	# list of platforms that have a separate kernel-kdump
	kernelKdumpArches = [ "ppc64" ]
	kernelKdumpInstalled = False

	def needsReboot(self):
		return self.reboot

	# toggle sensitivity of kdump config bits
	def showHide(self, status):
		self.totalMem.set_sensitive(status)
		self.kdumpMem.set_sensitive(status)
		self.systemUsableMem.set_sensitive(status)
		self.labelTotal.set_sensitive(status)
		self.labelKdump.set_sensitive(status)
		self.labelSys.set_sensitive(status)
		self.kdumpEnabled = status

	def on_enableKdumpCheck_toggled(self, *args):
		showHideStatus = self.enableKdumpCheck.get_active()
		self.showHide(showHideStatus)

	def updateAvail(self, widget, spin):
		self.remMem = self.availMem - spin.get_value_as_int()
		self.systemUsableMem.set_text("%s" % self.remMem)

	def getBootloader(self):
		for (name, (conf, offset)) in self.bootloaders.items():
			i = 0
			for c in conf:
				if os.access(c, os.W_OK):
					self.bootloader = name
					self.offset = i
					return self.bootloader
				i += 1

		self.offset = None
		self.bootloader = None
		return None

	def createScreen(self, doDebug = None):
		self.doDebug = doDebug

		if doDebug:
			print "initializing kdump module"

		# What kernel are we running?
		self.runningKernel = os.popen("/bin/uname -r").read().strip()

		# What arch are we running on?
		self.arch = os.popen("/bin/uname -m").read().strip()

		# Check for a xen kernel, kdump doesn't work w/xen just yet...
		self.xenKernel = self.runningKernel.find("xen")

		# Fedora or RHEL?
		releaseFile = '/etc/redhat-release'
		self.distro = 'rhel'
		lines = open(releaseFile).readlines()
		for line in lines:
			if line.find("Fedora") != -1:
				self.distro = 'fedora'
				kernelKdumpArchesFC = [ "i686", "x86_64" ]
				self.kernelKdumpArches.extend(kernelKdumpArchesFC)
				break

		# If we need kernel-kdump, check to see if its already installed
		if self.arch in self.kernelKdumpArches:
			self.kernelKdump = "/boot/vmlinux-%skdump" % self.runningKernel
			if os.access(self.kernelKdump, os.R_OK):
				self.kernelKdumpInstalled = True

		# Ascertain how much memory is in the system
		memInfo = open("/proc/meminfo").readlines()
		self.availMem = 0
		for line in memInfo:
				if line.startswith("MemTotal:"):
					self.availMem = int(line.split()[1]) / 1024
					break

		# Fix up memory calculations if kdump is already on
		cmdLine = open("/proc/cmdline").read()
		self.kdumpMem = 0
		self.kdumpOffset = 0
		self.origCrashKernel = ""
		self.kdumpEnabled = False
		chkConfigStatus=commands.getoutput('/sbin/chkconfig --list kdump')
		if chkConfigStatus.find("on") > -1:
			self.kdumpEnabled = True
		self.kdumpMemInitial = 0
		if cmdLine.find("crashkernel") > -1:
			crashString = filter(lambda t: t.startswith("crashkernel="),
					 cmdLine.split())[0].split("=")[1]
			if self.doDebug:
				print "crashString is %s" % crashString
			if crashString.find("@") != -1:
				(self.kdumpMem, self.kdumpOffset) = [int(m[:-1]) for m in crashString.split("@")]
			else:
				self.kdumpMem = int(crashString[:-1])
				self.kdumpOffset = 0
			self.availMem += self.kdumpMem
			self.origCrashKernel = "%dM" % (self.kdumpMem)
			self.kdumpMemInitial = self.kdumpMem
			self.kdumpEnabled = True
		else:
			self.kdumpEnabled = False
		self.initialState = self.kdumpEnabled

		# Do some sanity-checking and try to present only sane options.
		#
		# Defaults
		lowerBound = 128
		minUsable = 256
		step = 64
		self.enoughMem = True
		if self.arch == 'ia64':
			# ia64 usually needs at *least* 256M, page-aligned... :(
			lowerBound = 256
			minUsable = 512
			step = 256
		elif self.arch == 'ppc64':
			# ppc64 often fails w/128M lately, and we want at least 1G
			# of RAM for normal use, due to 64k page size... :\
			lowerBound = 256
			minUsable = 1024

		upperBound = (self.availMem - minUsable) - (self.availMem % step)

		if upperBound < lowerBound:
			self.enoughMem = False

		# Set spinner to lowerBound unless already set on kernel command line
		if self.kdumpMem == 0:
			self.kdumpMem = lowerBound
		else:
			# round down to a multiple of step value
			self.kdumpMem = self.kdumpMem - (self.kdumpMem % step)

		# kdump enable/disable checkbox
		self.enableKdumpCheck = gtk.CheckButton("Enable kdump?")
		self.enableKdumpCheck.set_alignment(xalign=0, yalign=0)

		# detected total amount of system memory
		self.totalMem = gtk.Label(_("%s" % self.availMem))
		self.labelTotal = gtk.Label(_("_Total System Memory (MB):"))
		self.labelTotal.set_use_underline(True)
		self.labelTotal.set_mnemonic_widget(self.totalMem)
		self.labelTotal.set_alignment(0.0, 0.5)
		self.labelTotal.set_width_chars(32)

		# how much ram to reserve for kdump
		self.memSpin = gtk.Adjustment(self.kdumpMem, lowerBound, upperBound, step, step, 64)
		self.kdumpMem = gtk.SpinButton(self.memSpin, 0, 0)
		self.kdumpMem.set_update_policy(gtk.UPDATE_IF_VALID)
		self.kdumpMem.set_numeric(True)
		self.memSpin.connect("value_changed", self.updateAvail, self.kdumpMem)
		self.labelKdump = gtk.Label(_("_Kdump Memory (MB):"))
		self.labelKdump.set_use_underline(True)
		self.labelKdump.set_mnemonic_widget(self.kdumpMem)
		self.labelKdump.set_alignment(0.0, 0.5)

		# remaining usable system memory
		self.resMem = eval(string.strip(self.kdumpMem.get_text()))
		self.remMem = self.availMem - self.resMem
		self.systemUsableMem = gtk.Label(_("%s" % self.remMem))
		self.labelSys = gtk.Label(_("_Usable System Memory (MB):"))
		self.labelSys.set_use_underline(True)
		self.labelSys.set_mnemonic_widget(self.systemUsableMem)
		self.labelSys.set_alignment(0.0, 0.5)
		
		self.vbox = gtk.VBox()
		self.vbox.set_size_request(400, 200)

		# title_pix = loadPixbuf("workstation.png")

		internalVBox = gtk.VBox()
		internalVBox.set_border_width(10)
		internalVBox.set_spacing(10)

		label = gtk.Label(_("Kdump is a kernel crash dumping mechanism. In the event of a "
							"system crash, kdump will capture information from your system "
							"that can be invaluable in determining the cause of the crash. "
							"Note that kdump does require reserving a portion of system "
							"memory that will be unavailable for other uses."))

		label.set_line_wrap(True)
		label.set_alignment(0.0, 0.5)
		label.set_size_request(500, -1)
		internalVBox.pack_start(label, False, True)

		table = gtk.Table(2, 4)

		table.attach(self.enableKdumpCheck, 0, 2, 0, 1, gtk.FILL, gtk.FILL, 5, 5)

		table.attach(self.labelTotal, 0, 1, 1, 2, gtk.FILL)
		table.attach(self.totalMem, 1, 2, 1, 2, gtk.SHRINK, gtk.FILL, 5, 5)

		table.attach(self.labelKdump, 0, 1, 2, 3, gtk.FILL)
		table.attach(self.kdumpMem, 1, 2, 2, 3, gtk.SHRINK, gtk.FILL, 5, 5)

		table.attach(self.labelSys, 0, 1, 3, 4, gtk.FILL)
		table.attach(self.systemUsableMem, 1, 2, 3, 4, gtk.SHRINK, gtk.FILL, 5, 5)

		# disable until user clicks check box, if not already enabled
		if self.initialState is False:
			self.showHide(False)
		else:
			self.enableKdumpCheck.set_active(True)

		internalVBox.pack_start(table, True, 15)

		# toggle sensitivity of Mem items
		self.enableKdumpCheck.connect("toggled", self.on_enableKdumpCheck_toggled)

		self.vbox.pack_start(internalVBox, False, 15)

	def grabFocus(self):
		self.enableKdumpCheck.grab_focus()

	def apply(self, *args):
		if self.kdumpEnabled:
			totalSysMem = self.totalMem.get_text()
			totalSysMem = eval(string.strip(totalSysMem))
			reservedMem = self.kdumpMem.get_value_as_int()
			remainingMem = totalSysMem - reservedMem
		else:
			reservedMem = self.kdumpMemInitial

		if self.doDebug:
			print "Running kernel %s on %s architecture" % (self.runningKernel, self.arch)
			if self.enableKdumpCheck.get_active():
				print "System Mem: %s MB	Kdump Mem: %s MB	Avail Mem: %s MB" % (totalSysMem, reservedMem, remainingMem)
			else:
				print "Kdump will be disabled"

		# If the user simply doesn't have enough memory for kdump to be viable/supportable, tell 'em
		if self.enoughMem is False and self.kdumpEnabled:
			self.showErrorMessage(_("Sorry, your system does not have enough memory for kdump to be viable!"))
			self.enableKdumpCheck.set_active(False)
			self.showHide(False)
			return RESULT_FAILURE 
		# Alert user that we're not going to turn on kdump if they're running a xen kernel
		elif self.xenKernel != -1 and self.kdumpEnabled:
			self.showErrorMessage(_("Sorry, Xen kernels do not support kdump at this time!"))
			self.enableKdumpCheck.set_active(False)
			self.showHide(False)
			return RESULT_FAILURE 
		# If there's no kdump support on this arch, let the user know and don't configure
		elif self.arch in self.unsupportedArches:
			self.showErrorMessage(_("Sorry, the %s architecture does not support kdump at this time!" % self.arch))
			self.enableKdumpCheck.set_active(False)
			self.showHide(False)
			return RESULT_FAILURE 

		# If running on an arch w/a separate kernel-kdump (i.e., non-relocatable kernel), check to
		# see that its installed, otherwise, alert the user they need to install it, and give them
		# the chance to abort configuration.
		if self.arch in self.kernelKdumpArches and self.kernelKdumpInstalled is False:
			kernelKdumpNote = "\n\nNote that the %s architecture does not feature a relocatable kernel at this time, and thus requires a separate kernel-kdump package to be installed for kdump to function. This can be installed via 'yum install kernel-kdump' at your convenience.\n\n" % self.arch
		else:
			kernelKdumpNote = ""

		# Don't alert if nothing has changed
		if self.initialState != self.kdumpEnabled or reservedMem != self.kdumpMemInitial:
			dlg = gtk.MessageDialog(None, 0, gtk.MESSAGE_INFO,
									gtk.BUTTONS_YES_NO,
									_("Changing Kdump settings requires rebooting the "
									  "system to reallocate memory accordingly. %sWould you "
									  "like to continue with this change and reboot the "
									  "system after firstboot is complete?" % kernelKdumpNote))
			dlg.set_position(gtk.WIN_POS_CENTER)
			dlg.show_all()
			rc = dlg.run()
			dlg.destroy()

			if rc == gtk.RESPONSE_NO:
				self.reboot = False
				return RESULT_SUCCESS 
			else:
				self.reboot = True

				# Find bootloader if it exists, and update accordingly
				if self.getBootloader() == None:
					self.showErrorMessage(_("Error! No bootloader config file found, aborting configuration!"))
					self.enableKdumpCheck.set_active(False)
					self.showHide(False)
					return RESULT_FAILURE 

				# Are we adding or removing the crashkernel param?
				if self.kdumpEnabled:
					grubbyCmd = "/sbin/grubby --%s --update-kernel=/boot/vmlinuz-%s --args=crashkernel=%iM" \
								% (self.bootloader, self.runningKernel, reservedMem)
					chkconfigStatus = "on"
				else:
					grubbyCmd = "/sbin/grubby --%s --update-kernel=/boot/vmlinuz-%s --remove-args=crashkernel=%s" \
								% (self.bootloader, self.runningKernel, self.origCrashKernel)
					chkconfigStatus = "off" 

				if self.doDebug:
					print "Using %s bootloader with %iM offset" % (self.bootloader, self.offset)
					print "Grubby command would be:\n	%s" % grubbyCmd
				else:
					os.system(grubbyCmd)
					os.system("/sbin/chkconfig kdump %s" % chkconfigStatus)
					if self.bootloader == 'yaboot':
						os.system('/sbin/ybin')
		else:
			self.reboot = False


		return RESULT_SUCCESS

	def showErrorMessage(self, text):
		dlg = gtk.MessageDialog(None, 0, gtk.MESSAGE_ERROR, gtk.BUTTONS_OK, text)
		dlg.set_position(gtk.WIN_POS_CENTER)
		dlg.set_modal(True)
		rc = dlg.run()
		dlg.destroy()
		return None

	def initializeUI(self):
		pass

