#!/usr/bin/perl
# Script for backup SQL tables from InterBase
#

#-------------------
# Directory to store SQL backup. You must have enough free disk space to store 
# all data from you SQL server.
#-------------------

$backup_path="/opt/fsbackup";

#-------------------
# List of databases and it's
# names of backup, single word.
#-------------------

%db_list=(

"/interbase/base1.gdb",	 "base1.gbk",
"/interbase/base2.gdb",  "base2.gbk"

);


#-------------------
# Auth information for MySQL.
#-------------------

#backup_ibuser=""
#backup_ibpassword=""


#-------------------
# Full path of InterBase backup program (gbak).
#-------------------

$backup_progdump="/opt/interbase/bin/gbak";

#-------------------                                                          
# Verbose level.                                                              
#       0       - Silent mode, suspend all output, except fatal configuration 
#                 errors.                                                     
#       1       - Output errors and warnings.                                 
#       2       - Output all the  available  data.                            
#                                                                                                           
#-------------------                                                          
                                                                              
$cfg_verbose = 2;                                                           
  
#-------------------                                                        
# Full path of some external program running from C<fsbackup.pl>.           
# $prog_gzip = "" - not use compression.                                                 
#-------------------       
                                                 
$prog_gzip="/bin/gzip"; # If equal to "", or the program was not found,          
                        # then don't use compression.                      
                                                                            
############################################################################
if ($cfg_verbose > 1) {$gbak_verbose="-v";};
# Determine if there is a matching file $prog_gzip

if ( -f $prog_gzip ) { 
    $add_ext=".gz"; 
    $prog_gzip="stdout | $prog_gzip >";
}
else {
    print "WARRNING: Programm $prog_gzip not found!\n" if ($prog_gzip and $cfg_verbose > 0 );
    $prog_gzip="";
}

#---------------------------------------------------------------------------
# Backup of specified databases for InterBase
    foreach (keys %db_list){
        if ( not -f $_){ 
	    print "ERROR: Source file $_ not found!\n" if ($cfg_verbose >0);    
	    next;
        }; 
    print "Dumping $_  in $backup_path/$db_list{$_}...\n" if ($cfg_verbose > 1);

    `$backup_progdump -B $gbak_verbose  $_ $prog_gzip $backup_path/$db_list{$_}$add_ext\n`;
    }