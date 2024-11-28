#!/usr/bin/env bash
#
# Mirroring /home to /backup2
# 8 18 * * * /usr/local/etc/backup/double_mirror.sh >/var/log/rsync.log 
#

date
/usr/local/bin/rsync -a -v --delete --delete-excluded --backup --exclude-from=/usr/local/etc/rsync_backup.exclude / /backup2/rsync 

RETCODE=$?
if [ $RETCODE -ne 0 -a $RETCODE -ne 24 ]; then
        echo "Err code=$RETCODE" | mail -aFrom:"FROM NAME<from_example@example.com>" -s "FATAL RSYNC BACKUP: `hostname`, `hostname -I | awk '{print $1}'`" to_example@example.com
fi
echo RET: $RETCODE
date