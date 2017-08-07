#!/bin/sh

# zzzrun - Run command only if ZFS pool has no sleeping hard drives
# Copyright (C) 2017 Francis Chin <dev@fchin.com>
#
# Repository: https://github.com/chinf/zzzrun
#
# Based on durandalTR's zstandby script
# (https://github.com/zfsonlinux/pkg-zfs/issues/54) and also
# zfs-auto-snapshot (https://github.com/zfsonlinux/zfs-auto-snapshot)
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

VERBOSITY=0
readonly SUBSTOKEN="@zzzrun-pool"
readonly DEFAULTCACHE="/var/cache/zzzrun-cache"

# Set environment
. /etc/profile.d/zzzrun.sh

print_log() { # level, message
  local LEVEL="$1"
  shift 1
  case $LEVEL in
    (err*) echo "Error: $*" >&2 ;;
    (war*) if [ $VERBOSITY -gt 0 ]; then echo "Warning: $*" >&2; fi ;;
    (inf*) if [ $VERBOSITY -gt 0 ]; then echo "$*" >&2; fi ;;
    (deb*) if [ $VERBOSITY -gt 1 ]; then echo "Debug: $*" >&2; fi ;;
  esac
}

#
# Options
#
print_usage() {
  echo "Usage:
  $(basename $0) [options] [-i POOL]... [-x POOL]... COMMAND [${SUBSTOKEN}] ...

Run a command only if there are no hard drives in standby or sleep
power modes in the ZFS pools specified.

  -p           Check each pool separately and run COMMAND once per pool.
               If using this option, use token ${SUBSTOKEN} (see COMMAND
               parameter) to update COMMAND for each run.

  -u           Force an update of any cached device information.

  -v           Verbose mode.  Report warnings and information.  By default
               only errors are reported.

  -vv          Very verbose.  Report debugging messages.

  -i POOL      Include a pool.  Repeat to specify multiple pools.  Any
               that are unavailable will be ignored.  Omit this option to
               include all pools.

  -x POOL      Exclude a pool.  Repeat to specify multiple pools.

  COMMAND      Command to execute.  Use token ${SUBSTOKEN} in the command
               arguments to make $(basename $0) insert the pool scope when
               running the command.  If using option -p, this will be the
               name of each pool as $(basename $0) iterates through them,
               otherwise this will be a list of all pools.
" >&2
exit 2
}

RUNMODE="single"
CACHEFILE="${ZZZRUNCACHE:-$DEFAULTCACHE}"
while getopts ":puvi:x:" OPT; do
  case "${OPT}" in
    p) RUNMODE="per pool" ;;
    u) UPDATECACHE="yes" ;;
    v) VERBOSITY=`expr $VERBOSITY + 1` ;;
    i)
      if [ -n "${OPTARG}" ]; then
        POOLARGS="${POOLARGS} ${OPTARG}"
      else
        print_usage
      fi
      ;;
    x)
      if [ -n "${OPTARG}" ]; then
        POOLEXCLUDES="${POOLEXCLUDES} ${OPTARG}"
      else
        print_usage
      fi
      ;;
    *) print_usage ;;
  esac
done
shift $((OPTIND-1))

if [ -z "$*" ]; then print_usage; fi
COMMAND="$*"
print_log debug "Parsed COMMAND: $COMMAND"

if [ $(id -u) -ne 0 ]; then
  echo "Please run $(basename $0) as root"
  exit 2
fi

#
# Configuration functions
#
get_pool_hdds() { # pool
  local POOL; local VDEVS; local HDDS
  POOL="$1"
  print_log debug "Finding hard drives in pool: ${POOL}"

  # Parse zpool status to get all devices used by the specified pool(s)
  VDEVS=$(env LC_ALL=C zpool status -L ${POOL} \
    | awk '/^\t +.+ +[A-Z]+ +[0-9]+ +[0-9]+ +[0-9]+/ {
      printf ("/dev/%s ", $1)
    }')
  print_log debug "VDEVS: ${VDEVS}"

  # Filter pool device list down to just hard drives
  # Using lsblk to lookup parent device (in case dev is a partition
  # or luks container) and rotational parameter
  HDDS=$(env LC_ALL=C echo "${VDEVS}" \
    | xargs lsblk -lso name,rota,type 2>/dev/null \
    | awk '/1 disk$/ { printf ("%s ", $1) }' \
    | sort -u)
  print_log debug "HDDS: ${HDDS}"

  echo -n "${HDDS}"
}

# Temp file caches hard drive configuration from the available pools
# to avoid calling ZFS utilities which can wake sleeping drives.
read_cache() {
  print_log info "Reading cache: ${CACHEFILE}"

  if [ ! -f "${CACHEFILE}" ]; then
    print_log error "${CACHEFILE} is not a file (or symlink to one)"
    exit 1
  fi
  if [ ! -r "${CACHEFILE}" ]; then
    print_log error "${CACHEFILE} is not readable"
    exit 1
  fi
  if [ ! -s "${CACHEFILE}" ]; then
    print_log error "${CACHEFILE} is empty"
    exit 1
  fi

  # ZFS pool name must be alphanumeric in addition to the special
  # characters underscore (_), hyphen (-), period (.) and must begin
  # with a letter.  Reserved names cannot be used as pool names
  # (e.g. log) but this will not be vetted by this script.
  # Ref: https://docs.oracle.com/cd/E26505_01/html/E37384/gbcpt.html
  ZPOOLS=$(env LC_ALL=C awk '{
    if ( $1 ~ /^[a-zA-Z][a-zA-Z0-9_\-\.]+:$/ ) {
      sub(":", "", $1)
      if ( NR > 1 )
        printf (" %s", $1)
      else
        printf ("%s", $1)
    } else exit 1
  }' "${CACHEFILE}")
  if [ $? -ne 0 ]; then
    print_log error "Cache ${CACHEFILE} contains an invalid pool name"
    exit 1
  fi

  # Block device paths must be alphanumeric in addition to the special
  # characters underscore (_), hyphen (-), slash (/) and must begin
  # with a letter.
  # Ref: https://github.com/torvalds/linux/blob/master/Documentation/admin-guide/devices.txt
  HDDARRAY=$(env LC_ALL=C awk '{
    printf ("%s ", $1)
    for ( i=2; i <= NF; i++ )
      if ( $i ~ /^[a-zA-Z][a-zA-Z0-9_\-\/]+$/ )
        printf ("%s ", $i)
      else
        exit 1
    printf ("\n")
  }' "${CACHEFILE}")
  if [ $? -ne 0 ]; then
    print_log error "Cache ${CACHEFILE} contains an invalid block device name"
    exit 1
  fi
}

get_new_config() {
  print_log debug "Getting new ZFS pool data"

  ZPOOLS=$(zpool list -H -o name)
  if [ -z "${ZPOOLS}" ]; then
    print_log warn "No pools are available on this system"
    exit 3
  fi

  HDDARRAY=
  for ZPOOL in $ZPOOLS; do
    HDDARRAY="${HDDARRAY}${ZPOOL}: `get_pool_hdds "${ZPOOL}"`\n"
  done
  print_log debug "HDDARRAY: ${HDDARRAY}"
}

write_cache() {
  print_log info "Writing cache: ${CACHEFILE}"

  touch "${CACHEFILE}"
  if [ -w "${CACHEFILE}" ]; then
    echo -n "${HDDARRAY}" > "${CACHEFILE}"
  else
    print_log warning "Unable to write to ${CACHEFILE}"
  fi
}

configure() {
  if ( [ -e "${CACHEFILE}" ] && [ -z "${UPDATECACHE}" ] ); then
    read_cache
  else
    get_new_config
    write_cache
  fi

  if [ -z "${POOLARGS}" ]; then POOLARGS="${ZPOOLS}"; fi

  for POOLARG in $POOLARGS; do
    for POOLEXCLUDE in $POOLEXCLUDES; do
      if [ "${POOLARG}" = "${POOLEXCLUDE}" ]; then 
        print_log debug "Excluding pool: ${POOLARG}"
        continue 2
      fi
    done

    for ZPOOL in $ZPOOLS; do
      if [ "${POOLARG}" = "${ZPOOL}" ]; then
        POOLS="${POOLS} ${POOLARG}"
        break
      fi
    done
  done

  if [ -z "${POOLS}" ]; then
    print_log warn "None of the pools specified are available"
    if [ -z "${UPDATECACHE}" ]; then
      print_log info "Try using -u option to refresh cache"
    fi
    print_log debug "POOLARGS: ${POOLARGS}"
    print_log debug "POOLEXCLUDES: ${POOLEXCLUDES}"
    print_log debug "ZPOOLS: ${ZPOOLS}"
    exit 3
  fi

  if [ "${RUNMODE}" = "per pool" ]; then
    TOKENS=$(echo "${COMMAND}" | grep -cE "${SUBSTOKEN}")
    if [ "${TOKENS}" -eq 0 ]; then
      print_log warn "Running per-pool but no substitution token found in command specified"
      print_log info "Command will be run without supplying pool names"
    fi
  fi
  print_log debug "Run mode: ${RUNMODE}"
  print_log info "Pools available to process: ${POOLS}"
}

#
# Main functions
#
get_disks() { # pool list
  local SCOPE; local POOL; local DEV; local DEVS
  SCOPE="$1"
  print_log debug "Getting devices for pool(s): ${SCOPE}"

  for POOL in $SCOPE; do
    DEV=$(echo "${HDDARRAY}" \
      | awk -v pool="${POOL}" '$1 == pool":" {
        for ( i=2; i <= NF; i++ )
          printf ("/dev/%s ", $i)
      }')
    DEVS="${DEVS}${DEV}"
  done
  print_log debug "DEVS: ${DEVS}"

  echo -n "${DEVS}"
}

count_standby_disks() { # hdds
  local DISKS; local DRIVESTATES; local UNKNOWNS
  DISKS="$1"
  print_log debug "Counting disks in standby or sleeping states"

  DRIVESTATES=$(echo "${DISKS}" | xargs hdparm -C)
  print_log debug "DRIVESTATES:\n${DRIVESTATES}"

  UNKNOWNS=$(echo "${DRIVESTATES}" | grep -cE 'unknown')
  if [ "${UNKNOWNS}" -gt 0 ]; then
    print_log warn "Unable to read status for at least one drive"
  fi

  echo "${DRIVESTATES}" | grep -cE 'standby|sleeping'
}

run_action() { # pool list
  local SCOPE; local CMD
  SCOPE="$1"

  CMD=$(echo "${COMMAND}" | sed "s/${SUBSTOKEN}/${SCOPE}/g")
  print_log debug "Executing command '${CMD}':"

  $CMD >&2
}

#
# main()
#
configure

for POOL in $POOLS; do
  if [ "${RUNMODE}" = "single" ]; then
    POOLSCOPE="${POOLS}"
  else
    POOLSCOPE="${POOL}"
  fi

  DISKS=$(get_disks "${POOLSCOPE}")
  if [ -n "${DISKS}" ]; then
    STANDBYCOUNT=$(count_standby_disks "${DISKS}")
    print_log info \
      "${STANDBYCOUNT} disk(s) standby/sleep in pool(s): ${POOLSCOPE}"
  else
    STANDBYCOUNT=0
    print_log info "No hard drives in pool(s): ${POOLSCOPE}"
  fi

  if [ "${STANDBYCOUNT}" -eq 0 ]; then
    print_log info "Running command for pool(s): ${POOLSCOPE}"
    run_action "${POOLSCOPE}"
  else
    print_log info "Skipping execution for pool(s): ${POOLSCOPE}"
  fi

  if [ "${RUNMODE}" = "single" ]; then break; fi
done

print_log debug "$(basename $0) finished."
