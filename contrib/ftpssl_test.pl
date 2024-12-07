#!/usr/bin/perl

use Net::FTPSSL;

$ftp = Net::FTPSSL->new("FTPS_HOST", Encryption => EXP_CRYPT, Timeout => 120, Debug => 2, Croak => 0, SSL_version => 'TLSv12') || die "Can't connect to ftp server.\n";
$ftp->login("FTPS_USER", "FTPS_PASSWORD") || die "Can't login to ftp server.\n";
$ftp->cwd("/FTPS_PATH") || $ftp->mkdir("/FTPS_PATH") || die "Path /FTPS_PATH not found on ftp server.\n";
$ftp->pwd();
$ftp->binary();
$ftp->list();
$ftp->put("test.txt");

---

#!/usr/bin/perl

use warnings;
use Net::FTPSSL;

# FTP Server credentials
my $ftp_server   = "FTPS_HOST"; # Replace with your server address
my $ftp_user     = "FTPS_USER";       # Replace with your FTP username
my $ftp_password = "FTPS_PASSWORD";       # Replace with your FTP password

# Create a new FTPS connection (Explicit mode)
my $ftps = Net::FTPSSL->new(
    $ftp_server,
    Encryption => EXP_CRYPT,    # Explicit FTPS
    Port       => 21,             # Default FTP control port
    Debug      => 1,              # Enable debug output
    Passive    => 1               # Enable Passive Mode
) or die "Failed to connect to $ftp_server: $@";

print "Connected to $ftp_server\n";

# Login to the server
$ftps->login($ftp_user, $ftp_password)
    or die "Failed to login: " . $ftps->last_message();

print "Login successful\n";

# Change to a specific directory (optional)
my $remote_dir = "/fb-bt";
$ftps->cwd($remote_dir)
    or die "Failed to change directory: " . $ftps->last_message();

print "Changed directory to $remote_dir\n";

# Get a directory listing
my @files = $ftps->nlst()
    or die "Failed to list directory contents: " . $ftps->last_message();

print "Directory listing:\n";
foreach my $file (@files) {
    print " - $file\n";
}

# Close the connection
$ftps->quit();
print "Connection closed\n";