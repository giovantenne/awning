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

# check if id_rsa.pub is present
if [ ! -f .ssh/id_rsa.pub ]; then
  echo "id_rsa.pub missing. Creating one..."
  ssh-keygen -t rsa -f /data/.ssh/id_rsa -b 4096 -N ""
  #
  # adding github public key fingerprints
  echo "github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=
github.com ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCj7ndNxQowgcQnjshcLrqPEiiphnt+VTTvDP6mHBL9j1aNUkY4Ue1gvwnGLVlOhGeYrnZaMgRK6+PKCUXaDbC7qtbW8gIkhL7aGCsOr/C56SJMy/BCZfxd1nWzAOxSDPgVsmerOBYfNqltV9/hWCqBywINIR+5dIg6JTJ72pcEpEjcYgXkE2YEFXV1JHnsKgbLWNlhScqb2UmyRkQyytRLtL+38TGxkxCflmO+5Z8CSSNY7GidjMIZ7Q4zMjA2n1nGrlTDkzwDCsw+wqFPGQA179cnfGWOWRVruj16z6XyvxvjJwbz0wQZ75XK5tKSb7FNyeIEs4TT4jk+S4dhPeAUC5y+bDYirYgM4GC7uEnztnZyaVWQ7B381AK4Qdrwt51ZqExKbQpTUNn+EjqoTwvqNj4kqx5QUCI0ThS/YkOxJCXmPUWZbhjpCg56i+2aB6CmK2JGhn57K5mj0MNdBXA4/WnwH6XoPWJzK5Nyu2zB3nAZp+S5hpQs+p1vN1/wsjk=" >> /data/.ssh/known_hosts
fi

echo "-----------------------"
cat .ssh/id_rsa.pub
echo "-----------------------"

# check if repo is present
if [ ! -d $REMOTE_BACKUP_DIR ]; then
  while ! git clone $SCB_REPO $REMOTE_BACKUP_DIR
  do
    sleep 30
  done
else
  cd $REMOTE_BACKUP_DIR || exit
  git pull
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
      echo "LND not ready. Waiting 30 seconds..."
      sleep 30
    fi

  done
}

run




