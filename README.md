# FSBackup

> FSBackup - file system backup and synchronization utility.

---

- [FSBackup](#fsbackup)
	- [Purpose](#purpose)
	- [Packages](#packages)
	- [Performed functions](#performed-functions)
	- [Installation](#installation)
	- [Configuration](#configuration)
	- [Configuration files](#configuration-files)
	- [Data recovery](#data-recovery)
	- [Backup types](#backup-types)
	- [Storage types for backup archive](#storage-types-for-backup-archive)
	- [Backup encryption](#backup-encryption)
	- [Notes](#notes)
	- [Postfix](#postfix)

---

## Purpose

The `fsbackup` system was created to provide backup of servers of various sizes to a dedicated backup server. 

The advantages of the backup method on a dedicated server, using `fsbackup`, are:

- high performance;
- reliability (possibility of parallel storage of several backups for different moments of time); 
- security (using PGP encryption of backups before writing them to the backup server);
- autonomy (once the system is configured, backups will be performed automatically, no need to maintain the streamer), 
- the ability to save only changed data from the last backup, without the need to spend on copying unchanged information;
- ease of configuration and installation (as a rule, the system is able to function immediately after running the installation script)
- ease of recovery (open format for storing backups (tar) allows data recovery without using the included recovery utilities).
- flexibility of specifying masks for placing files and directories in the archive;
- support for backing up databases stored in MySQL and PostgreSQL.

`fsbackup` can create both a full server image and backup copies of the main subsystems, excluding the operating system.

Unlike many automatic backup systems, `fsbackup` uses a flexible masking system (using regex) to decide whether to place files in the backup.

---

## Packages

1. `create_backup.sh` - Script to periodically run the entire backup subsystem from crontab.

2. `install.pl` - Script for installing the program and all missing Perl modules.

3. `fsbackup.pl` - Main script for backup and synchronization.

4. `cfg_example` - Sample configuration file and documentation on all configuration directives. 

5. `cache/` - Directory image for placing temporary hashes. 

6. `sys_backup/` - Directory image for placing backups created by `sysbackup.sh`. 

7. `modules/` - Perl modules that are required for `fsbackup.pl` to function.

8. `scripts/` - Directory with auxiliary scripts.

9. `scripts/mysql_backup.sh` and `scripts/pgsql_backup.sh` - Scripts for creating full and partial backups of a database stored in PostgreSQL or MySQL. Supported modes of operation:

- full backup of all databases and structures;
- full backup of all database structures + backup of data in selected databases/tables;
- full backup of all databases' structures + data backup in all databases except for favorite databases/tables;

10. `scripts/sysbackup.sh` - Script to save a list of all packages installed on the system.

11. `scripts/sysrestore.sh` - Script to automatically install all packages whose list was saved by `sysbackup.sh` script in a freshly installed system.

12. `scripts/fsrestore.sh` - Script for restoring data from an incremental backup.

---

## Performed functions

1. Two methods of checksum calculation:

- `timesize`: by attributes (date, time, size, permissions...);
- `md5`: by file contents.

2. Four types of backup:

- `backup`: incremental backup to archive (i.e. only files that have changed since the last backup are copied).
- `full_backup`: full backup to archive, without hash (i.e. all files are always copied).
- `sync`: synchronize the tree.
- `hash`: hash generation only, without putting files in the archive (can be used to determine which files have been modified).

3. Three types of backup storage:

- `local`: storing the backup in the local file system.
- `remote_ssh`: copy the backup to a remote machine using SSH
- `remote_ftp`: copy the backup to a remote machine using FTP.

4. Eight built-in operators (you can use regex) to describe files to be placed in the backup (or ignored for being placed in the backup):

- `/dir[/file]`: path to the file/directory to be backed up.
- `!/dir[/file]`: path negation, not to be placed in backup (not a mask, but a real path).
- `#`: comment
- `=~`: mask for file or directory, not absolute path. First or second character.
- `f~`: mask for a file. First or second character.
- `d~`: mask for a directory. The first or second character.
- `=!`: "NOT" a mask for a file or directory, not an absolute path. First or second character.
- `f!`: "NOT" mask for a file. First or second character.
- `d!`: "NOT" mask for a directory. The first or second character.

5. Ability to encrypt the backup using PGP.

6. Flexible setting of incrementally level. For example, at = 7 - 6 times only changes will be placed, at 7 times the backup will be merged into one file.

7. Script for saving a list of all installed packages for FreeBSD and Linux.

8. Scripts for creating a full and partial backup of a database stored in PostgreSQL or MySQL.

---

## Installation

To install the program, just run the `./install.pl` script. The program will be automatically copied to the directory specified by the `--prefix` directive, by default the installation is performed in the `/usr/local/fsbackup` directory.

After installation, just rename and edit the configuration file `cfg_example`, following the instructions inside `cfg_example`. Then, edit the startup script `create_backup`.sh, if necessary change the path to the backup storage and the name of the list of configuration files used. Activate periodic startup of the backup subsystem in crontab:

```shell
18 4 * * * /usr/local/fsbackup/create_backup.sh | mail -aFrom:"FROM NAME<from_example@example.com>" -s "Backup Report: `hostname`, `hostname -I | awk '{print $1}'`" to_example@example.com
```

When using MySQL Server or system backup, edit the scripts in the `./scripts` directory (`mysql_backup.sh`, `pgsql_backup.sh`, `sysbackup.sh`).

For example:

```shell
$ sudo -i
$ ./install.pl 
$ cd /usr/local/fsbackup
$ vim cfg_example
$ mv cfg_example server_backup.conf
$ vim create_backup.sh
$ crontab -e
$ cd scripts
$ vim sysbackup.sh
$ vim pgsql_backup.sh
$ exit
```

---

## Configuration

1. Log in system as root.

2. `git clone https://github.com/kraloveckey/fsbackup.git`

3. `cd fsbackup`

4. `./install.pl`

If you want to install fsbackup in other directory (`/usr/local/fsbackup/` by default), you may owerride it by `--prefix` directive, for example: `./install.pl --prefix /usr/fsbackup/`

You may answer by default on all script questions (simply `Enter`). You will see `Installation complete` message after install done.

5. Now, you have fsbackup installed fully in `/usr/local/fsbackup` (or other `--prefix`) directory. It consist scripts, config example and docs in some directories.

Main script is `create_backup.sh`. It must be run periodical via cron, or manually, if necessary. In this one, you may determine one or more config files. Every config file will describe one set of backups. First, save original files:

```shell
cd /usr/local/fsbackup/
cp -v create_backup.sh create_backup.sh.orig
cp -v cfg_example my_backup1.cfg
```

6. Edit them: `vim create_backup.sh`

In `create_backup.sh`, we must change only `config_files` parameter (`row 33`). Set it to:

```shell
config_files="my_backup1.cfg"
```

And examine others:

```shell
backup_path="/usr/local/fsbackup" - leave untouched, if you don't use --prefix option for install.pl
backup_mysql=0
backup_pgsql=0
backup_sqlite=0
backup_sys=0
```

If we don't want to backup databases and sysconfigs. Otherwise, we must edit `scripts/*` too. Save it end exit from editor.

7. `vim my_backup1.cfg`

```shell
row 8: $cfg_backup_name - simply tag of backup. Hostname by default. May contain [a-z,A-Z,0-9,_] only.

row 15: $cfg_cache_dir - backup cache directory. If possible, leave "/usr/local/fsbackup/cache"

rows 28-33: $prog_* - may be checked, but usually true for RH.
```

---

## Configuration files

For a detailed description of all configuration file parameters, see the `cfg_example` file.

> When describing directories for backup, you cannot specify the path to a symbolic link, only the full path to the real directory. For example, if `/home` is specified and it is a symbolic link to `/usr/home`, the backup will contain data about the symbolic link, but not the contents of the directory.

It is recommended that you describe the backup of different parts of the file system in several configuration files. For example, I use the following multiple configuration files:

- `server_etc.conf`: describes how to backup the `/etc` directory and secret data using PGP encryption;
- `server_local.conf`: backup `/usr/local`, except for temporary files, backup the database.
- `server_home.conf`: backup user directories (`/home` or `/usr/home`)

> Directories for saving backup in each configuration file must be different (`$cfg_remote_path`, `$cfg_local_path`), saving several backups described by different `.conf` files in the same directory is not allowed.

---

## Data recovery

A full backup can be restored in a short period of time without using additional utilities included with fsbackup. For example, if the backup archive is saved in the `/mnt/full_backup` directory, all you need to do for a full restore is to type:

```shell
cd /
tar xzf /mnt/full_backup/full_backup.tar.gz
sh /mnt/full_backup/full_backup.dir
```

For full data recovery from an incremental backup the script `scripts/fsrestore.sh` can be used, just edit the paths inside the script and run it.

In case of a partial backup of the file system, without backup of the operating system files, the script `scripts/sysrestore.sh` will help to restore the original set of packages installed at the moment of backup (`scripts/sysbackup.sh` must be allowed to run in create_backup.sh). After installing the OS, the script will automatically install missing packages for FreeBSD and Linux.

When backing up data from PostgreSQL or MySQL Server, the recovery is done with the commands: `psql -d template1 -f sqlbackupfile` or `mysql < sqlbackupfile`.

In this way we can give a typical process of complete system recovery:

- basic OS installation (without additional packages);
- mounting the disk with the backup;
- editing paths and running `scripts/sysrestore.sh` to install the required packages;
- editing paths and running `scripts/fsrestore.sh`;
- start MySQL Server and restore databases.

File assignment for incremental backups (for non-incremental backups, the format is `name.ext`):

- `name-time-volume.tar.gz`: backup archive (`backup_name-YYYYY.MM.DD.HH.MM.SS-volume_number.tar.gz`);
- `name-time.del`: list of files deleted since the previous backup;
- `name-time.hash`: hash table with checksums;
- `name-time.list`: list of files in the archive;
- `name-time.dir`: commands to restore permissions and empty directories.

For restoring data from the backup, we can use script:

```shell
/usr/local/fsbackup/scripts/fsrestore.sh
```

May be you want to save this file separately, simply in backup dir, for more quickly restoring:

```shell
cp -v /usr/local/fsbackup/scripts/fsrestore.sh /usr/local/fsbackup/archive/
```

1. Make some changes:

```shell
vim /usr/local/fsbackup/scripts/fsrestore.sh
```

There are 3 options here:

- `backup_name`: tag of data for extract (if you have more than 1 config for fsbackup, you can restore it separately)

- `backup_path` - in our fsbackup config we have `/usr/local/fsbackup/archive`, but may be after crash you will want mount dedicated HDD to other point.

- `restore_path` - this dir will be `root point` for the extracted data.

2. Do restoring process:

```shell
$ /usr/local/fsbackup/scripts/fsrestore.sh

Removing deleted files for router_ap01-2005.09.10.02.23.00-0.tar.gz...
Restoring router_ap01-2005.09.10.02.23.00-0.tar.gz...
Fixing directory permissions for router_ap01-2005.09.10.02.23.00-0.tar.gz...
mkdir: cannot create directory `./usr/local/fsbackup': File exists
mkdir: cannot create directory `./usr/local/fsbackup/scripts': File exists
mkdir: cannot create directory `./root': File exists
...
```

> Don't worry about `mkdir: cannot create directory` warnings: it simple try to create already created dirs in second pass of restoring.

`fsrestore.sh` will create all your data from base and all increments of archive. Check it!

---

## Backup types

Backup type in the configuration file is defined by the `$cfg_backup_style` parameter:

1. `backup` - incremental backup to archive. Only files that have changed since the last backup are copied, the incremental level is set by the `$cfg_increment_level` parameter, the parameter defines after what number of iterations the files with incremental copies will be merged into one file. For example, at `$cfg_increment_level = 7 - 6` times only changes will be placed, at `7` times the backup will be merged into one file. `0` - as many times as you want, without merging. Advantages - the ability to track changes (and restore data) at any time since the first iteration, only changed and new data are copied to the archive, which saves traffic and disk space. Suitable for daily backup of dynamically changing or critical to loss of information.

2. `full_backup` - full backup to archive, without hash. The backup always includes all files marked in the configuration file for backup). On the server where the backup is saved it is recommended to perform secondary backup, for example, in crontab once a week to duplicate the backup to another directory. Disadvantages - huge traffic for backup copying over the network and high requirements to the backup storage volume. Advantage - saves CPU resources and memory for hash creation and maintenance. Perfect for backing up low-powered machines with limited resources or when the data being backed up is static (for example, backing up remote routers once a month).

3. `sync` - tree synchronization (only for ssh or local storage type). Almost the same as `full_backup` or backup (depending on the `-c` switch when starting `fsbackup.pl`), except that the copy is not stored in the archive, and the file system area marked for backup is completely recreated in the specified directory on the backup server. It is intended for parallel storage (tree synchronization) of source code, web-server content, synchronization of projects from the developer's working machine to the server, etc. 

4. `hash` - only hash generation, without placing files in the archive (option `-h`). It can be used to mark the placement of files in the backup without physically moving them, to track changes in the file system to detect file substitution by intruders, etc.


The `fsbackup.pl` script supports a number of command-line keys:

```shell
fsbackup.pl [-n|-f|-h|-c] configuration file
    -n - create a new archive regardless of the hash state.
    -f - full_backup - full backup to archive, without hash.
    -h - hash - hash generation only, without putting files into the archive.
    -c - clean - clean the storage with incremental backup and create a new backup.
```

---

## Storage types for backup archive

The definition of storage type for backup is defined in the configuration file by the `$cfg_type` variable. Three types of storage are supported: `local`, `remote_ssh` and `remote_ftp`.

1. `local` - saving the backup in the local file system. Configuration:

```shell
$cfg_type="local";
$cfg_local_path="/var/backup"; # Vault path.
```
2. `remote_ssh` - saving the backup on a remote computer, the data is transmitted through an encrypted connection organized using SSH. An ssh client must be installed on the system from which the backup is made, and an ssh server must be installed on the remote system. The remote_ssh method is the most secure, but also resource-intensive. It is necessary to configure access of the backup client to the server using encrypted keys without password. `Example`: **local machine** - the machine from which the backup will be performed and on which we will run the script `fsbackup.pl`. The **remote machine** is the machine on which the backup files will be copied. Run the `ssh-keygen` program on the local machine, accept the default values for all questions asked (leave the passphrase field empty). Next, run the program `ssh-copy-id user@remotehost`, where `user` is the user of the remote machine, `remotehost` is the address of the remote machine, (or manually, on the remote machine in the directory `~/.ssh`, create a file `authorized_keys`, where we copy the contents of the file `identity.pub` from the local machine). To increase security in the `~/.ssh/authorized_keys` file on the remote machine, add the line `from="localhost"` before the key (separated by a space), where `localhost` is the address of the local machine (`from="localhost" 1024 23 1343.....`). Configuration:

```shell
$cfg_type="remote_ssh";
$cfg_remote_host="server.remote.com"; # The server to which the backup will be copied.
$cfg_remote_login="backup_login"; # Login under which the backup will be saved.
$cfg_remote_path="/home/backup_login/backup"; # The directory where the backup files should be placed, the directory must be present.
``` 

3. `remote_ftp` - save backup on remote computer, data is transferred via ftp protocol, the remote host must have an ftp server running. Since the password is stored in the configuration file in clear form, it is desirable to restrict access to the remote host via `tcpwrapper` or `firewall`, as well as to restrict the login of the user under which the backup will be stored, only via chroot ftp. The positive sides of copying via ftp, is the high performance of the upload and a small load on the CPU. Configuration:

```shell
$cfg_type="remote_ftp";
$cfg_remote_host="server.remote.com"; # Server to which the backup will be copied.
$cfg_remote_password="Test1234"; # FTP login password.
$cfg_remote_login="backup_login"; # Login under which backup will be saved.
$cfg_remote_path="/home/backup_login/backup"; # The directory where the backup files should be placed, the directory must be present.
$cfg_remote_ftp_mode=0; # Active (0) or Passive (1) connection.
```

---

## Backup encryption

To encrypt the backup, the system must have the PGP encryption program GnuPG: `https://www.gnupg.org/` (recommended) or PGP: `https://www.openpgp.org/` installed.

Next:

1. `Local machine` - the machine on which the backup is performed.
2. `Remote machine` - the machine where the backup archive is saved.

To create public and secret keys, type (on the remote machine):

```shell
pgp2.6> pgp -kg
pgp5.0> pgpk -g
gnupg> gpg --gen-key # If key generation takes too long, use: gpg --quick-random key.
```

Export the created public key to a file (on the remote machine):

```shell
pgp2.6> pgp -akx <UserID> <file where the key will be written>
pgp5.0> pgpk -ax <UserID> <file where the key will be written>
gnupg> gpg --export -a <UserID> > <file where the key will be written>
```

Then, add the created public key (on the local machine):

```shell
pgp2.6>pgp -ka <key file from remote machine>
pgp5.0>pgpk -a <key file from remote machine>
gnupg>gpg --import <file where the key will be written>
# For gnupg you need to certify the key (gpg --gen-key on the lock machine don't forget):
gnupg>gpg --sign-key <key name>
```

You need to run (on a remote machine) to decrypt it:

```shell
pgp2.6>cat encrypted.tar.gz | pgp -f -z'password' > decrypted.tar.gz
pgp5.0>cat encrypted.tar.gz | pgpv -f -z'password' > decrypted.tar.gz
gnupg>cat encrypted.tar.gz | gpg --decrypt > decrypted.tar.gz
```

Encryption is used (on the local machine):

```shell
pgp2.6>cat input| pgp -ef userid > output
pgp5.0>cat input| pgpe -f userid > output
gnupg>cat input| gpg -e -r userid > output
```

---

## Notes

If you don't want encryption, set `$prog_pgp = ""`. Be sure: it about encryption of entry archive, NOT simply protect it for transfer to network backup server (SSH will describe below). It may eat many resources for big backups.

If you want encryption and set `$prog_pgp = "/usr/bin/gpg"`, set `$prog_gzip = ""`, because gpg will already compress it.

```shell
row 49: $cfg_checksum - used for incremental backup, "timesize" recomended.

row 60: $cfg_backup_style - "backup" for incremental backup

row 70: $cfg_increment_level - as described, after how many incremental copy make full refresh of backup. If 0, don't make full  refresh.

row 85: $cfg_save_old_backup - save or not OLD backup.

row 95: $cfg_type - for local part of your project, must be "local". Use dedicated HD for backup destination is recommended.
```

For you demands, must be created two configs (and placed into `create_backup.sh`). First, for backup all demanded dirs or files, with `$cfg_type="local"`. Other, for move first backup to another server, with `$cfg_type="remote_ssh"` or `"remote_ftp"`, in which result of first backup `($cfg_local_path`) described as backup dir. SSH is more secure, but FTP is more quickly. If both servers are placed in one ethernet segment, with trusted hosts only, use FTP. Otherwise, SSH.

For SSH method certificate must be generated on backup destination server and placed into user's home on another server.

```shell
row 103-105: $cfg_remote* - settings for remote cfg_types.

row 116: $cfg_remote_ftp_mode - 1 if you have problem with firewalls between servers.

row 122: $cfg_remote_password - for ftp login to remote server.

row 132: $cfg_local_path - if $cfg_type=local, backups will be placed here. Not the some with cache! Must be already created. Don't forget exclude it from directories for backup below.

row 142: $cfg_time_limit - as described, 0 for all.

row 152: $cfg_size_limit - as described, in KB

row 165: $cfg_maximum_archive_size - BEFORE compression!

row 174: $cfg_root_path - change it if you want describe all not from root dir.

row 185: $cfg_pgp_userid - as described, for encryption.

row 196: $cfg_verbose - verbose level

row 207: $cfg_stopdir_prune - leave untouched
```

So, for local backup I have change next setting:

```shell
$prog_pgp = "";
```

Below, you have a list of backup files and directories, example:

```shell
__DATA__
/usr/local/fsbackup
!/usr/local/fsbackup/cache
!/usr/local/fsbackup/archive
f!\.core$
f!^core$
f!\.o$
f!\.log$

# Linux
/usr/src/linux/.config

# Users
/home
/root
!/home/ftp
=!\.netscape/cache/
=!\.mozilla/.*/Cache/
=!\.mozilla/.*/NewCache/
=!\.mozilla/.*/News/
f!.*\.avi$
f!.*\.mpeg$
f!.*\.mpg$
f!.*\.mp3$

# System configuration
/etc
/var/cron/tabs
/var/spool/cron
/usr/local/etc
```

1. Creating the local backup dir and protect it:

```shell
mkdir -p /usr/local/fsbackup/archive
chmod 700 /usr/local/fsbackup/archive
```

2. Planning of backup:

```shell
crontab -e
```

Add string for weekly backup:

```shell
1 1 * * 1 root  /usr/local/fsbackup/create_backup.sh | mail -aFrom:"FROM NAME<from_example@example.com>" -s "Backup Report: `hostname`, `hostname -I | awk '{print $1}'`" to_example@example.com
```

Or for daily backup:

```shell
1 1 * * * root  /usr/local/fsbackup/create_backup.sh | mail -aFrom:"FROM NAME<from_example@example.com>" -s "Backup Report: `hostname`, `hostname -I | awk '{print $1}'`" to_example@example.com
```

You can run it as `nice -n 5 /usr/local/fsbackup/create_backup.sh` if you want decrease CPU load by backup for other apps.

3. Testing fsbackup:

```shell
$ /usr/local/fsbackup/create_backup.sh
Creating local backup: router_ap01
Current increment number: 0
Adding /usr/local/fsbackup....
done
Adding /usr/src/linux/.config....
done
Adding /home....
done
Adding /root....
done
Adding /etc....
done
Adding /var/cron/tabs....
done
Adding /var/spool/cron....
done
Adding /usr/local/etc....
done
Storing local backup...
***** Backup successful complete.
```

4. And verify:

```shell
$ ls -l /usr/local/fsbackup/archive
total 11088
-rw-r--r--    1 root     root     11091270 Sep 10 02:23 router_ap01-2005.09.10.02.23.00-0.tar.gz
-rw-r--r--    1 root     root            0 Sep 10 02:23 router_ap01-2005.09.10.02.23.00.del
-rw-r--r--    1 root     root        28874 Sep 10 02:23 router_ap01-2005.09.10.02.23.00.dir
-rw-r--r--    1 root     root       172032 Sep 10 02:23 router_ap01-2005.09.10.02.23.00.hash
-rw-r--r--    1 root     root        36191 Sep 10 02:23 router_ap01-2005.09.10.02.23.00.list
-rw-r--r--    1 root     root        41787 Sep 10 02:23 router_ap01-2005.09.10.02.23.00.lsize
```

---

## Postfix

Install and configure `postfix` for SMTP: `mail` command. Append these lines to `/etc/postfix/main.cf` to configure Postfix. Create the file if missing. Set the sender email address and password. Replace `USERNAME` and `PASSWORD` with your own data. Secure your password DB file.

```shell
$ apt-get update && apt-get install postfix mailutils libsasl2-2 ca-certificates libsasl2-modules
$ nano /etc/postfix/main.cf

relayhost = [smtp.gmail.com]:587
smtp_sasl_auth_enable = yes
smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd
smtp_sasl_security_options = noanonymous
smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt
smtp_use_tls = yes
smtpd_relay_restrictions = permit_mynetworks, permit_sasl_authenticated, defer_unauth_destination

$ echo [smtp.gmail.com]:587 USERNAME@gmail.com:PASSWORD > /etc/postfix/sasl_passwd
$ postmap /etc/postfix/sasl_passwd
$ chmod 400 /etc/postfix/sasl_passwd

$ chown root:root /etc/postfix/sasl_passwd /etc/postfix/sasl_passwd.db
$ chmod 0600 /etc/postfix/sasl_passwd /etc/postfix/sasl_passwd.db

$ chfn -f "Wazuh Server" root

$ systemctl restart postfix

$ echo "Test mail from postfix" | mail -aFrom:"FROM NAME<from_example@example.com>" -s "Backup Report: `hostname`, `hostname -I | awk '{print $1}'`" to_example@example.com
```

> The password must be an [App Password](https://security.google.com/settings/security/apppasswords). App Passwords can only be used with accounts that have 2-Step Verification turned on. 