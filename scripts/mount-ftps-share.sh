#!/usr/bin/env bash
#
# This script mounts FTPS share.
# The fsbackup configs must have parameters:
#  $cfg_type = "local";
#  $cfg_local_path = "/usr/local/fsbackup/archive";
#
# Need rclone installed. Require:
#   * curl https://rclone.org/install.sh | bash
#   * apt install fuse3
#

# FTPS host settings
FTPS_REMOTE_NAME="lsftp" # Name of the rclone remote
FTPS_HOST=ftps.dns.com
FTPS_SHARE=/BACKUP
FTPS_USER=backupusr
FTPS_PASS=somepassword
FTPS_CHECK_PORT=21

RCLONE_CONFIG_FILE="$HOME/.config/rclone/rclone.conf"  # Path to rclone config file

LOCAL_MNT_DIR=/usr/local/fsbackup/archive

# Function to check if rclone remote exists
function remote_exists() {
    rclone listremotes | grep -q "^${FTPS_REMOTE_NAME}:$"
}

# Function to create rclone remote
function create_remote() {
    echo "Creating rclone remote '$FTPS_REMOTE_NAME'..."
    rclone config create "$FTPS_REMOTE_NAME" ftp \
        host "$FTPS_HOST" \
        user "$FTPS_USER" \
        pass "$FTPS_PASS" \
        --obscure \
        > /dev/null

    # Add additional variables to the remote configuration
    echo "Adding additional variables to the remote configuration..."
    sed -i "/^\[${FTPS_REMOTE_NAME}\]/a explicit_tls = true" "$RCLONE_CONFIG_FILE"
    sed -i "/^\[${FTPS_REMOTE_NAME}\]/a disable_mlsd = false" "$RCLONE_CONFIG_FILE"
    sed -i "/^\[${FTPS_REMOTE_NAME}\]/a disable_tls13 = true" "$RCLONE_CONFIG_FILE"
}

# ------------------------------------------------
if [ _"$1" = _"umount" ]; then
        echo "Ok. Backup done. Unmount share and exit..."
        if ! umount -l $LOCAL_MNT_DIR ; then
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

# Main script logic
if remote_exists; then
        echo "rclone profile '$FTPS_REMOTE_NAME' already exists."
else
        create_remote
fi

# Check if share already mounted
if [ -n "`/bin/df -h | egrep \"$FTPS_REMOTE_NAME:\"`" ]
then
        echo "Error! '$FTPS_HOST:$FTPS_SHARE' already mounted (check mounts). Exit."
        exit 2
fi

echo "Ok, try to mount..."

if rclone mount $FTPS_REMOTE_NAME:$FTPS_SHARE $LOCAL_MNT_DIR --vfs-cache-mode writes --daemon
then
        echo "Share mount success. Now beginning backup :)"

        sleep 1
        exit 0
else

        echo "Fail mount $FTPS_HOST:$FTPS_SHARE share. Exit :("
        exit 1
fi