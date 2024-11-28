#!/usr/bin/env bash
#
# Copy /home/backup_* with backups to a backup disk and triple-rotate to 3 disks.
# Delete "OLD" directories on the backup disk.
# 8 23 5,20 * * /usr/local/etc/backup/double_tar3.sh
#

reserv0="/backup/reserv.0"
reserv1="/backup2/backup_reserv/reserv.1"
reserv2="/backup3/reserv.2"


rm -rf $reserv2
mv -f $reserv1 $reserv2
mv -f $reserv0 $reserv1

mkdir $reserv0
cp -Rfp /home/backup_* $reserv0
find $reserv0 -name OLD -type d -exec rm -rf {} \;