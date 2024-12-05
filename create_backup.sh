#!/usr/bin/env bash
#
# Backup planner running from crontab.
#
# Example line for crontab:
#
# 18 4 * * * /usr/local/fsbackup/create_backup.sh | mail -aFrom:"FROM NAME<from_example@example.com>" -s "Backup Report: `hostname`, `hostname -I | awk '{print $1}'`" to_example@example.com

#--------------------------------------
# Path where fsbackup installed.
#--------------------------------------

backup_path="/usr/local/fsbackup"

#--------------------------------------
# List of fsbackup configuration files, delimited by spaces.
# Directories for saving backup in each configuration file should differ
# ($cfg_remote_path, $cfg_local_path), saving multiple backups described by different .conf files 
# in the same directory is not allowed is not acceptable.
#--------------------------------------

config_files="cfg_example cfg_example_users cfg_example_sql"

#--------------------------------------
# MySQL table backup flag, 1 - run ./scripts/mysql_backup.sh script (you need edit ./scripts/mysql_backup.sh first!), 0 - not run.
#--------------------------------------

backup_mysql=0

#--------------------------------------
# PostgreSQL table backup flag, 1 - run ./scripts/pgsql_backup.sh script (you need edit ./scripts/pgsql_backup.sh first!), 0 - not run.
#--------------------------------------

backup_pgsql=0

#--------------------------------------
# SQLite table backup flag, 1 - run ./scripts/sqlite_backup.sh script (you need edit ./scripts/sqlite_backup.sh first!), 0 - not run.
#--------------------------------------

backup_sqlite=0

#--------------------------------------
# System parameters backup flag, 1 - run ./scripts/sysbackup.sh script (you need edit ./scripts/sysbackup.sh first!), 0 - not run.
#--------------------------------------

backup_sys=0

#--------------------------------------
# 1 - run mount-windows-share.sh script (you need edit mount-windows-share.sh first!), 0 - not run.
#
# Flag to run the script that mounts the Windows share.
# Pre-configuration of the ./scripts/mount-windows-share.sh script is required,
# 1 to run, 0 not to run.
#--------------------------------------

mount_winshare=0

#--------------------------------------
# 1 - run mount-ftps-share.sh script (you need edit mount-ftps-share.sh first!), 0 - not run.
#
# Flag to run the script that mounts the FTPS share.
# Pre-configuration of the ./scripts/mount-ftps-share.sh script is required,
# 1 to run, 0 not to run.
#--------------------------------------

mount_ftpsshare=0

#############################################################################
# Protection against re-running two copies of fsbackup.pl
IDLE=`ps auxwww | grep fsbackup.pl | grep -v grep`
if [ "$IDLE" != "" ];  then
    echo "!!!!!!!!!!!!!!! `date` Backup dup"
    exit
fi

cd $backup_path

# Saving MySQL databases
if [ $backup_mysql -eq 1 ]; then
    ./scripts/mysql_backup.sh
fi

# Saving PostgreSQL databases
if [ $backup_pgsql -eq 1 ]; then
    ./scripts/pgsql_backup.sh
fi

# Saving SQLite databases
if [ $backup_sqlite -eq 1 ]; then
    ./scripts/sqlite_backup.sh
fi

# Saving system parameters
if [ $backup_sys -eq 1 ]; then
    ./scripts/sysbackup.sh
fi

# Mount Windows share (wait for it to show up)
if [ $mount_winshare -eq 1 ]; then
    ./scripts/mount-windows-share.sh || exit 1
fi

# Mount FTPS share (wait for it to show up)
if [ $mount_ftpsshare -eq 1 ]; then
    ./scripts/mount-ftps-share.sh || exit 1
fi

# Backup.
for cur_conf in $config_files; do
    ./fsbackup.pl ./$cur_conf
    next_iter=`echo "$config_files"| grep "$cur_conf "`
    if [ -n "$next_iter" ]; then
	sleep 600 # Sleep for 10 minutes, let the processor cool down :-)
    fi
done

# Unmounting the Windows share.
if [ $mount_winshare -eq 1 ]; then
    ./scripts/mount-windows-share.sh umount
fi

# Unmounting the FTPS share.
if [ $mount_ftpsshare -eq 1 ]; then
    ./scripts/mount-ftps-share.sh umount
fi