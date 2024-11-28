#!/usr/bin/env bash
#
# Synchronize the home directory of user "user_name" and 
# database "database_name" to the remote host.
#

CUR_PATH=/home/user/backup_rsync
date

# Prevent the process from memory leak.
ulimit -v 200000

# Prevent two rsync processes from running at the same time.
IDLE=`ps -auxwww | grep "rsync" | grep -vE "grep|rsync_backup"`
if [ "$IDLE" != "" ];  then
    echo "FATAL DUP" | mail -aFrom:"FROM NAME<from_example@example.com>" -s "FATAL RSYNC BACKUP DUP: `hostname`, `hostname -I | awk '{print $1}'`" to_example@example.com
exit
fi


/usr/local/pgsql/bin/pg_dump -c database_name |/usr/bin/gzip > ~/sql_dump.sql.gz

export RSYNC_RSH="ssh -c arcfour -o Compression=no -x"

# -n
/usr/local/bin/rsync -a -z -v --delete --max-delete=600 --bwlimit=50 \
  --backup --backup-dir=/home/backup_user/BACKUP_OLD_user_name \
  --exclude-from=$CUR_PATH/rsync.exclude \
  /home/user_name/ backup_user@backuphost.com:/home/backup_user/BACKUP_user_name/
  
  
RETCODE=$?
if [ $RETCODE -ne 0 -a $RETCODE -ne 24 ]; then
	echo "Err code=$RETCODE" | mail -aFrom:"FROM NAME<from_example@example.com>" -s "FATAL RSYNC BACKUP: `hostname`, `hostname -I | awk '{print $1}'`" to_example@example.com
fi
echo RET: $RETCODE
date