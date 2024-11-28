#!/usr/bin/env bash
#
# Script for backup SQL tables from SQLite
#
# For restore data type:
# cat <backupfile> | sqlite <path_to_db_file>
#

#-------------------
# Name of backup, single word.
#-------------------

backup_name="test_host"

#-------------------
# Backup method:
# full  - backup full DB's structure and data.
# db    - backup full DB's structure and data only for 'backup_db_list' databases.
# notdb - backup full DB's structure and data for all DB's, except 
#         data of 'backup_db_list' databases.
# 		  It is possible to exclude selective tables from the backup, then the format 
# 		  of the list of excluded tables is set as: 
# 		  "trash_db1 trash_db2:table1 trash_db2:table2"
# 		  - backup all bases, except trash_db1 base and tables table1 and 
# 		  table2 of trash_db2 base.
#-------------------

backup_method="notdb"

#-------------------
# List of databases (full path delimited by spaces)
# Tables are specified in the backup_tables_list variable as: database_name:table_name
# Attention, selecting the “db” method requires a complete listing of all 
# databases and tables to be backed up into the backup_tables_list variable
#-------------------

backup_db_list="/home/test/test /home/web/work_db /home/rt/rt3"
backup_tables_list="test rt3:Links"

#-------------------
# Directory to store SQLite backup. You must have enough free disk space to store 
# all data from you SQLite server.
#-------------------

backup_path="/usr/local/fsbackup/sys_backup"

#-------------------
# Full path of SQLite program.
#-------------------

backup_progdump_path="/usr/local/bin"

############################################################################

if [ -n "$backup_progdump_path" ]; then
    backup_progdump_path="$backup_progdump_path/"
fi

#-------------------------------------------------------------------------
# Full backup for SQLite
if [ "_$backup_method" = "_full" ]; then
    echo "Creating full backup of all SQLite databases."
    for cur_db in $backup_db_list; do
	cur_db_name=`basename $cur_db`
	if [ -f "$cur_db" ]; then
	    ${backup_progdump_path}sqlite $cur_db .dump |gzip > $backup_path/$backup_name-$cur_db_name-sqlite.gz
	else
	    echo "DB $cur_db not found"
	fi
    done
    exit

fi

#-------------------------------------------------------------------------
# Backup of specified databases for SQLite
if [ "_$backup_method" = "_db" ]; then
    echo "Creating full backup of $backup_tables_list SQLite databases."

    for cur_db in $backup_db_list; do
	cur_db_name=`basename $cur_db`
	if [ -f "$cur_db" ]; then
	    echo "Proccessing $cur_db"
	    flag=0
	    for cur_acl in $backup_tables_list; do
		if [ "_$cur_acl" = "_$cur_db_name" ]; then
		    flag=1
		fi
	    done
    	
	    if [ $flag -eq 1 ]; then
	        echo "Dumping $cur_db_name"
	        ${backup_progdump_path}sqlite $cur_db .dump |gzip > $backup_path/$backup_name-$cur_db_name-sqlite.gz
	    else
		rm -f $backup_path/$backup_name-$cur_db_name-sqlite
	        for cur_db_table in `${backup_progdump_path}sqlite $cur_db .tables`; do
		    for cur_acl in $backup_tables_list; do
			if [ "_$cur_acl" = "_$cur_db_name:$cur_db_table" ]; then
			    echo "  Dumping $cur_db_name:$cur_db_table"
			    ${backup_progdump_path}sqlite $cur_db ".dump $cur_db_table" >> $backup_path/$backup_name-$cur_db_name-sqlite
			fi
		    done
		done	    
		if [ -f "$backup_path/$backup_name-$cur_db_name-sqlite" ]; then
		    gzip -f $backup_path/$backup_name-$cur_db_name-sqlite
		fi
	    fi
	else
	    echo "DB $cur_db not found"
	fi
    done
    exit

fi


#-------------------------------------------------------------------------
# Backup of all databases except for SQLite
if [ "_$backup_method" = "_notdb" ]; then
    echo "Creating full backup of all SQLite databases except databases $backup_tables_list."

    for cur_db in $backup_db_list; do
	cur_db_name=`basename $cur_db`
	if [ -f "$cur_db" ]; then
	    echo "Proccessing $cur_db"
	    flag=0
	    for cur_acl in $backup_tables_list; do
		if [ "_$cur_acl" = "_$cur_db_name" ]; then
		    flag=1
		fi
	    done
    	    
	    if [ $flag -eq 1 ]; then
		echo "Skiping $cur_db_name"
	    else
		rm -f $backup_path/$backup_name-$cur_db_name-sqlite
		for cur_db_table in `${backup_progdump_path}sqlite $cur_db .tables`; do
		    flag=0
		    for cur_acl in $backup_tables_list; do
			if [ "_$cur_acl" = "_$cur_db_name:$cur_db_table" ]; then
			    echo "  Skiping $cur_db_name:$cur_db_table"
			    flag=1
			fi
		    done

		    if [ $flag -eq 0 ]; then
			${backup_progdump_path}sqlite $cur_db ".dump $cur_db_table" >> $backup_path/$backup_name-$cur_db_name-sqlite
    		    fi
	    	done	    
	    
		if [ -f "$backup_path/$backup_name-$cur_db_name-sqlite" ]; then
		    gzip -f $backup_path/$backup_name-$cur_db_name-sqlite
		fi
	    fi
	else
	    echo "DB $cur_db not found"
	fi
    done
    exit

fi

echo "Configuration error. Not valid parameters in backup_method or backup_sqltype."