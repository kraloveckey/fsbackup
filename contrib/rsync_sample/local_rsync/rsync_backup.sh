#!/usr/bin/env bash
#
# A full backup of the system to a backup disk
#

# Prevent the process from memory leak.
ulimit -v 200000

# Prevent two rsync processes from running at the same time.
IDLE=`ps -auxwww | grep -E "root.*rsync" | grep -vE "grep|rsync_backup"`
if [ "$IDLE" != "" ];  then
    echo "FATAL DUP"| mail -aFrom:"FROM NAME<from_example@example.com>" -s "ATAL RSYNC BACKUP DUP: `hostname`, `hostname -I | awk '{print $1}'`" to_example@example.com
exit
fi

date
#/sbin/mount -u -w /backup
#/bin/mount -o remount,rw /backup

# Save a list of all directories and their parameters.
/usr/local/fsbackup/scripts/create_dir_list.pl / > /usr/local/fsbackup/sys_backup/dir_list.txt

#/usr/local/bin/rsync -a -v --delete --delete-excluded --backup --exclude-from=/etc/rsync_backup.exclude / /backup
/usr/local/bin/rsync -a -v --delete --backup --exclude-from=/etc/rsync_backup.exclude / /backup

RETCODE=$?
if [ $RETCODE -ne 0 -a $RETCODE -ne 24 ]; then
        echo "Err code=$RETCODE" | mail -aFrom:"FROM NAME<from_example@example.com>" -s "FATAL RSYNC BACKUP: `hostname`, `hostname -I | awk '{print $1}'`" to_example@example.com
fi
echo RET: $RETCODE

# Additional backup of mailboxes (without backing up old copies).
/usr/local/bin/rsync -a -v --delete /var/mail /backup/var/

/bin/chmod 0700 /backup
#/sbin/mount -u -r /backup
#/bin/mount -o remount,rw /backup

date