#!/usr/bin/perl
# fsbackup - file system backup and synchronization utility. 
#
# Keys:
# -n - create a new archive whatever the state of the hash.
# -f - full_backup - full backup to archive, no hash.
# -h - hash - only hash generation, without putting the files in the archive.
# -c - clean - clearing the storage with incremental backup and creating a new backup.

#############################################
use constant DB_DEF_CACHE_SIZE => 4096000; # Cache size to place the hash in memory.

use POSIX;
use File::Find;
use Digest::MD5 qw(md5_base64);
use Net::FTP;
use Net::FTPSSL;
use DB_File;

use constant VERB_SILENT => 0; # Silent mode, suspend all output.
use constant VERB_ERROR => 1; # Output all errors and warnings.
use constant VERB_ALL => 2; # Output all the  available  data.

my $list_lines_cnt = 0;
my $del_lines_cnt = 0;
my $cur_time = time();
my %active_hash_last;
my %active_hash_new;
my $cfg_new_flag = 0;
my $cfg_clean_flag = 0;
my $config = 0;
my $cur_backup_size = 1536; # Block tar size
my $backup_file_base;
my $prog_pgp_filter;
my $prog_gzip_filter;
my $arc_ext;
my $ftp;
my $cur_increment_level;
my $cur_dir;
my $cur_path;
my $cur_file;
my $cur_pathitem;
my $file_fullpath;
my $file_fullpath_md5;
my $key;
my $dbobj_new;
my $dbobj_last;
my $db_hashinfo;
my $db_hashinfo2;
my $file;
my @volume_position=(0);
my @fs_path=();	       #  /dir[/file] - Path to the file/directory to back up.
my @fs_notpath=();     #  ! - Path negation, do not place in backup. Must always be the first character.
my @fs_mask=();        #  =~ - Mask for the file or directory, not the absolute path. The first or second character.
my @fs_filemask=();    #  f~ - Mask for the file. The first or second character.
my @fs_dirmask=();     #  d~ - Mask for the directory. The first or second character.
my @fs_notmask=();     #  =! - "NOT" a mask for a file or directory, not an absolute path. The first or second character.
my @fs_notfilemask=(); #  f! - "NOT" mask for the file. The first or second character.
my @fs_notdirmask=();  #  d! - "NOT" mask for the directory. The first or second character.

# ------------- Processing command line parameters

if ($ARGV[0] eq "-n" || $ARGV[0] eq "-h" || $ARGV[0] eq "-f" || $ARGV[0] eq "-c"){
    $cfg_new_flag=1;
    $config = $ARGV[1];
} else {
    $cfg_new_flag=0;
    $config = $ARGV[0];
}

if ( ! -f $config){
    die "Usage: fsbackup.pl [-n|-f|-h|-c] config_name\n";
}


require "$config";

if ( ! -d $cfg_cache_dir){
    die "\$cfg_cache_dir ($cfg_cache_dir) not found. Set \$cfg_cache_dir varisble in fsbackup.pl\n";
}

$cfg_time_limit *= 60 * 60 * 24; 	# Days into seconds.
$cfg_size_limit *= 1024;	 	 	# Kilobytes to bytes.
$cfg_maximum_archive_size *= 1024;	# Kilobytes to bytes.

if (-d $cfg_root_path){
    chdir($cfg_root_path);
} else {
    die "Invalid \$cfg_root_path path ($cfg_root_path)\n";
}

if ($ARGV[0] eq "-h"){
    $cfg_backup_style = "hash";
}
if ($ARGV[0] eq "-f" ){
    $cfg_backup_style = "full_backup";
}

if ($ARGV[0] eq "-c" ){
    $cfg_clean_flag=1;
} else {
    $cfg_clean_flag=0;
}

#------------------- Check variables in the configuration file.
if ($cfg_backup_name !~ /^[\w\d\_]+$/){
    die "Found illegal characters in $cfg_backup_name ($cfg_backup_name).";
}

if (! grep {$_ eq $cfg_checksum} ("md5", "timesize")){
    die "Unknown checksum method:\$cfg_checksum=$cfg_checksum (allowed md5 or timesize)\n";
}

if (! grep {$_ eq $cfg_backup_style} ("backup", "full_backup", "sync", "hash")){
    die "Unknown backup_style:\$cfg_backup_style=$cfg_backup_style\n";
}

if ($cfg_remote_ftp_mode != 1){
    $cfg_remote_ftp_mode = 0;
}

if ($cfg_backup_style eq "full_backup" || $cfg_backup_style eq "hash"){
    $cfg_new_flag=1;
    $cfg_clean_flag=1;
}

if (! grep {$_ eq $cfg_type} ("local", "remote_ssh", "remote_ftp", "remote_ftps")){
    die "Unknown backup target:\$cfg_type=$cfg_type\n";
}

if (($cfg_type eq "local") && (! -d $cfg_local_path)){
    die "Can't find \$cfg_local_path ($cfg_local_path)";
}

if ($cfg_backup_style eq "backup"){
    my ($sec,$min,$hour,$mday,$mon,$year) = localtime($cur_time);
    $backup_file_base = sprintf ("%s-%4.4d.%2.2d.%2.2d.%2.2d.%2.2d.%2.2d",
		$cfg_backup_name,$year+1900,$mon+1,$mday,$hour,$min,$sec);
}else{
    $backup_file_base="$cfg_backup_name";
}

print "Creating $cfg_type $cfg_backup_style: $cfg_backup_name\n" if ($cfg_verbose == &VERB_ALL);

if ($cfg_pgp_userid ne "" && $prog_pgp ne ""){
    print "PGP: enabled\n" if ($cfg_verbose == &VERB_ALL);

#    PGP 2.6 (pgp)
#    $prog_pgp_filter="| $prog_pgp -ef $cfg_pgp_userid -z'$cfg_pgp_userid' ";
#    PGP 5.0 (pgpe)
#    $prog_pgp_filter="| $prog_pgp -f $cfg_pgp_userid";
#    GnuPG (pgp)
    $prog_pgp_filter="| $prog_pgp -v --batch -e -r $cfg_pgp_userid";
} else {
    $prog_pgp_filter="";
}

if ($prog_gzip ne ""){
    $prog_gzip_filter="| $prog_gzip";
    $arc_ext=".gz";
} else {
    $prog_gzip_filter="";
    $arc_ext="";
    
}

if (! -d "$cfg_cache_dir/$cfg_backup_name"){
    mkdir("$cfg_cache_dir/$cfg_backup_name", 0700);
}

# ---------- Activate FTP connection.

ftp_connect();

#----------- Calculate the incremental level.
if ($cfg_increment_level != 0 && $cfg_backup_style eq "backup"){
    $cur_increment_level=0;

    if ( $cfg_type eq "local"){
	opendir( DIR, "$cfg_local_path");
	while ($cur_dir = readdir DIR){
            if ($cur_dir =~ /^${cfg_backup_name}\-.*\-0\.tar${arc_ext}$/){
	        $cur_increment_level++;
	    }
	}
	closedir (DIR);

    } elsif ( $cfg_type eq "remote_ssh"){

	open (DIR, "$prog_ssh -l $cfg_remote_login $cfg_remote_host 'ls $cfg_remote_path/' |") || print "SSH connection failed: $?\n";
	while (<DIR>){
	    $cur_dir = $_;
	    if ($cur_dir =~ /${cfg_backup_name}\-.*\-0\.tar${arc_ext}$/){
	        $cur_increment_level++;
	    }
	}
	close (DIR);
    } elsif ( $cfg_type eq "remote_ftp" || $cfg_type eq "remote_ftps" ){
	foreach $cur_dir ($ftp->ls()){
	    if ($cur_dir =~ /${cfg_backup_name}\-.*\-0\.tar${arc_ext}$/){
	        $cur_increment_level++;
	    }
	}
    }
    if ($cur_increment_level >= $cfg_increment_level){
	$cfg_new_flag=1;
	$cfg_clean_flag=1;
    }
    print "Current increment number: $cur_increment_level\n" if ($cfg_verbose == &VERB_ALL);
}
################################################
#----------- Read the hash into memory.
if ( (-f "$cfg_cache_dir/$cfg_backup_name/.hash" || $cfg_type ne "local" ) && $cfg_new_flag == 0){

# Read the current hash into memory.
if ( $cfg_type eq "local"){
    rename ("$cfg_cache_dir/$cfg_backup_name/.hash", "$cfg_cache_dir/$cfg_backup_name/.hash.last");
}elsif ( $cfg_type eq "remote_ssh"){
    system ("$prog_ssh -l $cfg_remote_login $cfg_remote_host 'cat $cfg_remote_path/.hash' > $cfg_cache_dir/$cfg_backup_name/.hash.last") == 0 || print "SSH connection failed: $?\n";
} elsif ( $cfg_type eq "remote_ftp" || $cfg_type eq "remote_ftps" ){
    unlink ("$cfg_cache_dir/$cfg_backup_name/.hash.last");
    $ftp->get(".hash", "$cfg_cache_dir/$cfg_backup_name/.hash.last")|| print "FTP error, Can't GET .hash\n";
}
        $db_hashinfo = new DB_File::HASHINFO ;
        $db_hashinfo->{'cachesize'} =  DB_DEF_CACHE_SIZE;
        if (! ($dbobj_last = tie(%active_hash_last, "DB_File", "$cfg_cache_dir/$cfg_backup_name/.hash.last", O_RDWR|O_CREAT, 0644, $db_hashinfo ))){
	    print "WARNING: Error in hash, creating full backup.\n" if ($cfg_verbose >= &VERB_ERROR);
	    unlink "$cfg_cache_dir/$cfg_backup_name/.hash.last";
	    $dbobj_last = tie(%active_hash_last, "DB_File", "$cfg_cache_dir/$cfg_backup_name/.hash.last", O_RDWR|O_CREAT, 0644, $db_hashinfo )||print "Can't create or open DB File!";
	}
}

# Close the ftp connection. The next block may take much longer to execute 
# than the ftp timeout.
if ( $cfg_type eq "remote_ftp" || $cfg_type eq "remote_ftps" ){
    $ftp->quit;
}
# Create a new hash.
unlink("$cfg_cache_dir/$cfg_backup_name/.hash");
$db_hashinfo2 = new DB_File::HASHINFO ;
$db_hashinfo2->{'cachesize'} =  100000;
$dbobj_new = tie(%active_hash_new, "DB_File", "$cfg_cache_dir/$cfg_backup_name/.hash", O_RDWR|O_CREAT, 0644, $db_hashinfo2) || print "Can't create or open DB File!\n";

# Create a list of files to be placed in the archive.
open (LIST, ">$cfg_cache_dir/$cfg_backup_name/$cfg_backup_name.list")|| print "Can't create list file ($cfg_cache_dir/$cfg_backup_name/$cfg_backup_name.list).\n";
flock (LIST, 2);

# A list of file sizes.
open (LIST_SIZE, ">$cfg_cache_dir/$cfg_backup_name/$cfg_backup_name.lsize")|| print "Can't create list file ($cfg_cache_dir/$cfg_backup_name/$cfg_backup_name.lsize).\n";
flock (LIST_SIZE, 2);

# Create a directory list in the archive.
open (DIRS, ">$cfg_cache_dir/$cfg_backup_name/$cfg_backup_name.dir")|| print "Can't create list file ($cfg_cache_dir/$cfg_backup_name/$cfg_backup_name.dir).\n";
flock (DIRS, 2);

# Read the list of directories to be backed up into memory.

while(<DATA>){
    chomp;
    $cur_path = $_;
    # Allow comment at the end
    $cur_path =~ s/^([^#]+)\#?.*$/$1/;  
    # Cutting border spaces
    $cur_path =~ s/^\s*([^\s\t]?.*)$/$1/;
    $cur_path =~ s/^(.*[^\s\t])\s*$/$1/;  

    if ($cur_path =~ /^\!(.*)$/){		#  !
	push @fs_notpath, $1;

    } elsif ($cur_path =~ /^\=\~(.*)$/){	#  =~
	push @fs_mask, $1;

    } elsif ($cur_path =~ /^f\~(.*)$/){		#  f~
	push @fs_filemask, $1;

    } elsif ($cur_path =~ /^d\~(.*)$/){		#  d~
	push @fs_dirmask, $1;

    } elsif ($cur_path =~ /^\=\!(.*)$/){	#  =!
	push @fs_notmask, $1;

    } elsif ($cur_path =~ /^f\!(.*)$/){		#  f!
	push @fs_notfilemask, $1;

    } elsif ($cur_path =~ /^d\!(.*)$/){		#  d!
	push @fs_notdirmask, $1;

    } elsif ($cur_path =~ /^#/ || $cur_path =~ /^\s*$/){ # Comment
	next;

    } elsif ($cur_path =~ /[\/\w]+/){ # /dir[/file]
	 if ($cur_path =~ /^$cfg_root_path/){
	     push @fs_path, "$cur_path";
	 } else {
	    push @fs_path, "$cfg_root_path$cur_path";
	 }

    } else {
	print STDERR "Syntax error: $cur_path, ingnored.\n" if ($cfg_verbose >= &VERB_ALL);
    }
}

#--------------------------------------------------------------------
# Sequentially browse through the entire list of directories marked for backup
foreach $cur_pathitem (@fs_path){
    print "Adding $cur_pathitem....\n" if ($cfg_verbose == &VERB_ALL);
    find (\&add_to_backup, $cur_pathitem);
    chdir($cfg_root_path); # Go to the root, as find does chdir.
    print "done\n" if ($cfg_verbose == &VERB_ALL);
}
close (LIST);
close (LIST_SIZE);
close (DIRS);

#------------ Make a list of deleted files.

    open (DEL, ">$cfg_cache_dir/$cfg_backup_name/$cfg_backup_name.del")|| print "Can't create list file ($cfg_cache_dir/$cfg_backup_name/$cfg_backup_name.del).\n";
    flock (DEL, 2);
    if ($cfg_backup_style ne "hash"){
	while(($file, $key)= each(%active_hash_last)){
	    $file =~ s/\'/\'\\\'\'/g;
	    $file =~ s/^\/(.*)$/$1/;
	    print DEL "rm -rf '$file'\n";
	    $del_lines_cnt++;
	}
    }
    close(DEL);

# Write the hash to disk.
$dbobj_new->sync();
untie %active_hash_new;
untie %active_hash_last;

# Activate the FTP connection for the second time.
ftp_connect();

#------------ If only updating the hash, we write it and exit.

if ($cfg_backup_style eq "hash"){ # Only create a hash without archiving.

    if ( $cfg_type eq "local"){
	system( "cp -f $cfg_cache_dir/$cfg_backup_name/.hash $cfg_local_path/.hash") == 0 || print "Local FS copy hash failed: $?";
    } elsif ( $cfg_type eq "remote_ssh"){
	system( "cat $cfg_cache_dir/$cfg_backup_name/.hash | $prog_ssh -l $cfg_remote_login $cfg_remote_host 'cat - > $cfg_remote_path/.hash'") == 0 || print "SSH connection failed (copy hash): $?\n";
    } elsif ( $cfg_type eq "remote_ftp" || $cfg_type eq "remote_ftps" ){
	$ftp->delete(".hash");
	$ftp->put("$cfg_cache_dir/$cfg_backup_name/.hash", ".hash")|| print "Can't upload .hash to remote server via FTP\n";
    }
    exit (0);
}

#------------ Archiving and transferring to storage.
if ($list_lines_cnt == 0 && $del_lines_cnt == 0){
    print "WARNING: Nothing to backup.\n" if ($cfg_verbose >= &VERB_ALL);
    exit;
}
if ( $cfg_type eq "local"){
    
    print "Storing local backup...\n" if ($cfg_verbose == &VERB_ALL);
    if ($cfg_backup_style eq "sync"){
	if ($cfg_clean_flag == 1){ # Delete old copies
	    print "WARNING: If you really sure to delete $cfg_local_path before sync operation uncomment line 'system( \"find \$cfg_local_path ! -path '\$cfg_local_path' -maxdepth 1 -exec \$prog_rm -rf \{\} \\;\");'" if ($cfg_verbose >= &VERB_ALL);
	}

	system( "cd $cfg_local_path; sh $cfg_cache_dir/$cfg_backup_name/$cfg_backup_name.del");
	system( "$prog_tar -c -f - -T $cfg_cache_dir/$cfg_backup_name/$cfg_backup_name.list| $prog_tar -xf - -C $cfg_local_path") == 0 || print "Local FS sync failed (tar|untar): $?\n";
	system( "cd $cfg_local_path; sh $cfg_cache_dir/$cfg_backup_name/$cfg_backup_name.dir");
	system( "cp -f $cfg_cache_dir/$cfg_backup_name/.hash $cfg_local_path/$backup_file_base.hash") == 0 || print "Local FS copy failed: $?\n";

    } else {
	if ($cfg_clean_flag == 1){ # Delete old copies
	    if ($cfg_save_old_backup == 0){
		system( "$prog_rm -f $cfg_local_path/*");
	    } else {
		if (! -d "$cfg_local_path/OLD"){
		    system( "mkdir $cfg_local_path/OLD");
		}
		system( "$prog_rm -f $cfg_local_path/OLD/*");
		system( "mv -f $cfg_local_path/$cfg_backup_name* $cfg_local_path/OLD/");
	    }
	}
	system( "cp -f $cfg_cache_dir/$cfg_backup_name/$cfg_backup_name.list $cfg_local_path/$backup_file_base.list") == 0 || print "Local FS .list copy failed: $?\n";
	system( "cp -f $cfg_cache_dir/$cfg_backup_name/$cfg_backup_name.lsize $cfg_local_path/$backup_file_base.lsize") == 0 || print "Local FS .lsize copy failed: $?\n";
	system( "cp -f $cfg_cache_dir/$cfg_backup_name/$cfg_backup_name.dir $cfg_local_path/$backup_file_base.dir") == 0 || print "Local FS .dir copy failed: $?\n";
	system( "cp -f $cfg_cache_dir/$cfg_backup_name/$cfg_backup_name.del $cfg_local_path/$backup_file_base.del") == 0 || print "Local FS .del copy failed: $?\n";
	system( "cp -f $cfg_cache_dir/$cfg_backup_name/.hash $cfg_local_path/$backup_file_base.hash") == 0 || print "Local FS .hash copy failed: $?\n";

	# Processing volume partitioning
	for ($arc_block_level=0; $arc_block_level <= $#volume_position; $arc_block_level++){
	    my $tmp_list_file = crate_tmp_list($arc_block_level, $volume_position[$arc_block_level], $volume_position[$arc_block_level+1], "$cfg_cache_dir/$cfg_backup_name/$cfg_backup_name.list");
	    system( "$prog_tar -c -f - -T $tmp_list_file $prog_gzip_filter $prog_pgp_filter > $cfg_local_path/$backup_file_base-$arc_block_level.tar${arc_ext}") == 0 || print "Local FS tar backup failed: $?\n";
	}
    }

} elsif ( $cfg_type eq "remote_ssh"){
    print "Storing remote ssh backup...\n" if ($cfg_verbose == &VERB_ALL);
    if ($cfg_backup_style eq "sync"){
	if ($cfg_clean_flag == 1){ # Delete old copies
	    system( "$prog_ssh -l $cfg_remote_login $cfg_remote_host find $cfg_remote_path ! -path '$cfg_remote_path' -maxdepth 1 -exec rm -rf \{\} \\;");
	}
	system( "cat $cfg_cache_dir/$cfg_backup_name/.hash | $prog_ssh -l $cfg_remote_login $cfg_remote_host 'cat - > $cfg_remote_path/.hash'") == 0 || print "SSH connection failed (store .hash): $?\n";
	system( "cat $cfg_cache_dir/$cfg_backup_name/$cfg_backup_name.del | $prog_ssh -l $cfg_remote_login $cfg_remote_host 'cat - > $cfg_remote_path/.del'") == 0 || print "SSH connection failed (store .hash): $?\n";
	system( "cat $cfg_cache_dir/$cfg_backup_name/$cfg_backup_name.dir | $prog_ssh -l $cfg_remote_login $cfg_remote_host 'cat - > $cfg_remote_path/.dir'") == 0 || print "SSH connection failed (store .hash): $?\n";
        system("$prog_ssh -l $cfg_remote_login $cfg_remote_host '(cd $cfg_remote_path; sh .del)'");
        system( "$prog_tar -c -f - -T $cfg_cache_dir/$cfg_backup_name/$cfg_backup_name.list $prog_gzip_filter| $prog_ssh -l $cfg_remote_login $cfg_remote_host tar -xf - -C $cfg_remote_path") == 0 || print "SSH connection failed (tar): $?\n";;
        system("$prog_ssh -l $cfg_remote_login $cfg_remote_host '(cd $cfg_remote_path; sh .dir)'");


	open (DEL, "<$cfg_cache_dir/$cfg_backup_name/$cfg_backup_name.del");
	flock (DEL, 1);
	while(<DEL>){
	    chomp;
	    $cur_file = $_;
	    $cur_file =~ s/\'/\'\\\'\'/g;
    	    system("$prog_ssh -l $cfg_remote_login $cfg_remote_host rm -f '$cfg_remote_path/$cur_file'");
	}
	close(DEL);
    } else {
	if ($cfg_clean_flag == 1){ # Delete old copies

	    if ($cfg_save_old_backup == 0){
		system( "$prog_ssh -l $cfg_remote_login $cfg_remote_host rm -f $cfg_remote_path/*");
	    } else {
		system( "$prog_ssh -l $cfg_remote_login $cfg_remote_host '(if [ ! -d $cfg_remote_path/OLD ]; then mkdir $cfg_remote_path/OLD; fi)'");
		system( "$prog_ssh -l $cfg_remote_login $cfg_remote_host rm -f $cfg_remote_path/OLD/*");
		system( "$prog_ssh -l $cfg_remote_login $cfg_remote_host mv -f $cfg_remote_path/$cfg_backup_name* $cfg_remote_path/OLD/");
	    }
	}
	system( "cat $cfg_cache_dir/$cfg_backup_name/$cfg_backup_name.list | $prog_ssh -l $cfg_remote_login $cfg_remote_host 'cat - > $cfg_remote_path/$backup_file_base.list'") == 0 || print "SSH connection failed (copy .list): $?\n";
	system( "cat $cfg_cache_dir/$cfg_backup_name/$cfg_backup_name.lsize | $prog_ssh -l $cfg_remote_login $cfg_remote_host 'cat - > $cfg_remote_path/$backup_file_base.lsize'") == 0 || print "SSH connection failed (copy .lsize): $?\n";
	system( "cat $cfg_cache_dir/$cfg_backup_name/$cfg_backup_name.dir | $prog_ssh -l $cfg_remote_login $cfg_remote_host 'cat - > $cfg_remote_path/$backup_file_base.dir'") == 0 || print "SSH connection failed (copy .dir): $?\n";
        system( "cat $cfg_cache_dir/$cfg_backup_name/$cfg_backup_name.del | $prog_ssh -l $cfg_remote_login $cfg_remote_host 'cat - > $cfg_remote_path/$backup_file_base.del'") == 0 || print "SSH connection failed (copy .del): $?\n";
        system( "cat $cfg_cache_dir/$cfg_backup_name/.hash | $prog_ssh -l $cfg_remote_login $cfg_remote_host 'cat - > $cfg_remote_path/$backup_file_base.hash'") == 0 || print "SSH connection failed (copy .hash): $?\n";
	system( "cat $cfg_cache_dir/$cfg_backup_name/.hash | $prog_ssh -l $cfg_remote_login $cfg_remote_host 'cat - > $cfg_remote_path/.hash'") == 0 || print "SSH connection failed (cache .hash): $?\n";
	# Processing volume partitioning
	for ($arc_block_level=0; $arc_block_level <= $#volume_position; $arc_block_level++){
	    my $tmp_list_file = crate_tmp_list($arc_block_level, $volume_position[$arc_block_level], $volume_position[$arc_block_level+1], "$cfg_cache_dir/$cfg_backup_name/$cfg_backup_name.list");
            system( "$prog_tar -c -f - -T $tmp_list_file $prog_gzip_filter $prog_pgp_filter| $prog_ssh -l $cfg_remote_login $cfg_remote_host 'cat - > $cfg_remote_path/$backup_file_base-$arc_block_level.tar${arc_ext}'") == 0 || print "SSH connection failed (tar): $?\n";
	}
    }
} elsif ( $cfg_type eq "remote_ftp" || $cfg_type eq "remote_ftps" ){
    print "Storing remote ftp backup...\n" if ($cfg_verbose == &VERB_ALL);

    if ($cfg_backup_style eq "sync"){
	print "WARNING: Backup style 'sync' only allowed for local and remote_ssh storage.\n" if ($cfg_verbose >= &VERB_ALL);
    } else {
	if ($cfg_clean_flag == 1){ # Delete old copies
	    if ($cfg_save_old_backup == 0){
		foreach $cur_dir ($ftp->ls()){
    		    $ftp->delete($cur_dir);
		}
	    } else {
		$ftp->mkdir("$cfg_remote_path/OLD");
		$ftp->cwd("$cfg_remote_path/OLD");
		foreach $cur_dir ($ftp->ls()){
    		    $ftp->delete($cur_dir);
		}
		$ftp->cwd("$cfg_remote_path");
		foreach $cur_dir ($ftp->ls()){
		    if ($cur_dir =~ /$cfg_backup_name/){
    			$ftp->rename($cur_dir,"$cfg_remote_path/OLD/$cur_dir");
		    }
		}
		foreach $cur_dir ($ftp->ls()){
    		    $ftp->delete($cur_dir);
		}
	    }
	}
	$ftp->delete("$backup_file_base.list");
	$ftp->put("$cfg_cache_dir/$cfg_backup_name/$cfg_backup_name.list", "$backup_file_base.list") || print "Can't PUT .list file to remote FTP server\n";
	$ftp->delete("$backup_file_base.lsize");
	$ftp->put("$cfg_cache_dir/$cfg_backup_name/$cfg_backup_name.lsize", "$backup_file_base.lsize") || print "Can't PUT .lsize file to remote FTP server\n";
	$ftp->delete("$backup_file_base.dir");
	$ftp->put("$cfg_cache_dir/$cfg_backup_name/$cfg_backup_name.dir", "$backup_file_base.dir")|| print "Can't PUT .dir file to remote FTP server\n";
	$ftp->delete("$backup_file_base.del");
	$ftp->put("$cfg_cache_dir/$cfg_backup_name/$cfg_backup_name.del", "$backup_file_base.del")|| print "Can't PUT .del file to remote FTP server\n";
    $ftp->delete("$backup_file_base.hash");
    $ftp->put("$cfg_cache_dir/$cfg_backup_name/.hash", "$backup_file_base.hash")|| print "Can't PUT old .hash file to remote FTP server\n";
	$ftp->delete(".hash");
	$ftp->put("$cfg_cache_dir/$cfg_backup_name/.hash", ".hash")|| print "Can't PUT new .hash file to remote FTP server\n";

	# Processing volume partitioning
	for ($arc_block_level=0; $arc_block_level <= $#volume_position; $arc_block_level++){
	    my $tmp_list_file = crate_tmp_list($arc_block_level, $volume_position[$arc_block_level], $volume_position[$arc_block_level+1], "$cfg_cache_dir/$cfg_backup_name/$cfg_backup_name.list");
	    $ftp->delete("$backup_file_base-$arc_block_level.list");
	    $ftp->put("$tmp_list_file", "$backup_file_base-$arc_block_level.list") || print "Can't PUT .list file to remote FTP server\n";
	    $ftp->delete("$backup_file_base-$arc_block_level.tar${arc_ext}");
	    open (TAR,"$prog_tar -c -f - -T $tmp_list_file $prog_gzip_filter $prog_pgp_filter|")|| print "tar failed: $?\n";
    	    flock(TAR,1);
	    $ftp->put(*TAR, "$backup_file_base-$arc_block_level.tar${arc_ext}")|| print "Can't store backup archive to remote FTP server.\n";
	    close(TAR);
	}
    	$ftp->quit;
    }
}

if ( $cfg_type eq "remote_ftp" || $cfg_type eq "remote_ftps" ){
    $ftp->quit;
}
print "***** Backup successful complete.\n" if ($cfg_verbose == &VERB_ALL);
exit (0);


########################################
sub add_to_backup{
  my($file_name, $file_dir, $md5_checksum_stat, $checksum_stat);
  my($tmp, $stat_mode, $stat_uid, $stat_gid, $stat_size, $stat_mtime, $stat_time);
 
  $file_name  = $_;
  $file_fullpath  = $File::Find::name;
  $file_dir  = $File::Find::dir;
  $file_fullpath =~ s/^$cfg_root_path/\.\//;
  my $file_fullpath_esc = $file_fullpath;
  $file_fullpath_esc =~ s/\'/\'\\\'\'/g;

  # Create a directory list
  if ((-d "$cfg_root_path/$file_fullpath") && (! -l "$cfg_root_path/$file_fullpath")){
      if (check_path($file_dir, $file_name) == 1){
	if ($cfg_backup_style ne "hash"){
	   ($tmp, $tmp, $stat_mode, $tmp, $stat_uid, $stat_gid, $tmp, $stat_size, $tmp, $stat_mtime, $stat_time) = stat("$cfg_root_path/$file_fullpath");
	    $stat_mode = sprintf ("%04o", $stat_mode & 07777);
	    $file_fullpath_esc =~ s/^\/(.*)$/$1/;
	    $stat_uid = getpwuid($stat_uid) || $stat_uid;
	    $stat_gid = getgrgid($stat_gid) || $stat_gid;
	    my ($sec,$min,$hour,$mday,$mon,$year) = localtime($stat_time);
	    $stat_time = sprintf ("%4.4d%2.2d%2.2d%2.2d%2.2d.%2.2d",
		                   $year+1900,$mon+1,$mday,$hour,$min,$sec);
    	    print DIRS "mkdir '$file_fullpath_esc'\n";
    	    print DIRS "chmod $stat_mode '$file_fullpath_esc'\n";
    	    print DIRS "chown $stat_uid:$stat_gid '$file_fullpath_esc'\n";
    	    print DIRS "touch -t $stat_time '$file_fullpath_esc'\n";
	    $cur_backup_size += int(length($file_fullpath)/100.0 + 1)*512;
	    if ($cfg_maximum_archive_size > 0 && $cur_backup_size + 10240 >= $cfg_maximum_archive_size){
	        my $old_val = $cur_backup_size - $stat_size - int(length($file_fullpath)/100.0 + 1)*512;
		my $tmp_pos= $#volume_position+1;
	        print "Volume $tmp_pos Done. Size: $old_val\n" if ($cfg_verbose == &VERB_ALL);
		$cur_backup_size = $stat_size + int(length($file_fullpath)/100.0 + 1)*512 + 1536;
	    	push @volume_position, $list_lines_cnt;
	    }
	}
      } else {
          if ($cfg_stopdir_prune == 1){
              $File::Find::prune = 1;
              return;
	  }
      }
  # Working with files
  } elsif ((-f "$cfg_root_path/$file_fullpath") || (-l "$cfg_root_path/$file_fullpath")){
      if (check_path($file_dir, $file_name) == 1){
	  ($tmp, $tmp, $stat_mode, $tmp, $stat_uid, $stat_gid, $tmp, $stat_size, $tmp, $stat_mtime) = stat("$cfg_root_path/$file_fullpath");
	      $checksum_stat= md5_base64("$stat_mtime/$stat_size/$stat_mode/$stat_uid/$stat_gid");
	      $file_fullpath_md5 = $file_fullpath;
	  if ($cfg_time_limit != 0 && $cur_time - $cfg_time_limit > $stat_mtime){
	      print "Time limit: $cur_time - $cfg_time_limit > $stat_mtime, file $file_fullpath ignored.\n" if ($cfg_verbose == &VERB_ALL);
	      next;
	  }
	  if ($cfg_size_limit != 0 && $cfg_size_limit < $stat_size){
	      print "Size limit: $cfg_size_limit < $stat_size, file $file_fullpath ignored.\n" if ($cfg_verbose == &VERB_ALL);
	      next;
	  }

	  if (($cfg_checksum eq "md5") && (! -l "$cfg_root_path/$file_fullpath")){
	      ($md5_checksum_stat, $tmp) = split(/\s+/, `$prog_md5sum '$cfg_root_path/$file_fullpath_esc'`);
	      $active_hash_new{$file_fullpath_md5} = "$checksum_stat/$md5_checksum_stat";
	      check_update($file_fullpath, "$checksum_stat/$md5_checksum_stat", $file_fullpath_md5, $stat_size);
	  } else {
	      $active_hash_new{$file_fullpath} = $checksum_stat;
	      check_update($file_fullpath, $checksum_stat, $file_fullpath, $stat_size);
	  }
      }
  }
}

###############################################
# Check if the file has changed or not, if yes, update the log.
sub check_update{
     my ($file, $checksum, $filesum, $stat_size) = @_;
    
    if ( $active_hash_last{$filesum} ne $checksum){
	if ($cfg_backup_style ne "hash"){
		$file =~ s/^\/(.*)$/$1/;
	        print LIST "$file\n";
		
	    # Handling the case of splitting giant archives.
		if (-l "/$file"){
		    $stat_size = 0;
		}
	        $cur_backup_size += $stat_size + int(length($file)/100.0 + 1)*512;
	        if ($cfg_maximum_archive_size > 0 && $cur_backup_size + 10240 >= $cfg_maximum_archive_size){
	        my $old_val = $cur_backup_size - $stat_size - int(length($file)/100.0 + 1)*512;
			my $tmp_pos= $#volume_position+1;
	        print "Volume $tmp_pos Done. Size: $old_val\n" if ($cfg_verbose == &VERB_ALL);
	        $cur_backup_size = $stat_size + int(length($file)/100.0 + 1)*512 + 1536;
	        push @volume_position, $list_lines_cnt;
	        print LIST_SIZE "$stat_size\t$file\t$tmp_pos\n";
	  }

	}
	$list_lines_cnt++;
    }
    delete $active_hash_last{$filesum};
    if (defined $dbobj_last){
	$dbobj_last->del($filesum);
    }
}

###############################################
# 0 - don't add a file
# 1 - add file

sub check_path {
    my ($dir_name, $file_name) = @_;
    my ($item, $path);
    
    $path = "$dir_name/$file_name";

    foreach $item (@fs_notmask){
	if ($path =~ /$item/){
	    return 0;
	}
    }

    foreach $item (@fs_notfilemask){
	if ($file_name =~ /$item/){
	    return 0;
	}
    }

    foreach $item (@fs_filemask){
	if ($file_name =~ /$item/){
	    return 1;
	}
    }

    foreach $item (@fs_notdirmask){
	if ($dir_name =~ /$item/){
	    return 0;
	}
    }

    foreach $item (@fs_mask){
	if ($path =~ /$item/){
	    return 1;
	}
    }

    foreach $item (@fs_dirmask){
	if ($dir_name =~ /$item/){
	    return 1;
	}
    }

    foreach $item (@fs_notpath){
	if (($dir_name eq $item) || ($path eq $item) || ($dir_name =~ /^$item\//)){
	    return 0;
	}
    }

    return 1;
}
###############################################
# Establish a connection to the remote server via FTP.

sub ftp_connect{
    if ( $cfg_type eq "remote_ftp"){
	    $ftp = Net::FTP->new($cfg_remote_host, Timeout => 30, Debug => 0,  Passive => $cfg_remote_ftp_mode) || die "Can't connect to ftp server.\n";
	    $ftp->login($cfg_remote_login, $cfg_remote_password) || die "Can't login to ftp server.\n";
	    $ftp->cwd($cfg_remote_path) || $ftp->mkdir("$cfg_remote_path") || die "Path $cfg_remote_path not found on ftp server.\n";
	    $ftp->binary();    
    }
	elsif ( $cfg_type eq "remote_ftps"){
        $ftp = Net::FTPSSL->new($cfg_remote_host, Encryption => EXP_CRYPT, Timeout => 30, Debug => 0, Croak => 0) || die "Can't connect to ftps server.\n";
        $ftp->login($cfg_remote_login, $cfg_remote_password) || die "Can't login to ftps server.\n";
        $ftp->cwd($cfg_remote_path) || $ftp->mkdir("$cfg_remote_path") || die "Path $cfg_remote_path not found on ftps server.\n";
        $ftp->binary();
	}
}
###############################################
# Creating a list of files to be placed in a specific volume of a multi-volume archive.

sub crate_tmp_list{
	my ($arc_block_level, $position1, $position2, $full_list_path) = @_;
	my ($tmp_list_path, $pos_counter);

    if ($arc_block_level == 0 && $position1 == 0 && $position2 eq ''){
	$tmp_list_path = $full_list_path;
    } else {
	$pos_counter = 0;
	$tmp_list_path = "$full_list_path.$arc_block_level";
	open(FULL_LIST, "<$full_list_path")|| die "Can't open full list $full_list_path\n";
	flock(FULL_LIST, 1);
	open(TMP_LIST, ">$tmp_list_path")|| die "Can't create temp list $tmp_list_path\n";
	flock(TMP_LIST, 2);
	while(<FULL_LIST>){
	    if (($pos_counter >= $position1) && ($pos_counter < $position2 || $position2 eq '')){
		print TMP_LIST $_;
	    }
	    $pos_counter++;
	}
	close(TMP_LIST);
	close(FULL_LIST);
    }
    return $tmp_list_path;
}
###############################################
###############################################

__END__

=head1 NAME

fsbackup - file system backup and synchronization utility. 

=head1 SYNOPSIS

    fsbackup.pl [options] <configuration file>

=head1 DESCRIPTION

C<fsbackup.pl> is a incremental backup creation utility. 
C<fsbackup.pl> support backup compression and encryption. Backup can be stored
on local file system and on remote host stored over SSH or FTP. Some addition 
scripts allow backups SQL tables from PostgreSQL and MySQL (C<pgsql_backup.sh> 
and C<mysql_backup.sh>)), save system configuration files and list of installed 
packages (C<sysbackup.sh>). 
Backuped with C<fsbackup.pl> files can be recovered by script C<fsrestore.sh>,
backuped with C<sysbackup.sh> system packeges can be reinstalled by C<sysrestore.sh>

=head1 OPTIONS

The following command-line options can be used with C<fsbackup.pl>:

=over

=item C<-n>

Create new backup without checking files in previously stored hash.

=item C<-f>

Create full backup, like as C<-n> option.

=item C<-h>

Only rebuild hash, no storing files in backup archive.

=item C<-c>

Clean incremental backup storage and create new full backup without checking
$cfg_increment_level config parameter.

=back

=head1 ADDITION SCRIPTS

=over

=item C<create_backup.sh>

Backup planner running from C<crontab>. For example: 

18 4 * * * /usr/local/fsbackup/create_backup.sh

=item C<install.pl>

Script to install fsbackup package and some required perl modules.

=item C<fsbackup.pl>

File system backup utility.

=item C<cfg_example>

Example of configuration file.

=item C<scripts/pgsql_backup.sh>

=item C<scripts/mysql_backup.sh>

Script for backup SQL tables from PostreSQL and MySQL.

=item C<scripts/sysbackup.sh>

Script for store system configuration files and information about installed
packages.

=item C<scripts/fsrestore.sh>

Script for restore files backuped by C<fsbackup.pl>.

=item C<scripts/sysrestore.sh>

Script for reinstall packages stored by C<sysbackup.sh>.

=item C<scripts/mount-windows-share.sh>

Script for mount Windows shared directory by C<sysbackup.sh>.

=back

=head1 CONFIGURATION FILE

=over

=item B<$cfg_backup_name> = 'test_host'

Name of backup, single word.

=item B<$cfg_cache_dir> = '/usr/local/fsbackup/cache'

Path of internal cache directory for local backup method.

=item B<$prog_md5sum> = 'md5sum -b'

=item B<$prog_tar> = 'tar'

=item B<$prog_ssh> = 'ssh'

=item B<$prog_rm> = 'rm'

=item B<$prog_gzip> = 'gzip'

=item B<$prog_pgp> = 'gpg'

Full path of some external program running from C<fsbackup.pl>.
B<$prog_gzip = ''> - not use compression, B<$prog_pgp = ''> - not use 
encryption.

=item B<$cfg_checksum> = 'timesize'

File checksum method: 

timesize - checksum of file attributes (default, best speed) 

md5      - checksum of file attributes + MD5 checksum of file content.

=item B<$cfg_backup_style> = 'backup'

Backup style:

backup - incremental backup (copy only new and changed files).

full_backup - full backup (copy all files).	

sync - file tree synchronization.

hash - hash creation without storing archive (spying for new or changed files).

=item B<$cfg_increment_level> = 7

Incremental level (after how many incremental copy make full refresh of backup)

=item B<$cfg_type> = 'remote_ssh'

Type of backup storage:

    local  - store backup on local file system.
    remote_ssh - store backup on remote host over SSH connection.
    remote_ftp - store backup on remote FTP server.
    remote_ftps - store backup on remote FTPS server.

=item B<$cfg_remote_host> = 'backup-server.test.com'

=item B<$cfg_remote_login> = 'backup_login'

=item B<$cfg_remote_path> = '/home/backup_login/backup'

Connection parameters for remote_ssh storage type.

=item B<$cfg_remote_password> = 'Test1234'

Password of remote login for remote_ftp storage type.

=item B<$cfg_remote_ftp_mode> = 0

FTP transfer mode.  0 - Active mode, 1 - Passive mode.

=item B<$cfg_local_path> = '/var/backup/'

Path of directory to store backup on local file system for local storage type.

=item B<$cfg_time_limit> = 0

Limit of file creation time in days. If not 0, don't backup files created or 
modified later then $cfg_time_limit (days).

=item B<$cfg_size_limit> = 0

Limit of maximum file size. If not 0, don't backup files witch size more then 
$cfg_time_limit kilobytes.

=item B<$cfg_root_path> = '/'

Root path for initial chdir.

=item B<$cfg_pgp_userid> = ''

Name of user in public key ring with public key will be used for PGP encryption.
Not use encryption if not set.

=item B<$cfg_verbose> = 3

Verbose level.

    0	- Silent mode, suspend all output, except fatal configuration errors.
    1	- Output errors and warnings.
    2	- Output all the  available  data.

=item B<$cfg_save_old_backup> = 1

Save previous backup to OLD directory before rotation or before storing full backup.

    0 - don't save old backup
    1 - save old backup.

=item B<$cfg_maximum_archive_size> = 0

Size of maximum size (in KiloBytes) of single unpacked archive file (0 - unlimited file size).

=item B<$cfg_stopdir_prune> = 0

Recursive review of the prohibited directories.
    0 - Recursively to view all contents of directories marked for backup, including contents of directories prohibited by '!', '!d' and '=! rules.
    1 - not use a recursive entrance to directory prohibited for backup (speed is increased, reduces flexibility of customization).

=item B<__DATA__> - list of backuped path and regexp mask.

    /dir[/file] - backup file or directory.
    !/dir[/file] - NOT include this file or directory to backup.
    # - ignore this line.

Mask:

    =~ - regexp mask for include file or directory to backup.
    f~ - regexp file mask for include file to backup.
    d~ - regexp directory mask for include directory to backup.
    =! - regexp mask for NOT include file or directory to backup.
    f! - regexp file mask for NOT include file to backup.
    d! - regexp directory mask for NOT include directory to backup.


Operation priority:

    1. =!
    2. f!
    3. f~
    4. d!
    5. =~
    6. d~
    7. !path
    8. path

=back

=head1 AUTHORS

kraloveckey

=cut