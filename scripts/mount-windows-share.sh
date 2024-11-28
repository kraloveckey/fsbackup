#!/usr/bin/env bash
#
# This script mounts Windows share.
# The fsbackup configs must have parameters:
#  $cfg_type = "local";
#  $cfg_local_path = "/usr/local/fsbackup/archive";
#
# Need Samba installed with CIFS and netcat support. Require:
#   * apt install cifs-utils smbclient netcat-traditional
#

# Windows host settings
SMB_HOST=192.168.1.44
SMB_SHARE=BACKUP
SMB_USER=backup
SMB_PASS=somepassword
SMB_CHECK_PORT=135

LOCAL_MNT_DIR=/usr/local/fsbackup/archive

# ------------------------------------------------
if [ _"$1" = _"umount" ]; then
        echo "Ok. Backup done. Unmount share and exit..."
        if ! umount $LOCAL_MNT_DIR ; then
                echo "Fail umount share '$LOCAL_MNT_DIR'."
                exit 1
        fi

        echo "Umount '$LOCAL_MNT_DIR' success."
        exit 0
fi

# ------------------------------------------------

echo "Check and wait availability Windows shared directory at '$SMB_HOST:$SMB_CHECK_PORT'"
nc -z $SMB_HOST $SMB_CHECK_PORT
res=$?

# Wait while SMB is up
while [ $res -ne 0 ]
do
        nc -z $SMB_HOST $SMB_CHECK_PORT
        res=$?

        # Sleep for waiting up all services on Windows
        # and don't annoy by checks very often
        sleep 300
done

# Check if share already mounted
if [ -n "`/bin/df -h | egrep \"//$SMB_HOST/$SMB_SHARE\"`" ]
then
	echo "Error!  '//$SMB_HOST/$SMB_SHARE' already mounted (check mounts). Exit."
	exit 2
fi

echo "Sleep 20sec for waiting up all services on windows PC"
sleep 20
echo "Ok, try to mount..."

if mount.cifs //$SMB_HOST/$SMB_SHARE $LOCAL_MNT_DIR -o user=$SMB_USER,pass=$SMB_PASS
then
	echo "Share mount success. Now begining backup."

	sleep 1
	exit 0
else

	echo "Fail mount //$SMB_HOST/$SMB_SHARE share. Exit."
	exit 1
fi