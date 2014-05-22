# Kdump configuration common methods
#
# Copyright (C) 2014 Red Hat, Inc.
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
import os
__all__ = ["getReservedMemory", "getTotalMemory", "getMemoryBounds", "getOS"]

from pyanaconda.isys import total_memory
from pyanaconda.flags import flags
from com_redhat_kdump.constants import OS_RELEASE

_reservedMemory = None
def getReservedMemory():
    """Return the amount of memory currently reserved for kdump in MB."""
    global _reservedMemory

    # Check if the value has already been read
    if _reservedMemory is not None:
        return _reservedMemory

    try:
        with open("/sys/kernel/kexec_crash_size", "r") as fobj:
            _reservedMemory = int(fobj.read()) / (1024*1024)
            return _reservedMemory
    except (ValueError, IOError):
        return 0

def getTotalMemory():
    """Return the total amount of system memory in MB

       This is the amount reported by /proc/meminfo plus the aount
       currently reserved for kdump.
    """

    # total_memory return memory in KB, convert to MB
    availMem = total_memory() / 1024

    return availMem + getReservedMemory()

def getMemoryBounds():
    """Return a tuple of (lower, upper, step) for kdump reservation limits.

       If there is not enough memory available to use kdump, both lower and
       upper will be 0.
    """

    totalMemory = getTotalMemory()

    if flags.targetarch == 'ppc64':
        lowerBound = 256
        minUsable = 1024
        step = 1
    else:
        lowerBound = 128
        minUsable = 256
        step = 1

    upperBound = (totalMemory - minUsable) - (totalMemory % step)

    if upperBound < lowerBound:
        upperBound = lowerBound = 0

    return (lowerBound, upperBound, step)

def getOS():
    with open(os.path.normpath(OS_RELEASE), "r") as fobj:
             line = fobj.readline()

    if not "Fedora" in line:
        return "redhat"
    else:
        return "fedora"
