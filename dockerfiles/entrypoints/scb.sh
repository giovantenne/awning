#!/bin/bash

# Safety bash script options
# # -e causes a bash script to exit immediately when a command fails
# # -u causes the bash shell to treat unset variables as an error and exit immediately.
# set -eu
#
# # The script waits for a change in /data/lnd/data/chain/bitcoin/mainnet/channel.backup.
# # When a change happens, it creates a backup of the file locally
# #   on a storage device and/or remotely in a GitHub repo
#
# # By default, both methods are used. If you do NOT want to use one of the
# #   method, replace "true" by "false" in the two variables below:
cd /data
git config --global user.email "awning@dummyemail.com" 
git config --global user.name "Awning"

REMOTE_BACKUP_ENABLED=true
LOCAL_BACKUP_ENABLED=false

SCB_SOURCE_FILE="/lnd/data/chain/bitcoin/mainnet/channel.backup"
LOCAL_BACKUP_DIR="/mnt/static-channel-backup-external"
REMOTE_BACKUP_DIR="/data/backups"

# check if repo is present
if [ ! -d $REMOTE_BACKUP_DIR ]; then
  echo "pre clone"
  while ! git clone $SCB_REPO $REMOTE_BACKUP_DIR
  do
    sleep 30
  done
fi;

# Safety bash script options
# -e causes a bash script to exit immediately when a command fails
# -u causes the bash shell to treat unset variables as an error and exit immediately.
set -eu

# The script waits for a change in /data/lnd/data/chain/bitcoin/mainnet/channel.backup.
# When a change happens, it creates a backup of the file locally
#   and remotely in a GitHub repo

# By default, both methods are used. If you do NOT want to use one of the
#   method, replace "true" by "false" in the two variables below:

# Remote backup function
run_remote_backup_on_change () {
  echo "Entering Git repository..."
  cd $REMOTE_BACKUP_DIR || exit
  echo "Making a timestamped copy of channel.backup..."
  echo "$1"
  cp "$SCB_SOURCE_FILE" "$1"
  echo "Committing changes and adding a message"
  git add .
  git commit --allow-empty -m "Static Channel Backup $(date +"%Y%m%d-%H%M%S")"
  echo "Pushing changes to remote repository..."
  git push --set-upstream origin main
  echo "Success! The file is now remotely backed up!"
}


# Monitoring function
run () {
  while true; do

    if [ -f $SCB_SOURCE_FILE ]; then
      inotifywait $SCB_SOURCE_FILE
      echo "channel.backup has been changed!"

      LOCAL_BACKUP_FILE="$LOCAL_BACKUP_DIR/channel-$(date +"%Y%m%d-%H%M%S").backup"
      REMOTE_BACKUP_FILE="$REMOTE_BACKUP_DIR/channel.backup"

      if [ "$LOCAL_BACKUP_ENABLED" == true ]; then
        echo "Local backup is enabled"
        run_local_backup_on_change "$LOCAL_BACKUP_FILE"
      fi

      if [ "$REMOTE_BACKUP_ENABLED" == true ]; then
        echo "Remote backup is enabled"
        run_remote_backup_on_change "$REMOTE_BACKUP_FILE"
      fi
    else
      sleep 5
    fi

  done
}

run




