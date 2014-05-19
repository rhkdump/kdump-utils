# Kdump anaconda configuration
#
# Copyright (C) 2013 Red Hat, Inc.
#
# This copyrighted material is made available to anyone wishing to use,
# modify, copy, or redistribute it subject to the terms and conditions of
# the GNU General Public License v.2, or (at your option) any later version.
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY expressed or implied, including the implied warranties of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General
# Public License for more details.  You should have received a copy of the
# GNU General Public License along with this program; if not, write to the
# Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
# 02110-1301, USA.  Any Red Hat trademarks that are incorporated in the
# source code or documentation are not subject to the GNU General Public
# License and may only be used or replicated with the express permission of
# Red Hat, Inc.
#
# Red Hat Author(s): David Shea <dshea@redhat.com>
#

"""Kdump anaconda TUI configuration"""

import re

from pyanaconda.ui.tui.spokes import EditTUISpoke
from pyanaconda.ui.tui.spokes import EditTUISpokeEntry as Entry
from com_redhat_kdump.common import getOS, getMemoryBounds
from com_redhat_kdump.i18n import N_, _

__all__ = ["KdumpSpoke"]

class _re:
    def __init__(self, patten, low, up):
        self.re = re.compile(patten)
        self.low = low
        self.up = up

    def match(self, key):
        if self.re.match(key):
            if key == "auto":
                return True
            if key[-1] == 'M':
                key = key[:-1]
            key = int(key)
            if key <= self.up and key >= self.low :
                return True
        return False

lower, upper ,step = getMemoryBounds()
# Allow either "auto" or a string of digits optionally followed by 'M'
RESERVE_VALID = _re(r'^((auto)|(\d+M?))$', lower, upper)
FEDORA_RESERVE_VALID = _re(r'^(\d+M?)$', lower, upper)

class KdumpSpoke(EditTUISpoke):
    title = N_("Kdump")
    category = "system"

    edit_fields = [
        Entry("Enable kdump", "enabled", EditTUISpoke.CHECK, True),
        Entry("Reserve amount", "reserveMB", RESERVE_VALID, lambda self,args: args.enabled)
        ]

    def __init__(self, app, data, storage, payload, instclass):
        if getOS() == "fedora":
            KdumpSpoke.edit_fields = [
                Entry("Enable kdump", "enabled", EditTUISpoke.CHECK, True),
                Entry("Reserve amount", "reserveMB", FEDORA_RESERVE_VALID, lambda self,args: args.enabled)
                ]

        EditTUISpoke.__init__(self, app, data, storage, payload, instclass)
        self.args = self.data.addons.com_redhat_kdump

    def apply(self):
        pass

    @property
    def completed(self):
        return True

    @property
    def status(self):
        if self.args.enabled:
            state = _("Kdump is enabled")
        else:
            state = _("Kdump is disabled")
        return state
