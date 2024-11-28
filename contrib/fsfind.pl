#!/usr/bin/perl

# Script to search for files in archives created by the fsbackup program

#############################################

my $type="list";
my $extract=0;
$cfg_cache_dir = "./";
my $findfile;

# Processing command line parameters
while (@ARGV){
    $arg= shift (@ARGV);
    if 	  ($arg eq "-h" or $arg eq "--help") {&help}		
    elsif ($arg eq "-d" or $arg eq "--del")  { $type="del"}	
    elsif ($arg eq "-c" or $arg eq "--cfgfile")  {
	    $config = shift (@ARGV);
	    require "$config" if ( -f $config );
    	}
    elsif ($arg eq "-p" or $arg eq "--path")  {
	$cfg_cache_dir=shift (@ARGV);
	}
    elsif ($arg eq "-m" or $arg eq "--mask")  {	
	$cfg_backup_name = shift (@ARGV);
	}
    else {$findfile="$arg"}
}

if ($findfile eq '') {
    print "File not specified\n";
    &help;
}

if ( ! -d $cfg_cache_dir ) {print "Directory: $cfg_cache_dir not found\n"; &help}

@files=sort {$b cmp $a} glob("$cfg_cache_dir/$cfg_backup_name*.$type" );
if ($#files <0) {
    print "In the directory $cfg_cache_dir no files found $cfg_backup_name.$type\n";
    exit;    
}

# Translate regular expressions
$findfile=~ s/\./\\\./g;
$findfile=~ s/\*/\.\+/g;    
$findfile=~ s/\_/\./g;        

# Searching and printing the results
foreach $f (@files){
    open (FILE, "$f");
    $tmp ="$f\n";

    while (<FILE>){
	chomp;
	if (/$findfile/i){ $tmp.="\t$_\n";}
    }
    
    if ($tmp ne "$f\n" ){ 
	$tmp=~ s/^$cfg_cache_dir\///;
    	print "$tmp\n"; 
    }		
}

exit;

sub help{
print qq|Usage: fsfind  [OPTION]...  FILE
Searches for FILE in archives created in fsbackup, regular expressions are allowed 
in the filename:
  * any number of any characters
  _ any single character

Options:
  -d, --del             search for deleted files
  -p, --path PATH       path to the directory with archives, if not specified,
                        then the search is performed in the current directory
  -m, --mask            mask for file names of archives in which the search is performed. 
                        search
  -c, --cfgfile FILE    fsbackup configuration file in which is specified 
                        directory with archives and archive file name
  -h, --help            output this prompt and exit

|;
    exit;                                                                     
}