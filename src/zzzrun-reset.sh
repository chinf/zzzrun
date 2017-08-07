#!/bin/sh

# zzzrun-reset - reset zzzrun's device cache
# Copyright (C) 2017 Francis Chin <dev@fchin.com>
#
# Repository: https://github.com/chinf/zzzrun
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU Lesser General Public License as published
# by the Free Software Foundation, either version 3 of the License, or (at
# your option) any later version.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser
# General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# Remove the device information cache file so that the next
# invocation of zzzrun will recreate a fresh cache file

readonly DEFAULTCACHE="/var/cache/zzzrun-cache"

# Set environment
. /etc/profile.d/zzzrun.sh

CACHEFILE="${ZZZRUNCACHE:-$DEFAULTCACHE}"

if [ $(id -u) -ne 0 ]; then
  echo "Please run $(basename $0) as root"
  exit 2
fi

if [ -e "${CACHEFILE}" ]; then
  /bin/rm "${CACHEFILE}"
fi
