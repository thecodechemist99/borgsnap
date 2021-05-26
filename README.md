# borgsnap - Backups using ZFS snapshots, borg, and (optionally) rsync.net

This fork adds:

* COMPRESS - variable to specify Borg compression method
* RECURSIVE - for recursive ZFS snapshot support
* BASEDIR - set cache/config folders
* LOCALSKIP - Ignore LOCAL path, create/purge remote backups only
* REMOTE_BORG_PATH - Configure remote borg command.  Defaults to borg1.
* PRE_SCRIPT and POST_SCRIPT - Run a script before or after taking ZFS snap

**The configuration file must include all options present in sample.conf, even
if the option has no value specified.**

*If RECURSIVE=true, borgsnap will create recursive ZFS snapshots for all
nominated FS filesystems.  Each child filesystem snapshot will be mounted
underneath the snapshot mount of the parent filesystem.  This allows borgsnap
to backup the parent filesystem and all child filesystems in a single borgbackup
repository.*

*COMPRESS default in sample.conf is zstd*

_BASEDIR will configure BORG_BASE_DIR option, this will move the cache/config
folders.  Added for unRAID where root home folder is not persistent.  If unset,
BORG_BASE_DIR will default to $HOME_

_CACHEMODE will configure how Borgbackup detects changed files
https://borgbackup.readthedocs.io/en/stable/usage/create.html_

_LOCALSKIP will skip LOCAL path for all operations and only perform backups
and purge operations on REMOTE target._

_REMOTE_BORG_PATH defaults to "borg1" for rsync.net.  Set this to "borg" for
normal remote borg destinations._ 

_PRE_SCRIPT will run before taking a snapshot for each dataset.  The example
provided demonstrates how to run a command only for a specific dataset.  Specify
the full path to the script._

_POST_SCRIPT will run after taking a snapshot for each dataset.  The example
provided demonstrates how to run a command only for a specific dataset.  Specify
the full path to the script._

*set -e was removed, this fork of borgsnap will continue running if a command
fails*

This is a simple script for doing automated daily backups of ZFS filesystems.
It uses ZFS snapshots, but could easily be adaptable to other filesystems,
including those without snapshots.

[Borg](https://www.borgbackup.org/) has excellent deduplication, so unchanged
blocks are only stored once. Borg backups are encrypted and compressed
(borgsnap uses lz4).

Unlike tools such as Duplicity, borg uses an incremental-forever model so you
never have to make a full backup more than once. This is really great when
sending full offsite backups might take multiple days to upload.

Borgsnap has optional integration with rsync.net for offsite backups. rsync.net
offers a [cheap plan catering to borg](http://www.rsync.net/products/attic.html).
As rsync.net charges nothing in transfer fees nor penalty fees for early
deletion, it's a very appealing option that is cheaper than other cloud storage
providers such as AWS S3 or Google Cloud Storage once you factor in transfer
costs and fees for deleting data.

Borgsnap automatically purges snapshots and old borg backups (both locally
and remotely) based on retention settings given in the configuration.
There is also the possibility to backup an already existing snapshot.

This assumes borg version 1.0 or later.

Finally, these things are probably obvious, but: Make sure your local backups
are on a different physical drive than the data you are backing up and don't
forget to do remote backups, because a local backup isn't disaster proofing
your data.

## borgsnap installation
```
git clone git@github.com:jortan/borgsnap.git
```

generate key:
```
pwgen 128 1 > /path/to/my/super/secret/myhost.key
```

adapt sample.conf
```
FS="zroot/root zroot/home zdata/data"
LOCAL="/backup/borg"
BASEDIR=""
LOCAL_READABLE_BY_OTHERS=false
LOCALSKIP=false
RECURSIVE=true
COMPRESS=zstd
CACHEMODE="mtime,size"
REMOTE=""
REMOTE_BORG_COMMAND=
PASS="/path/to/my/super/secret/myhost.key"
MONTH_KEEP=1
WEEK_KEEP=4
DAY_KEEP=7
PRE_SCRIPT=
POST_SCRIPT=
```

how to:
```
usage: borgsnap <command> <config_file> [<args>]

commands:
    run             Run backup lifecycle.
                    usage: borgsnap run <config_file>

    snap            Run backup for specific snapshot.
                    usage: borgsnap snap <config_file> <snapshot-name>
					
    tidy            Unmount and remove snapshots/local backups for today
                    usage: borgsnap tidy <config_file>
					
                    Added for test/dev purposes, may not work as intended!

                    Note: this will unmount all snapshots mounted by borgsnap
                    including other running instances.	
```

## how it works

Borgsnap is pretty simple, it has the following basic flow:

+ Read configuration file and encryption key file
+ Validate output directory exists and a few other basics
+ For each ZFS filesystem do the following steps:
  + Initialize borg repositories if local one doesn't exist
  + Take a ZFS snapshot of the filesystem (recursively if enabled)
  + Run borg for the local output if configured
  + Run borg for the rsync.net output if configured
  + Delete old ZFS snapshots (recursively if enabled)
  + Prune local borg if configured and needed
  + Prune rsync.net borg if configured and needed

That's it!

If things fail, it is not currently re-entrant. For example, if a ZFS snapshot
already exists for the day, the script will fail\*.  This could use a bit of
battle hardening, but has been working well for me for several months already.

\* If the script does fail, you can use "tidy" option.  This will make best
effort to remove any mountpoints, delete today's zfs snapshots and borg
archives, allowing borgsnap to be run again that day.  This was added mostly
for test/dev purposes and may not work as intended!


## Restoring files

Borgsnap doesn't help with restoring files, it just backs them up. Restorations
are done directly from borg (or ZFS snapshots if it's a simple file deletion to
be restored). A backup that can't be restored from is useless, so you need to
test your backups regularly.

For Borgsnap, there are three ways to restore, depending on why you need to:

+ Use the local ZFS snapshot (magic .zfs directory on each ZFS filesystem).
This is the way to go if you simply deleted a file and there is no hardware
failure.

+ Use the local borg repository. If there is data loss on the ZFS filesystem,
but the backup drive is still good, use "borg mount" to mount up the directory
and restore files. See example below.

+ Use the remote borg repository. As with a local repository, use "borg mount"
to restore files from rsync.net.

The borgwrapper script in this repository can be used to set BORG_PASSPHRASE
from the borgsnap configuration file, making this slightly easier.

### Restoration Examples

Note: Instead of setting BORG_PASSPHRASE as done here, with an exported
environment variable, you can paste it in interactively.

Also note that borgsnap does backups directly from the ZFS snapshot, using
the magic .zfs mount point, hence the borg snapshot preserves this directory
structure. Don't worry, borg is still deduplicating files, even though the
directory changes each time. Also, don't panic if you do "ls /mnt" and don't
see anything - try "ls -a /mnt" or you might miss seeing that .zfs directory.

```
$ sudo -i

# export BORG_PASSPHRASE=$(</path/to/my/super/secret/myhost.key)

# borg list /backup/borg/zroot/root
week-20171008                        Sun, 2017-10-08 01:07:29
day-20171009                         Mon, 2017-10-09 01:07:54
day-20171010                         Tue, 2017-10-10 01:07:48
day-20171011                         Wed, 2017-10-11 01:07:57

# borg mount /backup/borg/zroot/root::day-20171011 /mnt

# ls /mnt/.zfs/snapshot/day-20171011/
backup	bin   etc  home	 lib64  proc  root  sbin  tmp  var

# borg umount /mnt
```

Restoring from rsync.net is nearly the same, just a change in the path, and
passing --remote-path=borg1 since we are using a modern borg version:

```
# borg mount --remote-path=borg1 XXXX@YYYY.rsync.net:myhost/zroot/root::day-20171011 /mnt
```

I used "borg mount" above, where we would, simply "cp" the files out. See
the borg manpages to read about other restoration options, such as
"borg extract".

And finally, using the borgwrapper script, which will set BORG_PASSPHRASE for
you:
```
# borgwrapper /path/to/my/borgsnap.conf list /backup/borg/zroot/root
[...]
```
