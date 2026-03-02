#!/bin/bash
# Domain helpers: service status and sync derivation.
# Depends on: lib/docker.sh (bitcoin_cli), jq, awk

# Return bitcoin getblockchaininfo JSON, empty on failure.
domain_bitcoin_blockchain_info() {
    bitcoin_cli getblockchaininfo 2>/dev/null || true
}

# Parse blockchaininfo JSON and print tab-separated fields:
# blocks headers progress_pct size_gb initial_block_download
# Returns non-zero when input is empty/invalid.
# Uses a single jq invocation (instead of 5 separate calls) to minimise
# subprocess overhead — especially important when jq runs via Docker fallback.
domain_parse_bitcoin_sync_snapshot() {
    local info="$1"
    [[ -n "$info" ]] || return 1

    local raw
    raw="$(echo "$info" | jq -r '[
        (.blocks // 0),
        (.headers // 0),
        (.verificationprogress // 0),
        (.size_on_disk // 0),
        (.initialblockdownload // false)
    ] | @tsv')" || return 1
    [[ -n "$raw" ]] || return 1

    local blocks headers progress size_bytes ibd
    IFS=$'\t' read -r blocks headers progress size_bytes ibd <<< "$raw"

    local progress_pct size_gb
    progress_pct="$(echo "$progress" | LC_ALL=C awk '{printf "%.2f", $1 * 100}')"
    size_gb="$(echo "$size_bytes" | awk '{printf "%.1f", $1 / 1073741824}')"

    printf '%s\t%s\t%s\t%s\t%s\n' "$blocks" "$headers" "$progress_pct" "$size_gb" "$ibd"
}

# Return success while Bitcoin is still syncing.
# Args: blocks headers progress_pct ibd
# Sync is active when:
# - initialblockdownload=true, or
# - blocks < headers, or
# - verification progress < 99.99
domain_bitcoin_sync_active() {
    local blocks="$1" headers="$2" progress_pct="$3" ibd="$4"

    if [[ "$ibd" == "true" ]] || [[ "${blocks:-0}" -lt "${headers:-0}" ]]; then
        return 0
    fi

    LC_ALL=C awk "BEGIN {exit (${progress_pct:-0} >= 99.99)}" 2>/dev/null
}
