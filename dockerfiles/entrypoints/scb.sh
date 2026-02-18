#!/bin/bash
set -euo pipefail

# Awning v2: Static Channel Backup (SCB) entrypoint
# Watches LND's channel.backup file and pushes changes to a GitHub repository
# Uses inotifywait for efficient file monitoring with exponential backoff on failures

SCB_SOURCE="/lnd/data/chain/bitcoin/mainnet/channel.backup"
BACKUP_DIR="/data/backups"
MAX_RETRY_DELAY=300  # 5 minutes max between retries

log() { echo "[SCB] $(date '+%H:%M:%S') $*"; }

# --- SSH key setup ---
if [ ! -f /data/.ssh/id_ed25519 ]; then
    log "Generating SSH key..."
    mkdir -p /data/.ssh
    ssh-keygen -t ed25519 -f /data/.ssh/id_ed25519 -N "" -q
fi

# GitHub host keys (avoids interactive prompt)
if [ ! -f /data/.ssh/known_hosts ]; then
    mkdir -p /data/.ssh
    cat > /data/.ssh/known_hosts <<'KEYS'
github.com ssh-ed25519 <REDACTED>
github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=
github.com ssh-rsa <REDACTED>
KEYS
fi

log "--- SSH Public Key (add this to your GitHub repo as a deploy key with write access) ---"
cat /data/.ssh/id_ed25519.pub
log "---"

# --- Git config ---
git config --global user.email "awning@backup"
git config --global user.name "Awning SCB"

# --- Clone or update repo ---
setup_repo() {
    if [ -z "${SCB_REPO:-}" ]; then
        log "ERROR: SCB_REPO environment variable not set"
        exit 1
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
        git fetch origin 2>&1 || true
        git reset --hard origin/main 2>&1 || true
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

    while ! git push origin main 2>&1; do
        log "Push failed, retrying in ${delay}s..."
        sleep "${delay}"
        delay=$(( delay * 2 > MAX_RETRY_DELAY ? MAX_RETRY_DELAY : delay * 2 ))
    done

    log "Backup pushed successfully"
}

# --- Main loop ---
setup_repo

log "Watching for channel.backup changes..."
while true; do
    if [ -f "${SCB_SOURCE}" ]; then
        inotifywait -q -e modify,create "${SCB_SOURCE}"
        log "channel.backup changed, backing up..."
        push_backup || log "WARNING: Backup failed, will retry on next change"
    else
        log "Waiting for LND to create channel.backup..."
        sleep 30
    fi
done
