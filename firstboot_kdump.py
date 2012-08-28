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
_ = lambda x: gettext.ldgettext("kexec-tools", x)
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
	# todo: f18 grub2 for efi
	#			 bootloader : (config file, kdump offset)
	bootloaders = { "grub"   : (["/boot/grub/grub.conf", "/boot/efi/EFI/redhat/grub.conf"], [16, 256]),
					"grub2"   : (["/boot/grub2/grub.cfg"], [16, 256]),
					"zipl" : (["/etc/zipl.conf"], [0]),
					"yaboot" : (["/boot/etc/yaboot.conf"], [32]) }
	bootloader = None
	offset = 0

	# list of architectures without kdump support
	unsupportedArches = [ "ppc", "s390", "i386", "i586" ]

	def needsReboot(self):
		return self.reboot

	# toggle sensitivity of kdump config bits
	def showHideReserve(self, status):
		self.labelKdump.set_sensitive(status)
		self.kdumpMemspin.set_sensitive(status)
		self.totalMem.set_sensitive(status)
		self.systemUsableMem.set_sensitive(status)
		self.labelTotal.set_sensitive(status)
		self.labelSys.set_sensitive(status)

	# toggle sensitivity of kdump config bits
	def showHide(self, status):
		show_kdumpmem = status
		if self.distro == 'rhel':
			show_autoreserve = self.buttonAuto.get_active()
			if status == True:
				if self.buttonAuto.get_active() == True:
					show_kdumpmem = False
			self.buttonAuto.set_active(show_autoreserve)
			self.buttonManual.set_active(not show_autoreserve)
			self.labelReserve.set_sensitive(status)
			self.buttonAuto.set_sensitive(status)
			self.buttonManual.set_sensitive(status)
		self.showHideReserve(show_kdumpmem)
		self.labelReserved.set_sensitive(status)
		self.labelReservedMemsize.set_sensitive(status)
		self.kdumpEnabled = status
		self.AdvWindow.set_sensitive(status)

	def on_enableKdumpCheck_toggled(self, *args):
		showHideStatus = self.enableKdumpCheck.get_active()
		self.showHide(showHideStatus)

	def on_auto_toggled(self, *args):
		if self.distro == 'rhel':
			self.showHideReserve(not self.buttonAuto.get_active())

	def on_manual_toggled(self, *args):
		if self.distro == 'rhel':
			self.showHideReserve(self.buttonManual.get_active())

	def updateAvail(self, widget, spin):
		self.reserveMem = eval(string.strip(self.kdumpMemspin.get_text()))
		self.remainingMem = self.availMem - self.reserveMem
		self.systemUsableMem.set_text("%s" % self.remainingMem)

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
		lines = open(releaseFile).readlines()
		for line in lines:
			if line.find("Fedora") != -1:
				self.distro = 'fedora'
			else:
				self.distro = 'rhel'

		# Ascertain how much memory is in the system
		memInfo = open("/proc/meminfo").readlines()
		self.availMem = 0
		for line in memInfo:
				if line.startswith("MemTotal:"):
					self.availMem = int(line.split()[1]) / 1024
					break

		# Fix up memory calculations if kdump is already on
		cmdLine = open("/proc/cmdline").read()
		self.kdumpOffset = 0
		self.origCrashKernel = ""
		self.kdumpEnabled = False
		chkConfigStatus=commands.getoutput('/bin/systemctl is-enabled kdump.service')
		if chkConfigStatus.find("enabled") > -1:
			self.kdumpEnabled = True
		self.kdumpMemInitial = 0

		crashString = ""
		kexec_crash_size = open("/sys/kernel/kexec_crash_size").read()
		self.reservedMem = int(kexec_crash_size)/(1024*1024)

		if cmdLine.find("crashkernel") != -1:
			crashString = filter(lambda t: t.startswith("crashkernel="),
					 cmdLine.split())[0].split("=")[1]
			self.origCrashKernel = "crashkernel=%s" % (crashString)
			if self.doDebug:
				print "crashString is %s" % crashString
			if crashString.find("@") != -1:
				(self.kdumpMemInitial, self.kdumpOffset) = [int(m[:-1]) for m in crashString.split("@")]
			else:
				#kdumpMemInitial = -1 means auto reservation
				if self.distro == 'rhel' and self.origCrashKernel == 'crashkernel=auto':
					self.kdumpMemInitial=-1
				else:
					self.kdumpMemInitial=int(crashString[:-1])
				self.kdumpOffset = 0
		if self.kdumpMemInitial != 0:
			self.availMem += self.reservedMem
			self.kdumpEnabled = True
		else:
			self.kdumpEnabled = False
			if self.origCrashKernel.find("crashkernel=") != -1:
				self.kdumpEnabled = True

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
		if self.kdumpMemInitial == 0 or  self.kdumpMemInitial == -1:
			self.kdumpMemInitial = lowerBound
		else:
			# round down to a multiple of step value
			self.kdumpMemInitial = self.kdumpMemInitial - (self.kdumpMemInitial % step)

		# kdump enable/disable checkbox
		self.enableKdumpCheck = gtk.CheckButton(_("_Enable kdump?"))
		self.enableKdumpCheck.set_alignment(xalign=0, yalign=0)

		# detected total amount of system memory
		self.totalMem = gtk.Label(_("%s" % self.availMem))
		self.labelTotal = gtk.Label(_("Total System Memory (MB):"))
		self.labelTotal.set_alignment(0.0, 0.5)
		self.labelTotal.set_width_chars(32)

		# how much ram to reserve for kdump
		self.memAdjustment = gtk.Adjustment(self.kdumpMemInitial, lowerBound, upperBound, step, step, 0)
		self.kdumpMemspin = gtk.SpinButton(self.memAdjustment, 0, 0)
		self.kdumpMemspin.set_update_policy(gtk.UPDATE_IF_VALID)
		self.kdumpMemspin.set_numeric(True)
		self.memAdjustment.connect("value_changed", self.updateAvail, self.kdumpMemspin)
		self.labelKdump = gtk.Label(_("Memory To Be _Reserved (MB):"))
		self.labelKdump.set_use_underline(True)
		self.labelKdump.set_mnemonic_widget(self.kdumpMemspin)
		self.labelKdump.set_alignment(0.0, 0.5)

		# remaining usable system memory
		self.reserveMem = eval(string.strip(self.kdumpMemspin.get_text()))
		self.remainingMem = self.availMem - self.reserveMem
		self.systemUsableMem = gtk.Label(_("%s" % self.remainingMem))
		self.labelSys = gtk.Label(_("Usable System Memory (MB):"))
		self.labelSys.set_alignment(0.0, 0.5)

		self.labelReserved=gtk.Label(_("Memory Currently Reserved (MB):"))
		self.labelReservedMemsize=gtk.Label(_("%s" % self.reservedMem))
		self.labelReserved.set_alignment(0.0, 0.5)

		# rhel crashkernel=auto handling
		if self.distro == 'rhel':
			self.labelReserve = gtk.Label(_("Kdump Memory Reservation:"))
			self.buttonAuto = gtk.RadioButton(None, _("_Automatic"))
			self.buttonManual = gtk.RadioButton(self.buttonAuto, _("_Manual"))
			self.buttonAuto.connect("toggled", self.on_auto_toggled, None)
			self.buttonManual.connect("toggled", self.on_manual_toggled, None)
			self.buttonAuto.set_use_underline(True)
			self.buttonManual.set_use_underline(True)
			self.labelReserve.set_alignment(0.0, 0.5)
			if self.origCrashKernel == 'crashkernel=auto':
				self.buttonAuto.set_active(True)
				self.buttonManual.set_active(False)
			else:
				self.buttonAuto.set_active(False)
				self.buttonManual.set_active(True)
			self.autoinitial = self.buttonAuto.get_active()


		# Add an advanced kdump config text widget
		inputbuf = open("/etc/kdump.conf", "r")
		self.AdvConfig = gtk.TextView()
		AdvBuf = gtk.TextBuffer()
		AdvBuf.set_text(inputbuf.read())
		inputbuf.close()

		self.AdvConfig.set_buffer(AdvBuf)
		self.AdvWindow = gtk.ScrolledWindow()
		self.AdvWindow.set_shadow_type(gtk.SHADOW_IN)
		self.AdvWindow.set_policy(gtk.POLICY_AUTOMATIC, gtk.POLICY_AUTOMATIC)
		self.AdvWindow.set_size_request(500, 300)
		self.AdvWindow.add(self.AdvConfig)

		self.AdvConfLabel = gtk.Label(_("\nAdvanced kdump configuration"))
		self.AdvConfLabel.set_alignment(0.0, 0.5)

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

		if self.distro == 'rhel':
			table = gtk.Table(3, 100)
			table.attach(self.enableKdumpCheck, 0, 3, 0, 1, gtk.FILL, gtk.FILL, 5, 5)
			table.attach(self.labelReserve, 0, 1, 1, 2, gtk.FILL)
			table.attach(self.buttonAuto, 1, 2, 1, 2, gtk.FILL, gtk.FILL, 5, 5)
			table.attach(self.buttonManual, 2, 3, 1, 2, gtk.FILL, gtk.FILL, 5, 5)
			table.attach(self.labelReserved, 0, 1, 2, 3, gtk.FILL)
			table.attach(self.labelReservedMemsize, 2, 3, 2, 3, gtk.SHRINK, gtk.FILL, 5, 5)
			table.attach(self.labelKdump, 0, 1, 3, 4, gtk.FILL)
			table.attach(self.kdumpMemspin, 2, 3, 3, 4, gtk.SHRINK, gtk.FILL, 5, 5)
			table.attach(self.labelTotal, 0, 1, 4, 5, gtk.FILL)
			table.attach(self.totalMem, 2, 3, 4, 5, gtk.SHRINK, gtk.FILL, 5, 5)
			table.attach(self.labelSys, 0, 1, 5, 6, gtk.FILL)
			table.attach(self.systemUsableMem, 2, 3, 5, 6, gtk.SHRINK, gtk.FILL, 5, 5)
			table.attach(self.AdvConfLabel, 0, 1, 6, 7, gtk.FILL)
			table.attach(self.AdvWindow, 0, 3, 7, 100, gtk.FILL, gtk.FILL, 5, 5)
		else:
			table = gtk.Table(2, 100)
			table.attach(self.enableKdumpCheck, 0, 2, 0, 1, gtk.FILL, gtk.FILL, 5, 5)
			table.attach(self.labelTotal, 0, 1, 1, 2, gtk.FILL)
			table.attach(self.totalMem, 1, 2, 1, 2, gtk.SHRINK, gtk.FILL, 5, 5)

			table.attach(self.labelKdump, 0, 1, 2, 3, gtk.FILL)
			table.attach(self.kdumpMemspin, 1, 2, 2, 3, gtk.SHRINK, gtk.FILL, 5, 5)

			table.attach(self.labelReserved, 0, 1, 3, 4, gtk.FILL)
			table.attach(self.labelReservedMemsize, 1, 2, 3, 4, gtk.SHRINK, gtk.FILL, 5, 5)

			table.attach(self.labelSys, 0, 1, 4, 5, gtk.FILL)
			table.attach(self.systemUsableMem, 1, 2, 4, 5, gtk.SHRINK, gtk.FILL, 5, 5)

			table.attach(self.AdvConfLabel, 0, 1, 6, 7, gtk.FILL)
			table.attach(self.AdvWindow, 0, 2, 7, 100, gtk.FILL, gtk.FILL, 5, 5)

		# disable until user clicks check box, if not already enabled
		if self.initialState is False:
			self.showHide(False)
		else:
			self.enableKdumpCheck.set_active(True)
			self.showHide(True)

		internalVBox.pack_start(table, True, 15)

		# toggle sensitivity of Mem items
		self.enableKdumpCheck.connect("toggled", self.on_enableKdumpCheck_toggled)

		self.vbox.pack_start(internalVBox, False, 15)

	def grabFocus(self):
		self.enableKdumpCheck.grab_focus()

	def configChanged(self):
		if self.initialState == self.kdumpEnabled and self.initialState == False:
			return False
		if self.initialState != self.kdumpEnabled \
		or (self.distro == 'rhel' and self.autoinitial != self.buttonAuto.get_active()) \
		or (self.distro == 'rhel' and self.buttonManual.get_active() == True and self.reserveMem != self.kdumpMemInitial) \
		or (self.distro != 'rhel' and self.reserveMem != self.kdumpMemInitial):
			return True
		return False


	def apply(self, *args):
		if self.kdumpEnabled:
			self.reserveMem = self.kdumpMemspin.get_value_as_int()
		else:
			self.reserveMem = self.kdumpMemInitial
		self.remainingMem = self.availMem - self.reserveMem
		if self.doDebug:
			print "Running kernel %s on %s architecture" % (self.runningKernel, self.arch)
			if self.enableKdumpCheck.get_active():
				print "System Mem: %s MB	Kdump Mem: %s MB	Avail Mem: %s MB" % (totalSysMem, self.reserveMem, self.remainingMem)
			else:
				print "Kdump will be disabled"

		# Before we do other checks we should save the users config
		AdvBuf = self.AdvConfig.get_buffer()
		start, end = AdvBuf.get_bounds()
		outputbuf = open("/etc/kdump.conf", "rw+")
		outputbuf.write(AdvBuf.get_text(start, end))
		outputbuf.close()

		# Regardless of what else happens we need to be sure to disalbe kdump if its disabled here, or
		# else it will fail during startup
		if (self.enableKdumpCheck.get_active() == False):
			os.system("/bin/systemctl disable kdump.service")

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

		# Don't alert if nothing has changed
		if self.configChanged() == True:
			dlg = gtk.MessageDialog(None, 0, gtk.MESSAGE_INFO,
									gtk.BUTTONS_YES_NO,
									_("Changing Kdump settings requires rebooting the "
									  "system to reallocate memory accordingly. Would you "
									  "like to continue with this change and reboot the "
									  "system after firstboot is complete?"))
			dlg.set_position(gtk.WIN_POS_CENTER)
			dlg.show_all()
			rc = dlg.run()
			dlg.destroy()

			if rc != gtk.RESPONSE_YES:
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
					_reserves = "%iM" % (self.reserveMem)
					if self.distro == 'rhel':
						if self.buttonAuto.get_active() == True:
							_reserves = 'auto'

					grubbyCmd = "/sbin/grubby --%s --update-kernel=ALL --args=crashkernel=%s" \
								% (self.bootloader, _reserves)
					chkconfigStatus = "enable"
				else:
					grubbyCmd = "/sbin/grubby --%s --update-kernel=ALL --remove-args=%s" \
								% (self.bootloader, self.origCrashKernel)
					chkconfigStatus = "disable"

				if self.doDebug:
					print "Using %s bootloader with %iM offset" % (self.bootloader, self.offset)
					print "Grubby command would be:\n	%s" % grubbyCmd
					print "chkconfig status is %s" % chkconfigStatus
				else:
					os.system(grubbyCmd)
					os.system("/bin/systemctl %s kdump.service" % (chkconfigStatus))
					if self.bootloader == 'yaboot':
						os.system('/sbin/ybin')
					if self.bootloader == 'zipl':
						os.system('/sbin/zipl')
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

