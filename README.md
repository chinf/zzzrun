# zzzrun
*Run a command only if a ZFS pool has no hard drives in a standby state.*

If all disks in the pool are active/idle then the command supplied will be executed. Use this command to avoid spinning up drives unnecessarily.

Derived from durandalTR's zstandby script at https://github.com/zfsonlinux/pkg-zfs/issues/54

Depends on the standard ZFS utilities and hdparm. Currently implementated in bash shell.

## Installation
```
wget https://github.com/chinf/zzzrun/archive/master.zip
unzip master.zip
cd zzzrun-master
make install
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
