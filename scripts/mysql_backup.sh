#!/usr/bin/env bash
#
# Script for backup SQL tables from MySQL
#
# For restore data type:
# mysql --login-path=$backup_login_path < backupfile
#

#-------------------
# Name of backup, single word.
#-------------------

backup_name="test_host"


#-------------------
# Backup method:
# full - backup full DB's structure and data (recommended).
#	 alternative mysqldump --all-databases --all
# db - backup full DB's structure and data only for 'backup_db_list' databases.
# notdb - backup full DB's structure and data for all DB's, except 
#         data of 'backup_db_list' databases.
#		  It is possible to exclude selective tables from the backup, then the format 
# 		  of the list of excluded tables is set as: 
# 		  "trash_db1 trash_db2:table1 trash_db2:table2"
# 		  - backup all bases, except trash_db1 base and tables table1 and 
# 		  table2 of trash_db2 base.
#-------------------

backup_method="notdb"


#-------------------
# List of databases or excluded from backup databases (delimited by spaces)
# Tables are specified as: database_name:table_name
#-------------------

backup_db_list="aspseek trash:cache_table1 trash:cache_table2 mnogosearch"


#-------------------
# mysql_config_editor utility which allows you to save in an encrypted .mylogin.cnf file the credentials for system authentication.
# Add a profile with login-password pair for MySQL (for databases):
# mysql_config_editor set --login-path=sqlProfile --host=localhost --user=root --password
# mysql_config_editor print --all
# my_print_defaults -s sqlProfile
#-------------------

backup_login_path="sqlProfile"


#-------------------
# Auth information for MySQL.
#-------------------

backup_mysqlhost="localhost"


#-------------------
# Directory to store SQL backup. You must have enought free disk space to store 
# all data from you SQL server.
#-------------------

backup_path="/usr/local/fsbackup/sys_backup"


#-------------------
# Full path of mysql programs.
#-------------------

backup_progdump_path="/usr/local/mysql/bin"


#-------------------
# Extra flags for mysqldump program. 
# -c (--complete-insert) - Use complete insert statements.
# -c - form backup data in the form of INSERT commands, specifying the names of the
#		of columns. If the speed of backup recovery and the size of the backup
#		are more important and compatibility with other DBMSs can be neglected, 
#		use: extra_mysqldump_flag="”
#-------------------

extra_mysqldump_flag="--complete-insert --host=$backup_mysqlhost"


############################################################################

if [ -n "$backup_progdump_path" ]; then
    backup_progdump_path="$backup_progdump_path/"
fi


#-------------------------------------------------------------------------
# Full backup MySQL
if [ "_$backup_method" = "_full" ]; then
    echo "Creating full backup of all MySQL databases."
    ${backup_progdump_path}mysqldump --login-path=$backup_login_path --all --add-drop-table --all-databases --force --no-data $extra_mysqldump_flag > $backup_path/$backup_name-struct-mysql
    ${backup_progdump_path}mysqldump --login-path=$backup_login_path --all-databases --all --add-drop-table --force $extra_mysqldump_flag |gzip > $backup_path/$backup_name-mysql.gz
    exit
fi


#-------------------------------------------------------------------------
# Backup of specified databases for MySQL
if [ "_$backup_method" = "_db" ]; then
    echo "Creating full backup of $backup_db_list MySQL databases."
    ${backup_progdump_path}mysqldump --login-path=$backup_login_path --add-drop-table --all-databases --force --no-data $extra_mysqldump_flag > $backup_path/$backup_name-struct-mysql
    cat /dev/null > $backup_path/$backup_name-mysql

    for cur_db in $backup_db_list; do
        echo "Dumping $cur_db..."
        cur_db=`echo "$cur_db" | awk -F':' '{if (\$2 != ""){print \$1, \$2}else{print \$1}}'`
        ${backup_progdump_path}mysqldump --login-path=$backup_login_path --add-drop-table --databases --force $extra_mysqldump_flag $cur_db >> $backup_path/$backup_name-mysql
    done
    gzip -f $backup_path/$backup_name-mysql
    exit
fi


#-------------------------------------------------------------------------
# Backup of all databases except those specified for MySQL
if [ "_$backup_method" = "_notdb" ]; then
    echo "Creating full backup of all MySQL databases except databases $backup_db_list."
    ${backup_progdump_path}mysqldump --login-path=$backup_login_path --all --add-drop-table --all-databases --force --no-data $extra_mysqldump_flag > $backup_path/$backup_name-struct-mysql
    cat /dev/null > $backup_path/$backup_name-mysql

    for cur_db in `${backup_progdump_path}mysqlshow --login-path=$backup_login_path| tr -d ' |'|grep -v -E '^Databases$|^\+\-\-\-'`; do

        grep_flag=`echo " $backup_db_list"| grep " $cur_db:"`
        if [ -n "$grep_flag" ]; then
			# Exclude tables for this database
            ${backup_progdump_path}mysqldump --login-path=$backup_login_path --all --add-drop-table --databases --no-create-info --no-data --force $extra_mysqldump_flag $cur_db >> $backup_path/$backup_name-mysql

            for cur_db_table in `${backup_progdump_path}mysqlshow --login-path=$backup_login_path $cur_db| tr -d ' |'|grep -v -E '^Tables$|^Database\:|^\+\-\-\-'`; do

                flag=1
                for cur_ignore in $backup_db_list; do
                    if [ "_$cur_ignore" = "_$cur_db:$cur_db_table" ]; then
                        flag=0
                    fi
                done

                if [ $flag -gt 0 ]; then
                    echo "Dumping $cur_db:$cur_db_table..."
                    ${backup_progdump_path}mysqldump --login-path=$backup_login_path --all --add-drop-table --force $extra_mysqldump_flag $cur_db $cur_db_table >> $backup_path/$backup_name-mysql

                else
                    echo "Skiping $cur_db:$cur_db_table..."
                fi
            done
        else
			# Excluding database
            flag=1
            for cur_ignore in $backup_db_list; do
                if [ "_$cur_ignore" = "_$cur_db" ]; then
                    flag=0
                fi
            done

            if [ $flag -gt 0 ]; then
                echo "Dumping $cur_db..."
                ${backup_progdump_path}mysqldump --login-path=$backup_login_path --all --add-drop-table --databases --force $extra_mysqldump_flag $cur_db >> $backup_path/$backup_name-mysql
            else
                echo "Skiping $cur_db..."
            fi
        fi
    done
    gzip -f $backup_path/$backup_name-mysql
    exit
fi

echo "Configuration error. Not valid parameters in backup_method or backup_sqltype."