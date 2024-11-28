#!/usr/bin/env bash
#
# Hourly backup of the most critical data on SQL server.
# cron:
# 53 */1 * * *   /usr/local/fsbackup/scripts/hourly_sql_backup.sh >/dev/null
#

backup_database="testbase"

usefull_table_list="table1 table2 table3"
	   
backup_path="/backup/.DB"

backup_progdump_path="/usr/local/pgsql/bin"

############################################################################
#/sbin/mount -u -w /backup
#/bin/mount -o remount,rw /backup

if [ ! -d "$backup_path" ]; then
    mkdir $backup_path
fi

backup_iteration=`date \+\%H`
backup_path="$backup_path/$backup_iteration"

if [ ! -d "$backup_path" ]; then
    mkdir $backup_path
fi


#-------------------------------------------------------------------------
# Backup of specified databases for PostgreSQL

    for cur_table in $usefull_table_list; do
	echo "Dumping $cur_table..."
	${backup_progdump_path}/pg_dump -a -t $cur_table $backup_database > $backup_path/$cur_table.sql
	/bin/chmod 0600 $backup_path/$cur_table.sql
    done

#sync; sync; sync
#sleep 5
#/sbin/mount -u -w /backup
#/bin/mount -o remount,rw /backup