#!/usr/bin/env bash
#
# This script mounts FTPS share.
# The fsbackup configs must have parameters:
#  $cfg_type = "local";
#  $cfg_local_path = "/usr/local/fsbackup/archive";
#
# Need curlftpfs installed. Require:
#   * apt install curlftpfs
#

# FTPS host settings
FTPS_HOST=ftps.dns.com
FTPS_SHARE=BACKUP
FTPS_USER=backup
FTPS_PASS=somepassword
FTPS_CHECK_PORT=21

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

echo "Check and wait availability FTPS shared directory at '$FTPS_HOST:$FTPS_CHECK_PORT'"
nc -z $FTPS_HOST $FTPS_CHECK_PORT
res=$?

# Wait while FTPS is up
while [ $res -ne 0 ]
do
        nc -z $FTPS_HOST $FTPS_CHECK_PORT
        res=$?

        # Sleep for waiting up all services
        # and don't annoy by checks very often
        sleep 300
done

# Check if share already mounted
if [ -n "`/bin/df -h | egrep \"$FTPS_HOST:$FTPS_SHARE\"`" ]
then
	echo "Error!  '$FTPS_HOST:$FTPS_SHARE' already mounted (check mounts). Exit."
	exit 2
fi

echo "Ok, try to mount..."

if curlftpfs -o allow_other,ssl $FTPS_USER:$FTPS_PASS@$FTPS_HOST:$FTPS_SHARE $LOCAL_MNT_DIR
then
	echo "Share mount success. Now beginning backup."

	sleep 1
	exit 0
else

	echo "Fail mount $FTPS_HOST:$FTPS_SHARE share. Exit."
	exit 1
fi