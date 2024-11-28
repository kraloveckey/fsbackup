#!/usr/bin/env bash
#
# Script for restore files backuped by fsbackup.pl
# Attention, the data must be decrypted beforehand in case PGP is used
#

#-------------------
# Name of backup, single word.
#-------------------

backup_name="test_host"


#-------------------
# Directory with content of incremental backup.
#-------------------

backup_path="/mnt/backup"


#-------------------
# Directory to save restored data.
#-------------------

restore_path="/var/backup" 


###########################################################################
old_path=`pwd`
cd $backup_path

for cur_arc in `ls *.tar* | sort -n`; do
	del_file="`echo \"$cur_arc\"| sed 's/\-0.tar\(.gz\)*$//'`.del"
	dir_file="`echo \"$cur_arc\"| sed 's/\-0.tar\(.gz\)*$//'`.dir"
	if [ -e "$del_file" ]; then
    	    echo "Removing deleted files for $cur_arc..."
	    cd $restore_path
	    sh $backup_path/$del_file
	    cd $backup_path
	fi
        echo "Restoring $cur_arc..."
	gzip_type=`ls $cur_arc|grep '.gz'`
	if [ -n "$gzip_type" ]; then
	    tar -xpzf $cur_arc -C $restore_path
	else
	    tar -xpf $cur_arc -C $restore_path
	fi
	if [ -e "$dir_file" ]; then
	    echo "Fixing directory permissions for $cur_arc..."
	    cd $restore_path
	    sh $backup_path/$dir_file
	    cd $backup_path
	fi
done

cd $old_path