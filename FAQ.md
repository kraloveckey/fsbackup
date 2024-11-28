# FAQ: ANSWERS TO FREQUENTLY ASKED QUESTIONS

---
**How to maximize performance and reduce CPU load when encrypting a backup?**

When using encryption via gpg, it is recommended to set the value of `$prog_gzip=""` (i.e. disable archive compression), because gpg compresses data before encryption.compresses the data on its own before encryption. Using gzip will result in double compression and unnecessary load on CPU.

---
**There was a fear that fsbackup would eat up all the RAM if there were a lot of files.**

Not at all, one of the advantages of fsbackup is its very economical memory requirements. Memory requirements due to the use of the DBM library for storing hashes. By default, no more than 4 MB of RAM is used.

---
**How to increase performance and optimize memory allocation for fsbackup?** 

By default, only 4 MB of indexes are in memory, the rest is dumped to disk to disk. Backup performance can be increased by `_an_order_` by increasing the size of the cache for placing the table cache in memory by increasing the size of the cache for placing the hash table in memory. To do this, you need to change the values of the constant in `fsbackup.pl`: use constant `DB_DEF_CACHE_SIZE => cache_size_in_bytes`. The larger `DB_DEF_CACHE_SIZE` is the better.

---
**Why would you create your own system for backing up SQL tables when you have pg_dump and mysqldump?**

Neither of them can backup all bases, with a few missing. For example, backup of all databases on MySQL server, except for unnecessary gigabyte database of word forms for search engine. fsbackup relies on three pillars: a full backup of all databases, a backup of all databases, backup of only the databases specified in `backup_db_list`, and backup of all databases other than those specified in `backup_db_list`.

---
**How to most competently organize the backup of the server and a large amount of data?**

It is recommended to describe the backup of different parts of the file system in several configuration files.
For example, create the following configurations:

- `server_etc.conf` - describes the creation of a backup of the /etc directory and secret data using PGP encryption;
- `server_local.conf` - backup `/usr/local`, excluding temporary files;
- `server_sql.conf` - backup of the database;
- `server_home.conf` - backup of user directories (`/home` or `/usr/home`);
- `server_soft.conf` - backup of program archive (uncompressed).

> Вirectories for saving the backup in each configuration file should be different (`$cfg_remote_path`, `$cfg_local_path`). Saving several backups described by different `.conf` files in the same directory is not allowed.

---
**Why when $cfg_maximum_archive_size=100 variable is specified, uncompressed archive volumes appear to be slightly larger or smaller than 100 KB?**

The `$cfg_maximum_archive_size` variable takes into account the actual size of data in files plus the approximate size of file or directory attributes. The volume is terminated when the byte count is greater than the value specified in the configuration. For example, if the last file to be added is a 70Kb file and the size of the already compiled volume is 90Kb, then a 90Kb archive file will be created and a 70Kb file will be placed in the next volume. I.e. the system tries to create archive volumes with size slightly smaller than the size specified in the configuration file, except for the case of a file whose size is larger than the limit imposed on the size of the volume, in this case the entire file is placed in the archive volume, despite its large size. You can prevent the creation of archive volumes that do not fit on the drive used for backup by defining the maximum possible file size to be placed in the archive (`$cfg_size_limit`).

---
**How can I not archive files from such-and-such directories, and the directories themselves must be. For example, mail directories qmail, I set the mask: =!Maildir/cur/* as a result does not create in the archive catalogs cur in user profiles.**

It is enough to specify:

```shell
=!.*/Maildir/new/.*
```

Then all files inside `/Maildir/new/` will not be placed in the archive, and the directory will be added to the .dir file and will be recreated when restoring. In tar archive empty directories will not be placed in tar archive, only in .dir list.

---
**Why fsbackup does not backup directories if there are no files in them?**

Empty directories are simply not reflected in tar archive (as well as access rights to all directories). To store the full list of directories and access rights to them, `.dir` file is used, executed as a regular shell script. When restoring data from backup, it is necessary not only to open the `.tar` archive, but also to execute the `.dir` script.

---
**What can you recommend for backing up multiple servers ?**

- Allocate an old machine with a large disk for the backup server.
- Remove the backup server from the technical site, it is recommended to move it to another building (for example, to a remote office), in case of fire, robbery and other force majeure circumstances. Or periodically dump backups from the backup server onto portable media and take them home.
- I recommend to backup via FTP, if properly organized, no less secure than via SSH (using PGP encryption of backup and preventing the possibility of sniffing), and most importantly a faster and less resource-intensive way. 
- On each of the servers from which the backup will be performed, delimit the areas of the file system depending on the importance and volume of data. Each area should be described in a separate configuration file (see the questions above). For the most important data (e.g., password files, sensitive information representing trade secrets, etc.), use PGP encryption. For text data of large volume and not requiring frequent lifting from backup - use gzip compression. If the need for access to the data in the backup is great, you can limit yourself to a regular tar archive without compression.
- Configure ftp-server with access only to the hosts from which the backup is made (for example, via /etc/hosts.allow) and closed to the outside world.In the configuration of ftp-server forbid going outside the home directory (`/etc/ftpchroot`). Additionally, via crontab, write weekly backup duplication on the backup server to a neighboring disk (backup backup backup).

---
**Why does the backup script hangs or times out when creating a backup via FTP? FTP server (windows, nowell netware) at first glance works.**

Some FTP servers or firewall settings do not allow the default active FTP connection mode. Set `$cfg_remote_ftp_mode=1` in the configuration file.

---
**I cannot create a backup using pgp encryption. On the remote and local machine I created/exported/imported the keys as described in README on the local machine (from which the backup is merged) gpg --list-secret-key gives:**

```shell
pub  1024D/06E192F6 2024-08-20 kraloveckey
sub  1024g/C3750174 2024-08-20
```

And when I run fsbackup the picture is as follows:

```shell
PGP: enabled
......
gpg: backup: skipped: public key not found
gpg: [stdin]: encryption failed: public key not found
```

Apparently your key is named `kraloveckey`, and the configuration file (configuration directive `$cfg_pgp_userid`) specifies `backup` as the name of the public key. Another common mistake is forgetting to certify the public key (sign it, `gpg --sign-key`) on the machine where the backup is performed.

---
**How can I see the size of files and attributes placed in the archive? The archive is too big, I need to find out what file caused the size to grow so much.**

```shell
db_dump .hash
db_dump185 .hash
db2_dump .hash
```

---
**Why files of disks mounted via samba or netware are not placed in the archive.**

Try putting in `fsbackup.pl`, after `"use File::Find;"` the line:

```pl
$File::Find::dont_use_nlink = 1;
```

---
**Is it possible to realize through fsbackup archive of configuration files. I.e. back up not once a day, but let's say check once every 5 minutes and if there are changes make a backup reflecting in the file name the time of change, otherwise do not touch anything?**

Configure incremental backup mode and specify a known large number of iterations (for example, `$cfg_increment_level=99999`). If there are no changes from the last incremental backup, fsbackup will swear that there is nothing to back up and will not create unnecessary files.

---
**If you set backup by /, will all mounted file systems be backed up?** 

No, you need to list all monitoring points in the configuration.

---
**It is impossible to upload an archive (split into 800Mb volumes) with total size more than 2GB via FTP on one machine.**

Update the version of perl module `Net::FTP`.

---
**Why the file named /tmp/test/c:\trace_b.txt is not placed in the archive, it says: /bin/tar: tmp/test/c\:\trace_b.txt: Cannot stat: No such file or direct**

I'm afraid this is hard to deal with, `\t` can quite reasonably be seen as a tabulation. The list of files is passed to tar as it is, without escaping, and tar itself parsing the file with the list makes a decision about escaping when putting it into the archive (as you can see on the example of `":"` escaping). 

You should read the specification for the type of file system you are using, it is likely that the `\` character cannot be used in the file name.

---
**I want to exclude files located in the /etc/tinydns/log/main/ directory from the backup. I use the rule "f!/etc/tinydns/log/main/.*", but the files are still placed in the backup.**

`"f[~!]"` - mask for filename only, no directory, `"d[~!]"` - mask for directory only, `'=[~!]'` - mask for path, `'!'` - path exception (not a mask).

For example, there is a file `"/dir/file.txt"`. `"f"` sees only `'file.txt'`, `'d'` sees only `'/dir'`, and `'='` sees `'/dir/file.txt'`.

Examples of correct solutions:

```shell
!/etc/tinydns/log/main
=!/etc/tinydns/log/main/.*
```

---
**When creating an archive with PGP encryption from cron it creates an empty tar (0 bytes), why?**
 
I will describe to you for information (may be useful for FAQ) the solution to my problem with gpg archive encryption when running from cron. I noticed that in the root of the system there is a folder `.gnupg` (theoretically it should not be?) with empty pubring. I changed it to a reference to `~/.gnupg`, after that files started to be created normally (not empty). Conclusion: gpg run by cron from script cannot access root pubring, but accesses root (shared?).


---
**If I specify the parameter config_files="cfg_files1 cfg_files2", then backup cfg_files1 and the script hangs without performing any actions (backup cfg_files2 is not performed). If you separately write one by one these configuration files, everything is ok.**

In the script `create_backup.sh` between runs of fsbackup there is a delay of 10 minutes. Comment out the line `sleep 600` at the end of the file.

---
**Is it possible to exclude MySQL tables from backup by mask. The names are "tbl_01_2024" (by date).**


The `mysql_backup.sh` script uses the following line to determine if an exclusion has occurred string:

```shell
if [ "_$cur_ignore" = "_$cur_db:$cur_db_table" ]; then
```

You could try replacing it with e.g. 

```shell
grep_flag2=`echo "$cur_ignore"| grep -E "$cur_db:$cur_db_table"`.
if [ -n "$grep_flag2" ]; then
```

Set parameters as:

```shell
backup_db_list='base2:tbl_[0-9][0-9]_20[0-9][0-9]'
```

---
**Can fsbackup on FTP copy files not in one archive, but individually without archiving.**

Perhaps synchronization mode can be used for this, but it works via ssh, as it is essentially the same tar transfer, but only with disclosure on the remote side.

At first glance, I would make a copy of a single file, but on the remote side in cron hang a script that would monitor the appearance of new files or update existing ones and then unzip what you need.

If you just need to synchronize a group of files, it is better to use `rsync`. fsbackup for synchronization is suitable only in limited cases, when you need a particularly large flexibility in the choice of files or there is a need to connect your own copy handler or filter.

---
**Why doesn't fsbackup work with OpenBSD tar?**

For OpenBSD tar you need to use the `-l` switch instead of the `-T` switch. Replace all lines `$prog_tar -c -f - - -T` in `fsbackup.pl` with `$prog_tar -c -f - - -l`.

---
**After running the DBMS backup script, the database dump is left locally, i.e. it turns out that the dump directories should be additionally specified in the fsbackup.pl configuration for uploading to the remote backup server ? in the fsbackup.pl configuration for uploading to a remote backup server?**

Yes, of course. By default, dumps are put into the `fsbackup/sys_backup` directory, and are backed up together with fsbackup. The config should explicitly contain:

```shell
__DATA__
...
/usr/local/fsbackup/sys_backup
or 
/usr/local/fsbackup
```

---
**When running ./fsbackup.pl my_cfg gives an error: "my_cfg did not return a true value at ./fsbackup.pl line 78". What could be the problem?**

Look at the sample configuration, there is a `line "1;"` just before the `__DATA__` block. In your configuration file, it seems to be deleted.

---
**Is it possible to make MySQL backup with the rest of the data copied over the network, instead of being stored in the sys_backup directory?**

It is understood that the `sys_backup` directory should be included in the backup copied over the network, unless you have deleted the line from the example configuration file. I.e. backup of bases passes in two stages:

1. Put the dump of the base in `sys_backup`.
2. Copy the contents of `sys_backup` to the backup server.

In my experience, most often the latest version of the database dump is required on the DBMS server, so it is left on the local machine.

---
**Does fsbackup support ACLs and storing data about extended FS attributes?**

It supports them as much as tar installed on your system. All archiving operations are performed through a call to the tar program. Of the alternative tar implementations, star is the one that most definitely supports ACLs.

---
**How to save directories with excluded content in the archive?**

As an option, exclude not via `!/dir/`, but via a softer exclusion operator `d!/dir/.*`. This will take into account the excluded directories in the `.dir` file. Another option is to use `contrib/dir_sync`.