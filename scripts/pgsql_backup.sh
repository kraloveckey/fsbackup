#!/usr/bin/env bash
#
# Script for backup SQL tables from PostreSQL
#
# For restore data type: psql -d template1 -f backupfile
#

#-------------------
# Name of backup, single word.
#-------------------

backup_name="hostname_pgsql"

#-------------------
# Backup method:
# full  - backup full DB's structure and data (recommended),
#	 	  alternative pg_dumpall.
# db    - backup full DB's structure and data only for 'backup_db_list' databases.
# notdb - backup full DB's structure and data for all DB's, except
#         data of 'backup_db_list' databases.
#		  It is possible to exclude selective tables from the backup, then the format 
# 		  of the list of excluded tables is set as: 
# 		  "trash_db1 trash_db2:table1 trash_db2:table2"
# 		  - backup all bases, except trash_db1 base and tables table1 and 
# 		  table2 of trash_db2 base.
#-------------------

backup_method="full"

#-------------------
# List of databases (delimited by spaces)
# Tables are specified as: database_name:table_name
#-------------------

backup_db_list="aspseek trash:cache_table1 trash:cache_table2 mnogosearch"


#-------------------
# Auth information for PostgreSQL.
#-------------------
backup_sqluser=""
backup_sqlpassword=""
backup_sqlhost=""
# Default PostgreSQL port is 5432
backup_sqlport="5432"

# File $PGPASS_FILE format: hostname:port:database:username:password
# don't change below line!
PGPASS_FILE="/root/.pgpass"

#-------------------
# Change to user (by su) before run 'pgdump' util
# Run 'pgdump' as user:
#backup_suuser="postgres"
backup_suuser=""

#
# Chown by $backup_suuser the $backup_path directory
# Change the permissions of the $backup_path directory and the $PGPASS_FILE file
# (it is better to do it manually, so that there will be no conflicts in the future)
chown_by_suuser=0

# If $chown_by_suuser is used, you need to change the PGPASS_FILE to '~$backup_suuser/.pgpass'
# (i.e. to '~postgres/.pgpass', or better yet, the exact path to the $backup_suuser home directory)

#-------------------
# Make a final WAL (Write-Ahead Logs) backup and rotate at the end.
# Before doing so, put these scripts from the 'contrib/psql_wal' folder in /usr/local/fsbackup/scripts
# Be sure to customize these scripts (by editing them first)
# Instructions on what WAL is and how to use it can be found in the comments of contrib/psql_wal/daily_pgsql_backup.sh file
wal_backup=0

#-------------------
# Directory to store SQL backup. You must have enought free disk space to store
# all data from you SQL server.
#-------------------

backup_path="/usr/local/fsbackup/sys_backup"


#-------------------
# Full path of PostgreSQL programs.
#-------------------

backup_progdump_path="/usr/local/pgsql/bin"
#backup_progdump_path="/usr/bin"

#-------------------
# Extra flags for pg_dump program.
# -D - Dump data as INSERT commands with  explicit  column names
# Additional parameters for pg_dump
# -D - form data backup in the form of INSERT commands, specifying the names of the
# column names. If speed of recovery from backup and backup size
# are more important, and compatibility with other DBMSs can be neglected,
# use: extra_pg_dump_flag="”
# New name of the '-D' option: --inserts
#
# -h, --host=NAME			database server name or socket directory
# -l, --database=NAME_DB 	select a different database by default
# -p, --port=PORT 			the port number of the database server
# -U, --username=NAME 		database user name
# -w, --no-password 		do not ask for a password
# -W, --password 			always require a password (usually not required)
#-------------------

extra_pg_dump_flag="--inserts"
#extra_pg_dump_flag=""

############################################################################

if [ "_$backup_sqluser" != "_" ]; then
	# fill $PGPASS_FILE for authorization
	echo "$backup_sqlhost:$backup_sqlport:*:$backup_sqluser:$backup_sqlpassword" > $PGPASS_FILE
	chmod 0600 $PGPASS_FILE

	# add authorization to parameters
	extra_pg_dump_flag="$extra_pg_dump_flag -U $backup_sqluser"
	if [ "_$backup_sqlhost" != "_" ]; then
		extra_pg_dump_flag="$extra_pg_dump_flag -h $backup_sqlhost"
	fi
	if [ "_$backup_sqlport" != "_" ]; then
		extra_pg_dump_flag="$extra_pg_dump_flag -p $backup_sqlport"
	fi
fi

if [ "_$backup_suuser" != "_" ] && [ $chown_by_suuser -eq 1 ]; then
    chown -R $backup_suuser $backup_path
    chown $backup_suuser $PGPASS_FILE
fi

if [ -n "$backup_progdump_path" ]; then
    backup_progdump_path="$backup_progdump_path/"
fi

#------------------------

if [ $wal_backup -eq 1 ]; then
    echo "Creating last daily backup before new full backup"
    /usr/local/fsbackup/scripts/daily_pgsql_backup.sh "force"
fi

#-------------------------------------------------------------------------
# Full backup for PostgreSQL
if [ "_$backup_method" = "_full" ]; then
    echo "Creating full backup of all PostgreSQL databases."
    if [ "_$backup_sqluser" = "_" ]; then
        ${backup_progdump_path}pg_dumpall $extra_pg_dump_flag -s > $backup_path/$backup_name-struct-pgsql
    fi
    if [ "_$backup_suuser" != "_" ]; then
        su - ${backup_suuser} -c ${backup_progdump_path}/pg_dumpall $extra_pg_dump_flag > $backup_path/$backup_name-pgsql
    else
        ${backup_progdump_path}/pg_dumpall $extra_pg_dump_flag > $backup_path/$backup_name-pgsql
    fi

#-------------------------------------------------------------------------
# Backup of specified databases for PostgreSQL
elif [ "_$backup_method" = "_db" ]; then
    echo "Creating full backup of $backup_db_list PostgreSQL databases."
    if [ "_$backup_sqluser" = "_" ]; then
        ${backup_progdump_path}pg_dumpall $extra_pg_dump_flag -s > $backup_path/$backup_name-struct-pgsql
    fi
    cat /dev/null > $backup_path/$backup_name-pgsql

    for cur_db in $backup_db_list; do
	echo "Dumping $cur_db..."
	cur_db=`echo "$cur_db" | awk -F':' '{if (\$2 != ""){print "-t", \$2, \$1}else{print \$1}}'`
	if [ "_$backup_suuser" != "_" ]; then
		chown $backup_suuser $backup_path/$backup_name-pgsql
		su - ${backup_suuser} -c ${backup_progdump_path}pg_dump $extra_pg_dump_flag $cur_db >> $backup_path/$backup_name-pgsql
        else
		${backup_progdump_path}pg_dump $extra_pg_dump_flag $cur_db >> $backup_path/$backup_name-pgsql
	fi
    done
    gzip -f $backup_path/$backup_name-pgsql

#-------------------------------------------------------------------------
# Backup of all databases except those specified for PostgreSQL
elif [ "_$backup_method" = "_notdb" ]; then
    echo "Creating full backup of all PostgreSQL databases except databases $backup_db_list."
    if [ "_$backup_suuser" != "_" ]; then
        # TODO: Need to finalize this spot below... in the meantime, a plug:
        echo "The '$backup_method' method does not support the 'backup_suuser' parameter, yet. Sorry, exit..."
        exit 1
    fi
    if [ "_$backup_sqluser" = "_" ]; then
        ${backup_progdump_path}pg_dumpall $extra_pg_dump_flag -s > $backup_path/$backup_name-struct-pgsql
    fi
    cat /dev/null > $backup_path/$backup_name-pgsql

    for cur_db in `${backup_progdump_path}psql -A -q -t -c "select datname from pg_database" template1 | grep -v '^template[01]$' `; do

	grep_flag=`echo " $backup_db_list"| grep " $cur_db:"`
	if [ -n "$grep_flag" ]; then
		# Exclude tables for this database
	    for cur_db_table in `${backup_progdump_path}psql -A -q -t -c "select tablename from pg_tables WHERE tablename NOT LIKE 'pg\_%' AND tablename NOT LIKE 'sql\_%';" $cur_db`; do

		flag=1
		for cur_ignore in $backup_db_list; do
		    if [ "_$cur_ignore" = "_$cur_db:$cur_db_table" ]; then
			flag=0
		    fi
		done

		if [ $flag -gt 0 ]; then
		    echo "Dumping $cur_db:$cur_db_table..."
		    ${backup_progdump_path}pg_dump $extra_pg_dump_flag -t $cur_db_table $cur_db >> $backup_path/$backup_name-pgsql
		else
		    echo "Skiping $cur_db:$cur_db_table..."
		fi
	    done
	else
		# Database exclusion
	    flag=1
	    for cur_ignore in $backup_db_list; do
		if [ "_$cur_ignore" = "_$cur_db" ]; then
		    flag=0
		fi
	    done

	    if [ $flag -gt 0 ]; then
		echo "Dumping $cur_db..."
		${backup_progdump_path}pg_dump $extra_pg_dump_flag $cur_db >> $backup_path/$backup_name-pgsql
	    else
		echo "Skiping $cur_db..."
	    fi
	fi
    done
    gzip -f $backup_path/$backup_name-pgsql
else
    # Unknown $backup_method
    echo "Configuration error. Not valid parameters in backup_method."
    exit 1
fi

if [ $wal_backup -eq 1 ]; then
    # Rotate daily backups (prepare for new WAL files)
    /usr/local/fsbackup/scripts/daily_pgsql_rotate.pl "do"
fi

