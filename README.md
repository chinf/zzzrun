# zzzrun
*Run a command only if a ZFS pool has no hard drives in a standby state.*

If all disks in the pool are active/idle then the command supplied will be executed. Use this utility to avoid spinning up drives unnecessarily.

Based on [durandalTR's zstandby script](https://github.com/zfsonlinux/pkg-zfs/issues/54) and [zfs-auto-snapshot](https://github.com/zfsonlinux/zfs-auto-snapshot).

Depends on the standard ZFS utilities and hdparm.  Implemented in and tested with a POSIX-compliant shell.  Uses a systemd unit to reset the device cache upon system boot up.

## Installation
```
wget https://github.com/chinf/zzzrun/archive/master.zip
unzip master.zip
cd zzzrun-master
sudo make install
```
This will install cron entries for zzzrun under:

* /etc/cron.d/
* /etc/cron.hourly/
* /etc/cron.daily/
* /etc/cron.weekly/
* /etc/cron.monthly/

The default cron configuration calls zfs-auto-snapshot with default values.
If you wish to use this with zfs-auto-snapshot, you must comment out or otherwise disable zfs-auto-snapshot's own cron files in the same directories.

If you don't wish to use this, simply remove or customise the zzzrun cron files for your own needs.

Installation will also add an environment configuration file under `/etc/profile.d/zzzrun.sh`.

## Device Cache
Device information is cached to avoid unnecessary calls to ZFS utilities which can cause sleeping drives to wake up.  The default location for the device information cache is `/var/cache/zzzrun-cache`.

Ideally this should be on a device that is not subject to spin-down.  To change this location, edit the export variable ZZZRUNCACHE in `/etc/profile.d/zzzrun.sh`

## Limitations
There is currently no mechanism in place to detect pool changes (e.g. from `zpool import` or `zpool export`) to automatically invalidate the cache, so to avoid errors in these situations, run `zzzrun -u :` afterwards.

Hard drives that are connected to the host via USB may report their power state incorrectly to `hdparm -C`.
USB drives that appear to hdparm to be in standby when they are not will cause this utility to skip runnning the command for otherwise fully active pools.
In some cases `hdparm -C` may cause USB drives in standby to wake up, which defeats the purpose of this utility.

A possible workaround for both of these issues would be to not use zzzrun on affected pool(s) and instead run the command manually as required.

If `hdparm -C` returns "unknown" for a drive, zzzrun will interpret this as active/idle and so err in favour of running the command.
