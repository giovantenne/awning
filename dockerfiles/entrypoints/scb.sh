#!/bin/bash
set -euo pipefail

# Awning v2: Static Channel Backup (SCB) entrypoint
# Watches LND's channel.backup file and pushes changes to a GitHub repository
# Uses inotifywait for efficient file monitoring with exponential backoff on failures

SCB_SOURCE="/lnd/data/chain/bitcoin/mainnet/channel.backup"
BACKUP_DIR="/data/backups"
MAX_RETRY_DELAY=300  # 5 minutes max between retries
HEARTBEAT_FILE="/tmp/scb_heartbeat"
SSH_KEY=""

log() { echo "[SCB] $(date '+%H:%M:%S') $*"; }
heartbeat() { date +%s > "${HEARTBEAT_FILE}"; }

# --- SSH key setup ---
mkdir -p /data/.ssh
if [ -f /data/.ssh/id_ed25519 ]; then
    SSH_KEY="/data/.ssh/id_ed25519"
elif [ -f /data/.ssh/id_rsa ]; then
    SSH_KEY="/data/.ssh/id_rsa"
else
    log "Generating SSH key..."
    ssh-keygen -t ed25519 -f /data/.ssh/id_ed25519 -N "" -q
    SSH_KEY="/data/.ssh/id_ed25519"
fi

if [ ! -f "${SSH_KEY}.pub" ]; then
    ssh-keygen -y -f "${SSH_KEY}" > "${SSH_KEY}.pub" 2>/dev/null || true
fi

# known_hosts bootstrap (avoids interactive prompt)
touch /data/.ssh/known_hosts
if ! ssh-keygen -F github.com -f /data/.ssh/known_hosts >/dev/null 2>&1; then
    log "Fetching github.com host keys..."
    delay=2
    while ! ssh-keyscan -t ed25519,ecdsa,rsa github.com >> /data/.ssh/known_hosts 2>/dev/null; do
        log "ssh-keyscan failed, retrying in ${delay}s..."
        sleep "${delay}"
        delay=$(( delay * 2 > MAX_RETRY_DELAY ? MAX_RETRY_DELAY : delay * 2 ))
    done
fi

# Configure SSH for git operations
export GIT_SSH_COMMAND="ssh -i ${SSH_KEY} -o UserKnownHostsFile=/data/.ssh/known_hosts -o StrictHostKeyChecking=yes"

log "--- SSH Public Key (add this to your GitHub repo as a deploy key with write access) ---"
cat "${SSH_KEY}.pub"
log "---"

# --- Git config ---
git config --global user.email "awning@backup"
git config --global user.name "Awning SCB"

# --- Clone or update repo ---
setup_repo() {
    if [ -z "${SCB_REPO:-}" ]; then
        log "SCB_REPO not set, channel backup disabled. Exiting."
        exit 0
    fi

    if [ ! -d "${BACKUP_DIR}/.git" ]; then
        log "Cloning backup repository..."
        local delay=5
        while ! git clone "${SCB_REPO}" "${BACKUP_DIR}" 2>&1; do
            log "Clone failed, retrying in ${delay}s..."
            sleep "${delay}"
            delay=$(( delay * 2 > MAX_RETRY_DELAY ? MAX_RETRY_DELAY : delay * 2 ))
        done
    else
        log "Updating existing backup repository..."
        cd "${BACKUP_DIR}"
        git fetch origin --prune 2>&1 || true

        # Handle both initialized and empty remotes without noisy fatal errors.
        if git show-ref --verify --quiet refs/remotes/origin/main; then
            git reset --hard origin/main 2>&1 || true
        elif git show-ref --verify --quiet refs/remotes/origin/master; then
            git reset --hard origin/master 2>&1 || true
        else
            log "Remote repository is empty or has no default branch yet."
        fi
    fi
}

# --- Push backup ---
push_backup() {
    local delay=5
    cd "${BACKUP_DIR}"

    cp "${SCB_SOURCE}" "${BACKUP_DIR}/channel.backup"

    git add channel.backup
    if git diff --cached --quiet; then
        log "No changes to commit"
        return 0
    fi

    git commit -m "SCB $(date +"%Y-%m-%d %H:%M:%S")"

    while ! git push origin HEAD 2>&1; do
        log "Push failed, retrying in ${delay}s..."
        sleep "${delay}"
        delay=$(( delay * 2 > MAX_RETRY_DELAY ? MAX_RETRY_DELAY : delay * 2 ))
    done

    log "Backup pushed successfully"
}

# --- Main loop ---
setup_repo
heartbeat

log "Watching for channel.backup changes..."
while true; do
    if [ -f "${SCB_SOURCE}" ]; then
        heartbeat
        inotifywait -q -e modify,create "${SCB_SOURCE}"
        log "channel.backup changed, backing up..."
        push_backup || log "WARNING: Backup failed, will retry on next change"
        heartbeat
    else
        log "Waiting for LND to create channel.backup..."
        heartbeat
        sleep 30
    fi
done
