#!/bin/bash

# zzzrun - Run command only if ZFS pool has no sleeping hard drives
# Copyright (C) 2017 Francis Chin <dev@fchin.com>
#
# Repository: https://github.com/chinf/zzzrun
#
# Based on durandalTR's zstandby script
# (https://github.com/zfsonlinux/pkg-zfs/issues/54) and also
# zfs-auto-snapshot (https://github.com/zfsonlinux/zfs-auto-snapshot)
# 
# Awk compatibility note:
# Tested with mawk and gawk for wider compatibility
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

SUBSTOKEN="@zzzrun-pool"
VERBOSITY=0

print_usage() {
  echo "Usage: $0 [options] [-p POOL]... COMMAND [${SUBSTOKEN}] ...
Run a command only if a ZFS pool has no hard drives in standby or sleep
power modes.

  -s           Single run.  By default zzzrun will check and execute on a
               per pool basis.  This option will instead check all disks
               across all pools in scope and execute COMMAND just once if
               there are no disks in standby/sleep.

  -v           Verbose mode.  Report warnings and information.  By default
               this utility will only report errors.

  -vv          Very verbose.  Report debugging messages.

  -p POOL      Specify a pool to check, otherwise all available pools are
               included by default.  Repeat this option to specify more
               than one pool.  Any pools specified that are unavailable
               will be ignored.

  COMMAND      Command to execute if no hard drives in the pool(s) are in
               standby or sleep modes.
               Optionally, use the token ${SUBSTOKEN} one or more times
               in the command's arguments to have zzzrun insert the pool
               scope when running the command.
               If using zzzrun -s this will be a list of all available
               specified pools, otherwise this will be the name of each
               pool as zzzrun iterates through them.
" >&2
exit 2
}

print_log() { # level, message
  local LEVEL=$1
  shift 1
  case $LEVEL in
    (err*) echo -e "Error: $*" >&2 ;;
    (war*) if [ $VERBOSITY -gt 0 ]; then echo -e "Warning: $*" >&2; fi ;;
    (inf*) if [ $VERBOSITY -gt 0 ]; then echo -e "$*" >&2; fi ;;
    (deb*) if [ $VERBOSITY -gt 1 ]; then echo -e "Debug: $*" >&2; fi ;;
  esac
}

#
# Options parsing
#
ALLPOOLS=yes
ZPOOLLIST=$(env zpool list -H -o name)
POOLS=""
PERPOOL=yes

while getopts ":svp:" OPT; do
  case "${OPT}" in
    s) PERPOOL=no ;;
    v) VERBOSITY=`expr $VERBOSITY + 1` ;;
    p)
      if [ -z "${OPTARG}" ]; then print_usage; fi

      ALLPOOLS=no

      # Validate argument against currently available pools
      for ZPOOL in $ZPOOLLIST
      do
        if [ $OPTARG = $ZPOOL ]; then POOLS+="${OPTARG} "; fi
      done
      ;;
    *) print_usage ;;
  esac
done
shift $((OPTIND-1))

#
# Configuration validation
#
if [ -z "$*" ]; then print_usage; fi
COMMAND="$*"
print_log debug "COMMAND: $COMMAND"

if [[ `id -u` -ne 0 ]]; then
  echo "Please run as root"
  exit 2
fi

if [ $ALLPOOLS = "no" ]; then
  if [ -z "$POOLS" ]; then
    print_log warn "None of the pools specified are available"
    print_log debug "ZPOOLLIST: ${ZPOOLLIST}"
    exit 3
  fi
else
  if [ -n "$ZPOOLLIST" ]; then
    POOLS="$ZPOOLLIST"
  else
    print_log warn "No pools are available on this system"
    exit 3
  fi
fi
print_log info "Pool(s) available to process:\n${POOLS}"
print_log debug "Processing per pool: ${PERPOOL}"

#
# Main functions
#
get_pool_disks() { # pool list
  local SCOPE="$1"
  print_log debug "Finding hard drives in pool(s):\n${SCOPE}"

  # Parse zpool status to get all devices used by the specified pool(s)
  local DEVS=$(env LC_ALL=C zpool status -L $SCOPE \
    | awk '/^\t +.+ +[A-Z]+ +[0-9]+ +[0-9]+ +[0-9]+/ \
    { print "/dev/"$1 }')
  print_log debug "DEVS:\n${DEVS}"

  # Filter pool device list down to just hard drives
  # Using lsblk to lookup parent device (in case dev is a partition
  # or luks container) and rotational parameter
  local HDDS=$(env LC_ALL=C echo "${DEVS}" \
    | xargs lsblk -Pso name,rota,type 2>/dev/null \
    | awk '/ROTA="1" TYPE="disk"$/ { sub("NAME=\"","/dev/"); \
      sub("\"",""); print $1 }' | sort -u)
  print_log debug "HDDS:\n${HDDS}"

  echo $HDDS
}

count_standby_disks() { # hdds
  local DISKS="$1"
  print_log debug "Counting disks in standby or sleeping states"

  local DRIVESTATES=$(env echo "${DISKS}" | xargs hdparm -C)
  print_log debug "DRIVESTATES:\n${DRIVESTATES}"

  local UNKNOWNS=$(env echo "${DRIVESTATES}" | grep -cE 'unknown')
  if [ $UNKNOWNS -gt 0 ]; then
    print_log warn "Unable to read status for at least one drive"
  fi

  echo "${DRIVESTATES}" | grep -cE 'standby|sleeping'
}

run_action() { # pool list
  local SCOPE="$1"

  local CMD=$(env echo $COMMAND | sed "s/${SUBSTOKEN}/${SCOPE}/g")
  print_log debug "Executing command '${CMD}':"

  $CMD >&2
}

#
# main()
#
for POOL in $POOLS
do
  if [ $PERPOOL = "yes" ]; then
    POOLSCOPE="${POOL}"
  else
    POOLSCOPE="${POOLS}"
  fi

  POOLDISKS=`get_pool_disks "${POOLSCOPE}"`
  if [ -n "${POOLDISKS}" ]; then
    STANDBYCOUNT=`count_standby_disks "${POOLDISKS}"`
    print_log info \
      "${STANDBYCOUNT} disk(s) standby/sleep in pool(s):\n${POOLSCOPE}"
  else
    STANDBYCOUNT=0
    print_log info "No hard drives in pool(s):\n${POOLSCOPE}"
  fi

  if [ $STANDBYCOUNT -eq 0 ]; then
    print_log info "Running command for pool(s): ${POOLSCOPE}"
    run_action "${POOLSCOPE}"
  else
    print_log info "Skipping execution"
  fi

  if [ $PERPOOL = "no" ]; then break; fi
done

print_log debug "$0 finished."
