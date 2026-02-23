#!/bin/bash
# Awning v2: Setup wizard
# Guided setup with polished terminal UI
# Only requirement: Docker (with compose plugin)

# --- Setup constants ---
# REQUIRED_DISK_GB is defined in common.sh
FALLBACK_BITCOIN_VERSION="30.2"
FALLBACK_LND_VERSION="0.20.1-beta"
FALLBACK_ELECTRS_VERSION="0.11.0"
FALLBACK_RTL_VERSION="0.15.8"

# Update or append a KEY=VALUE pair in a .env file.
# If the key already exists, its value is replaced in-place.
# If not, the line is appended.
# Uses a line-by-line loop instead of sed to avoid escaping pitfalls
# with special characters in passwords and values.
# Args: $1=file  $2=key  $3=value
_env_set() {
    local file="$1" key="$2" value="$3"
    local found=0
    local tmpfile

    if [[ -f "$file" ]]; then
        tmpfile="$(mktemp "${file}.tmp.XXXXXX")"
        while IFS= read -r line || [[ -n "$line" ]]; do
            if [[ "$line" == "${key}="* ]]; then
                echo "${key}=${value}"
                found=1
            else
                echo "$line"
            fi
        done < "$file" > "$tmpfile"

        # Append if key was not found, before the atomic mv
        if [[ "$found" -eq 0 ]]; then
            echo "${key}=${value}" >> "$tmpfile"
        fi
        mv "$tmpfile" "$file"
    else
        echo "${key}=${value}" >> "$file"
    fi
}

maybe_require_first_run_disclaimer() {
    local env_file
    env_file="$(awning_path .env)"

    # Only show on first setup when no configuration exists yet.
    [[ -f "$env_file" ]] && return 0

    clear
    draw_header "IMPORTANT DISCLAIMER" "Explicit acceptance required"
    echo ""
    echo -e "  This software configures and runs a Bitcoin + Lightning node."
    echo -e "  You are solely responsible for security, backups, and funds."
    echo -e "  Use at your own risk: software bugs, hardware failures,"
    echo -e "  or misconfiguration may cause data loss or financial loss."
    echo -e "  Full disclaimer: ${UNDERLINE}https://github.com/giovantenne/awning/blob/master/DISCLAIMER.md${NC}"
    echo ""
    echo -e "  Type ${BOLD}I ACCEPT${NC} to continue:"

    local answer
    read -r -p "$(echo -e "  ${YELLOW}>${NC} ")" answer < /dev/tty
    if [[ "$answer" != "I ACCEPT" ]]; then
        print_warn "Disclaimer not accepted. Setup aborted."
        return 1
    fi

    return 0
}

run_setup() {
    local ignore_disk_space="${1:-0}"
    maybe_require_first_run_disclaimer || return 1
    draw_header "AWNING SETUP" "Bitcoin + Lightning Node"

    step_prerequisites "$ignore_disk_space"
    step_node_config
    step_scb_config
    step_rtl_config
    step_generate_configs
    if ! step_build_and_start; then
        return 1
    fi
    if ! step_initialize_wallet; then
        return 1
    fi

    echo ""
    echo -e "  ${ICON_BOLT} ${BOLD}Setup complete!${NC} Bitcoin sync will take several days."
    echo -e "  Run ${CYAN}./awning.sh${NC} again to access the management menu."
    echo ""
}

# ============================================================
# Auto-setup: near-zero-interaction first-run experience
# ============================================================
# Detects defaults, asks only the RTL password, and runs everything.
# Offers an escape hatch ('w') to launch the full interactive wizard.
run_auto_setup() {
    local ignore_disk_space="${1:-0}"
    local AUTO_SETUP_MODE=1
    maybe_require_first_run_disclaimer || return 1
    clear
    draw_header "AWNING FIRST SETUP" "Bitcoin + Lightning Node"

    # --- Prerequisites (reuse existing, non-interactive) ---
    step_prerequisites "$ignore_disk_space" || return 1

    # --- Auto-detect architecture ---
    detect_arch || return 1
    local bitcoin_arch="$DETECTED_BITCOIN_ARCH"
    local lnd_arch="$DETECTED_LND_ARCH"

    # --- Auto-detect UID/GID ---
    local host_uid host_gid
    host_uid="$(id -u)"
    host_gid="$(id -g)"

    # --- Fetch latest versions with spinner ---
    echo ""
    echo -e "  ${BOLD}${CYAN}Fetching latest versions...${NC}"

    local btc_version lnd_version electrs_version rtl_version
    local tmp_btc_ver tmp_lnd_ver tmp_electrs_ver tmp_rtl_ver
    tmp_btc_ver="$(mktemp /tmp/awning_btc_ver.XXXXXX)"
    tmp_lnd_ver="$(mktemp /tmp/awning_lnd_ver.XXXXXX)"
    tmp_electrs_ver="$(mktemp /tmp/awning_electrs_ver.XXXXXX)"
    tmp_rtl_ver="$(mktemp /tmp/awning_rtl_ver.XXXXXX)"

    # Ensure temp files are cleaned up on exit/error (preserve existing traps)
    local _prev_trap
    _prev_trap="$(trap -p EXIT | sed "s/^trap -- '//;s/' EXIT$//" )" || true
    trap 'rm -f "$tmp_btc_ver" "$tmp_lnd_ver" "$tmp_electrs_ver" "$tmp_rtl_ver"; _cleanup_github_cache; '"${_prev_trap}" EXIT

    fetch_latest_github_version "bitcoin/bitcoin" > "$tmp_btc_ver" 2>/dev/null &
    local pid_btc=$!
    fetch_latest_github_version "lightningnetwork/lnd" > "$tmp_lnd_ver" 2>/dev/null &
    local pid_lnd=$!
    fetch_latest_github_version "romanz/electrs" > "$tmp_electrs_ver" 2>/dev/null &
    local pid_electrs=$!
    fetch_latest_github_version "Ride-The-Lightning/RTL" > "$tmp_rtl_ver" 2>/dev/null &
    local pid_rtl=$!

    # Wait for all fetches and track failures
    local fetch_failures=0
    wait "$pid_btc" 2>/dev/null || fetch_failures=$((fetch_failures + 1))
    wait "$pid_lnd" 2>/dev/null || fetch_failures=$((fetch_failures + 1))
    wait "$pid_electrs" 2>/dev/null || fetch_failures=$((fetch_failures + 1))
    wait "$pid_rtl" 2>/dev/null || fetch_failures=$((fetch_failures + 1))

    btc_version="$(cat "$tmp_btc_ver" 2>/dev/null)" || true
    lnd_version="$(cat "$tmp_lnd_ver" 2>/dev/null)" || true
    electrs_version="$(cat "$tmp_electrs_ver" 2>/dev/null)" || true
    rtl_version="$(cat "$tmp_rtl_ver" 2>/dev/null)" || true
    rm -f "$tmp_btc_ver" "$tmp_lnd_ver" "$tmp_electrs_ver" "$tmp_rtl_ver"
    # Restore previous EXIT trap (or clear if none existed)
    if [[ -n "$_prev_trap" ]]; then
        # shellcheck disable=SC2064  # Intentional: restore previously captured trap
        trap "${_prev_trap}" EXIT
    else
        trap - EXIT
    fi
    _cleanup_github_cache

    # Fallback to constants if fetch failed
    btc_version="${btc_version:-$FALLBACK_BITCOIN_VERSION}"
    lnd_version="${lnd_version:-$FALLBACK_LND_VERSION}"
    electrs_version="${electrs_version:-$FALLBACK_ELECTRS_VERSION}"
    rtl_version="${rtl_version:-$FALLBACK_RTL_VERSION}"

    if [[ "$fetch_failures" -gt 0 ]]; then
        print_warn "Could not fetch ${fetch_failures} version(s) from GitHub, using fallback defaults"
    fi

    print_check "Bitcoin Core ${btc_version}"
    print_check "LND ${lnd_version}"
    print_check "Electrs ${electrs_version}"
    print_check "RTL ${rtl_version}"

    # --- Config summary box ---
    local node_alias="AwningNode"
    echo ""
    draw_info_box \
        "Node alias       ${BOLD}${node_alias}${NC}" \
        "Bitcoin Core     ${BOLD}${btc_version}${NC}" \
        "LND              ${BOLD}${lnd_version}${NC}" \
        "Electrs          ${BOLD}${electrs_version}${NC}" \
        "RTL              ${BOLD}${rtl_version}${NC}" \
        "SCB              ${DIM}Static Channel Backup disabled${NC}"
    echo ""
    print_info "Settings and channel backup can be changed later from Menu > Tools > Setup wizard, or now by typing ${BOLD}w${NC}."

    # --- Auto-generate RTL password (non-interactive) ---
    local rtl_password
    rtl_password="$(generate_password 16)"

    # --- Choice prompt: Enter = auto, w = full wizard ---
    local choice
    read -r -p "$(echo -e "  Press ${BOLD}Enter${NC} to start, or type ${BOLD}'w'${NC} now for the advanced setup wizard: ")" choice < /dev/tty

    if [[ "$choice" == "w" || "$choice" == "W" ]]; then
        run_setup "$ignore_disk_space"
        return $?
    fi

    # === AUTO-SETUP: proceed with defaults ===

    # --- Write .env ---
    echo ""

    local env_file
    env_file="$(awning_path .env)"

    umask 077
    cat > "$env_file" <<EOF
# Awning v2 - Auto-setup on $(date)
# System (auto-detected, do not edit)
HOST_UID=${host_uid}
HOST_GID=${host_gid}
BITCOIN_ARCH=${bitcoin_arch}
LND_ARCH=${lnd_arch}

# Versions
BITCOIN_CORE_VERSION=${btc_version}
LND_VERSION=${lnd_version}
ELECTRS_VERSION=${electrs_version}

# Node
NODE_ALIAS=${node_alias}

# Host port bindings
LND_REST_BIND=127.0.0.1
LND_REST_PORT=8080
ELECTRS_SSL_BIND=127.0.0.1
ELECTRS_SSL_PORT=50002

# RTL (LAN accessible)
RTL_VERSION=${rtl_version}
RTL_PASSWORD=${rtl_password}
RTL_BIND=0.0.0.0
RTL_PORT=3000

# SCB (disabled)
SCB_REPO=
EOF
    chmod 600 "$env_file"

    # Export for step_generate_configs and dc_* functions
    export HOST_UID="$host_uid" HOST_GID="$host_gid"
    export BITCOIN_ARCH="$bitcoin_arch" LND_ARCH="$lnd_arch"
    export BITCOIN_CORE_VERSION="$btc_version" LND_VERSION="$lnd_version" ELECTRS_VERSION="$electrs_version"
    export NODE_ALIAS="$node_alias"
    export RTL_VERSION="$rtl_version" RTL_PASSWORD="$rtl_password" RTL_BIND="0.0.0.0" RTL_PORT="3000"
    export SCB_REPO=""

    # --- Generate configs from templates (reuse existing) ---
    step_generate_configs || return 1

    # --- Build Docker images ---
    print_step "Building Docker Images"
    echo ""
    print_info "Building Electrs from source can take ${BOLD}up to 1 hour${NC} on ARM."
    echo ""

    if ! dc_build_services; then
        print_warn "Build failed. Fix the error and re-run: ./awning.sh build"
        return 1
    fi

    # --- Start services ---
    echo ""
    ensure_lnd_password_file
    dc_start_services

    # --- Initialize wallet via REST API ---
    print_step "Initialize LND Wallet"
    echo ""
    if ! auto_initialize_wallet; then
        print_warn "Wallet initialization failed. You can retry from the menu."
        return 1
    fi

    # --- Show seed screen ---
    show_seed_screen

    # Return 0 so caller shows the dashboard
    return 0
}

# ============================================================
# Pre-step: Prerequisites (only Docker required on host)
# ============================================================
step_prerequisites() {
    local ignore_disk_space="${1:-0}"
    local can_sudo=0
    if command -v sudo &>/dev/null && sudo -n true 2>/dev/null; then
        can_sudo=1
    fi
    echo ""
    echo -e "  ${BOLD}${CYAN}Checking prerequisites...${NC}"

    local missing=0

    # Docker
    if command -v docker &>/dev/null; then
        local docker_ver
        docker_ver="$(docker --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1)" || docker_ver="unknown"
        print_check "Docker v${docker_ver}"
    else
        print_fail "Docker not found"
        print_info "Install: ${WHITE}${UNDERLINE}https://docs.docker.com/engine/install/${NC}"
        missing=1
    fi

    # Docker compose (plugin or standalone)
    if docker compose version &>/dev/null 2>&1 || docker-compose version &>/dev/null 2>&1 || \
       { [[ "$can_sudo" -eq 1 ]] && sudo -n docker compose version &>/dev/null 2>&1; } || \
       { [[ "$can_sudo" -eq 1 ]] && sudo -n docker-compose version &>/dev/null 2>&1; }; then
        local compose_ver
        compose_ver="$(docker compose version 2>/dev/null | grep -oP '\d+\.\d+(\.\d+)?' | head -1)" || true
        if [[ -z "$compose_ver" ]]; then
            compose_ver="$(docker-compose version 2>/dev/null | grep -oP '\d+\.\d+(\.\d+)?' | head -1)" || compose_ver="unknown"
            print_check "docker-compose v${compose_ver}"
        else
            print_check "docker compose v${compose_ver}"
        fi
    else
        print_fail "docker compose not found (plugin or standalone)"
        missing=1
    fi

    # Docker daemon running
    if docker info &>/dev/null 2>&1 || { [[ "$can_sudo" -eq 1 ]] && sudo -n docker info &>/dev/null 2>&1; }; then
        print_check "Docker daemon running"
    else
        print_fail "Docker daemon is not running"
        missing=1
    fi

    # Disk space check
    # Required free space is reduced by already downloaded blockchain data.
    local avail_kb avail_gb existing_bitcoin_kb required_free_kb required_free_gb
    avail_kb="$(df --output=avail "$(awning_path .)" 2>/dev/null | tail -1 | tr -d ' ')" || avail_kb=0
    avail_gb="$(echo "$avail_kb" | awk '{printf "%.1f", $1 / 1048576}')"
    existing_bitcoin_kb="$(du -sk "$(awning_path data/bitcoin)" 2>/dev/null | awk '{print $1}')" || existing_bitcoin_kb=0
    existing_bitcoin_kb="${existing_bitcoin_kb:-0}"
    required_free_kb=$((REQUIRED_DISK_GB * 1048576 - existing_bitcoin_kb))
    if [[ "$required_free_kb" -lt 0 ]]; then
        required_free_kb=0
    fi
    required_free_gb="$(echo "$required_free_kb" | awk '{printf "%.1f", $1 / 1048576}')"

    if [[ "$avail_kb" -ge "$required_free_kb" ]]; then
        print_check "Disk space: ${avail_gb} GB free (required: ${required_free_gb} GB free)"
    elif [[ "$ignore_disk_space" == "1" ]]; then
        print_warn "Disk space: ${avail_gb} GB free (required: ${required_free_gb} GB free, override enabled)"
    else
        print_fail "Disk space: ${avail_gb} GB free (required: ${required_free_gb} GB free)"
        missing=1
    fi

    # Internet connectivity
    if curl -sf --max-time 5 https://api.github.com &>/dev/null 2>&1 || \
       wget -q --timeout=5 -O /dev/null https://api.github.com 2>/dev/null || \
       _docker run --rm debian:bookworm-slim bash -c "apt-get update -qq" &>/dev/null 2>&1; then
        print_check "Internet connectivity"
    else
        print_warn "Internet connectivity check failed (may still work)"
    fi

    if [[ $missing -ne 0 ]]; then
        echo ""
        print_fail "Please install missing prerequisites and re-run setup"
        return 1
    fi

    echo ""
}

# ============================================================
# Step 1: Node configuration
# ============================================================
choose_version_from_list() {
    local label="$1"
    local default="$2"
    shift 2
    local options=("$@")

    local i=1
    for opt in "${options[@]}"; do
        echo -e "    ${BOLD}${WHITE}${i})${NC} ${opt}" >&2
        ((i++))
    done
    echo -e "    ${BOLD}${WHITE}${i})${NC} Custom" >&2

    while true; do
        local choice
        read -r -p "$(echo -e "  ${YELLOW}Choose [default ${default}]:${NC} ")" choice < /dev/tty

        if [[ -z "$choice" ]]; then
            echo "$default"
            return
        fi

        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#options[@]} + 1 )); then
            if (( choice == ${#options[@]} + 1 )); then
                local custom
                read -r -p "$(echo -e "  ${YELLOW}Enter ${label} version${NC} ${DIM}[${default}]${NC}: ")" custom < /dev/tty
                echo "${custom:-$default}"
                return
            fi
            echo "${options[$((choice - 1))]}"
            return
        fi

        print_warn "Invalid selection" >&2
    done
}

validate_node_alias() {
    local alias="$1"
    if [[ ! "$alias" =~ ^[A-Za-z0-9._-]{1,32}$ ]]; then
        print_fail "Invalid alias. Allowed chars: A-Z a-z 0-9 . _ - (max 32)"
        return 1
    fi
    return 0
}

validate_scb_repo() {
    local repo="$1"
    if [[ ! "$repo" =~ ^git@[A-Za-z0-9.-]+:[A-Za-z0-9._-]+/[A-Za-z0-9._-]+\.git$ ]]; then
        print_fail "Invalid Git SSH URL format"
        print_info "Expected: git@github.com:user/lnd-backup.git"
        return 1
    fi
    return 0
}

# Per-session GitHub API response cache (avoids rate limiting).
# Uses deterministic file paths so the cache works across subshells
# (command substitution, background jobs in run_auto_setup, etc.).
# GitHub's unauthenticated limit is 60 req/hour, so we must minimise calls.
_GITHUB_CACHE_DIR="/tmp/awning_gh_cache.$$"

# Fetch recent release versions from a GitHub repository.
# Uses curl + jq with per-session caching.
# Versions are normalized (strip leading "v"), deduplicated, and sorted by
# semantic version descending so "latest" means numerically highest version
# across all projects (not just first returned by GitHub API).
# Args:
#   $1 - GitHub repo (e.g. "bitcoin/bitcoin")
#   $2 - Number of releases to return (default: 5)
# Output: One version per line on stdout (stripped of leading "v")
# Returns: 1 if no versions could be fetched
fetch_github_versions() {
    local repo="$1"
    local limit="${2:-5}"
    local cache_key="${repo//\//_}"
    local cache_file="${_GITHUB_CACHE_DIR}/${cache_key}.json"

    # Populate cache if not present
    if [[ ! -s "$cache_file" ]]; then
        mkdir -p "$_GITHUB_CACHE_DIR"
        # Always fetch a generous page so the cache covers both "latest"
        # and "show recent releases" use-cases.
        local fetch_limit=$(( limit > 8 ? limit : 8 ))
        curl -sf --max-time 10 -H "User-Agent: awning-setup" \
            "https://api.github.com/repos/${repo}/releases?per_page=${fetch_limit}" \
            > "$cache_file" 2>/dev/null || true
        # Discard if not a valid JSON array (e.g. rate-limit error message)
        if ! jq -e 'type == "array"' < "$cache_file" &>/dev/null; then
            rm -f "$cache_file"
            return 1
        fi
    fi

    local output
    output="$(
        jq -r '.[].tag_name' < "$cache_file" \
        | sed 's/^v//' \
        | awk 'NF && !seen[$0]++' \
        | sort -Vr \
        | head -n "$limit"
    )" || true

    if [[ -z "$output" ]]; then
        return 1
    fi

    echo "$output"
}

# Fetch the latest release version for a GitHub repo.
# Reuses the cached /releases response from fetch_github_versions.
fetch_latest_github_version() {
    local repo="$1"
    fetch_github_versions "$repo" 1 | head -1
}

# Clean up cached GitHub API responses.
_cleanup_github_cache() {
    rm -rf "$_GITHUB_CACHE_DIR" 2>/dev/null || true
}

# Interactive version selector with latest/custom/list options.
# Args:
#   $1 - Human-readable label (e.g. "Bitcoin Core")
#   $2 - GitHub repo (e.g. "bitcoin/bitcoin")
#   $3 - Fallback version if GitHub is unreachable
#   $4 - Current version (optional, enables "Keep current" option)
# Output: Selected version string on stdout
select_version_interactive() {
    local label="$1"
    local repo="$2"
    local fallback_latest="$3"
    local current_value="${4:-}"

    local latest
    latest="$(fetch_latest_github_version "$repo" 2>/dev/null)" || latest="$fallback_latest"

    echo "" >&2
    echo -e "  ${BOLD}${CYAN}${label} version${NC}" >&2
    local default_choice=1
    local custom_default="$latest"
    if [[ -n "$current_value" ]]; then
        echo -e "    ${BOLD}${WHITE}1)${NC} Keep current (${current_value})" >&2
        echo -e "    ${BOLD}${WHITE}2)${NC} Latest (${latest})" >&2
        echo -e "    ${BOLD}${WHITE}3)${NC} Custom version" >&2
        echo -e "    ${BOLD}${WHITE}4)${NC} Show recent releases" >&2
        custom_default="$current_value"
    else
        echo -e "    ${BOLD}${WHITE}1)${NC} Latest (${latest})" >&2
        echo -e "    ${BOLD}${WHITE}2)${NC} Custom version" >&2
        echo -e "    ${BOLD}${WHITE}3)${NC} Show recent releases" >&2
    fi

    while true; do
        local choice
        read -r -p "$(echo -e "  ${YELLOW}Choose [default ${default_choice}]:${NC} ")" choice < /dev/tty
        choice="${choice:-$default_choice}"

        case "$choice" in
            1)
                if [[ -n "$current_value" ]]; then
                    echo "$current_value"
                else
                    echo "$latest"
                fi
                return
                ;;
            2)
                if [[ -n "$current_value" ]]; then
                    echo "$latest"
                    return
                fi
                local custom
                read -r -p "$(echo -e "  ${YELLOW}Enter ${label} version${NC} ${DIM}[${custom_default}]${NC}: ")" custom < /dev/tty
                echo "${custom:-$custom_default}"
                return
                ;;
            3)
                if [[ -n "$current_value" ]]; then
                    local custom
                    read -r -p "$(echo -e "  ${YELLOW}Enter ${label} version${NC} ${DIM}[${custom_default}]${NC}: ")" custom < /dev/tty
                    echo "${custom:-$custom_default}"
                    return
                fi
                local versions
                versions="$(fetch_github_versions "$repo" 8 2>/dev/null)" || true
                if [[ -z "$versions" ]]; then
                    print_warn "Could not fetch recent ${label} releases, using latest (${latest})" >&2
                    echo "$latest"
                    return
                fi
                local version_list
                readarray -t version_list <<< "$versions"
                choose_version_from_list "$label" "$custom_default" "${version_list[@]}"
                return
                ;;
            4)
                if [[ -z "$current_value" ]]; then
                    print_warn "Invalid selection" >&2
                    continue
                fi
                local versions
                versions="$(fetch_github_versions "$repo" 8 2>/dev/null)" || true
                if [[ -z "$versions" ]]; then
                    print_warn "Could not fetch recent ${label} releases, using latest (${latest})" >&2
                    echo "$latest"
                    return
                fi
                local version_list
                readarray -t version_list <<< "$versions"
                choose_version_from_list "$label" "$custom_default" "${version_list[@]}"
                return
                ;;
            *)
                print_warn "Invalid selection" >&2
                ;;
        esac
    done
}

step_node_config() {
    print_step "Step 1/7: Node Configuration"

    # Auto-detect architecture
    detect_arch || return 1
    local bitcoin_arch="$DETECTED_BITCOIN_ARCH"
    local lnd_arch="$DETECTED_LND_ARCH"

    # Auto-detect UID/GID
    local host_uid host_gid
    host_uid="$(id -u)"
    host_gid="$(id -g)"

    # Node alias
    local node_alias
    local current_alias
    current_alias="${NODE_ALIAS:-AwningNode}"
    while true; do
        node_alias="$(read_input "Enter LND alias" "$current_alias")"
        if validate_node_alias "$node_alias"; then
            break
        fi
    done

    # Versions (default to latest; fetch full release list only on explicit request)
    local btc_version lnd_version electrs_version
    btc_version="$(select_version_interactive "Bitcoin Core" "bitcoin/bitcoin" "$FALLBACK_BITCOIN_VERSION" "${BITCOIN_CORE_VERSION:-}")"
    lnd_version="$(select_version_interactive "LND" "lightningnetwork/lnd" "$FALLBACK_LND_VERSION" "${LND_VERSION:-}")"
    electrs_version="$(select_version_interactive "Electrs" "romanz/electrs" "$FALLBACK_ELECTRS_VERSION" "${ELECTRS_VERSION:-}")"

    # Save to .env (UID/GID/ARCH auto-detected, not user-editable)
    local env_file
    env_file="$(awning_path .env)"

    umask 077
    cat > "$env_file" <<EOF
# Awning v2 - Generated by setup wizard on $(date)
# System (auto-detected, do not edit)
HOST_UID=${host_uid}
HOST_GID=${host_gid}
BITCOIN_ARCH=${bitcoin_arch}
LND_ARCH=${lnd_arch}

# Versions
BITCOIN_CORE_VERSION=${btc_version}
LND_VERSION=${lnd_version}
ELECTRS_VERSION=${electrs_version}

# Node
NODE_ALIAS=${node_alias}

# Host port bindings (security defaults: localhost only)
LND_REST_BIND=127.0.0.1
LND_REST_PORT=8080
ELECTRS_SSL_BIND=127.0.0.1
ELECTRS_SSL_PORT=50002
EOF
    chmod 600 "$env_file"

    echo ""
    print_check "Node configuration saved"
    _cleanup_github_cache
}

# ============================================================
# Step 2: SCB configuration
# ============================================================
step_scb_config() {
    print_step "Step 2/7: Channel Backup (SCB)"
    echo ""
    print_info "SCB automatically backs up your Lightning channel state to GitHub."
    print_info "You need a private GitHub repository and an SSH deploy key."
    echo ""

    local existing_scb_repo="${SCB_REPO:-}"
    local default_enable="y"
    if [[ -n "$existing_scb_repo" ]]; then
        print_info "Current SCB repository: ${WHITE}${UNDERLINE}${existing_scb_repo}${NC}"
    fi

    if confirm "Enable Static Channel Backup?" "$default_enable"; then
        local scb_repo
        print_info "Need a private GitHub repo? Create one at: ${WHITE}${UNDERLINE}https://github.com/new${NC}"
        print_info "Format: ${DIM}git@github.com:user/lnd-backup.git${NC}"
        while true; do
            scb_repo="$(read_input "GitHub SSH URL" "$existing_scb_repo")"
            if [[ -z "$scb_repo" ]]; then
                if [[ -n "$existing_scb_repo" ]]; then
                    scb_repo="$existing_scb_repo"
                    print_info "Keeping existing SCB repository"
                else
                    print_warn "No repository provided, SCB will be disabled"
                    _env_set "$(awning_path .env)" "SCB_REPO" ""
                    export SCB_REPO=""
                    return
                fi
            fi
            if validate_scb_repo "$scb_repo"; then
                break
            fi
            print_info "Please enter a valid SSH URL or leave blank to disable SCB."
        done

        _env_set "$(awning_path .env)" "SCB_REPO" "$scb_repo"
        export SCB_REPO="${scb_repo}"

        # Generate SSH key using Docker (no ssh-keygen needed on host)
        local scb_ssh_dir
        scb_ssh_dir="$(awning_path data/scb/.ssh)"
        mkdir -p "$scb_ssh_dir"

        local key_priv key_pub
        if [[ -f "${scb_ssh_dir}/id_rsa" || -f "${scb_ssh_dir}/id_rsa.pub" ]]; then
            key_priv="${scb_ssh_dir}/id_rsa"
            key_pub="${scb_ssh_dir}/id_rsa.pub"
        elif [[ -f "${scb_ssh_dir}/id_ed25519" || -f "${scb_ssh_dir}/id_ed25519.pub" ]]; then
            key_priv="${scb_ssh_dir}/id_ed25519"
            key_pub="${scb_ssh_dir}/id_ed25519.pub"
        else
            key_priv="${scb_ssh_dir}/id_ed25519"
            key_pub="${scb_ssh_dir}/id_ed25519.pub"
        fi

        if [[ -f "$key_priv" && ! -f "$key_pub" ]]; then
            # Recover missing public key from existing private key.
            if command -v ssh-keygen &>/dev/null; then
                ssh-keygen -y -f "$key_priv" > "$key_pub" 2>/dev/null || true
            fi
        fi

        if [[ -f "$key_priv" && -f "$key_pub" ]]; then
            print_info "Reusing existing SCB SSH key ($(basename "$key_priv"))"
        elif [[ -f "$key_pub" && ! -f "$key_priv" ]]; then
            print_warn "Found SCB public key without private key, generating a new key pair"
            rm -f "$key_pub"
        fi

        if [[ ! -f "$key_priv" ]]; then
            key_priv="${scb_ssh_dir}/id_ed25519"
            key_pub="${scb_ssh_dir}/id_ed25519.pub"
            if command -v ssh-keygen &>/dev/null; then
                ssh-keygen -t ed25519 -f "$key_priv" -N "" -C "scb@awning" &>/dev/null
            else
                # Generate via Docker if ssh-keygen not available on host
                _docker run --rm -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
                    -v "${scb_ssh_dir}:/keys" debian:bookworm-slim \
                    bash -c 'apt-get update -qq && apt-get install -y -qq openssh-client >/dev/null 2>&1 && ssh-keygen -t ed25519 -f /keys/id_ed25519 -N "" -C "scb@awning" && chown "$HOST_UID:$HOST_GID" /keys/id_ed25519 /keys/id_ed25519.pub' &>/dev/null
            fi
            print_check "SSH key generated"
        fi

        # Display the public key
        if [[ -f "$key_pub" ]]; then
            local pubkey
            pubkey="$(cat "$key_pub")"
            local key_title
            key_title="${NODE_ALIAS:-AwningNode} SCB"
            echo ""
            if [[ "$scb_repo" =~ ^git@github\.com:([^/]+)/([^/]+)\.git$ ]]; then
                local gh_owner gh_repo
                gh_owner="${BASH_REMATCH[1]}"
                gh_repo="${BASH_REMATCH[2]}"
                echo -e "  ${BOLD}Add this key at:${NC} ${WHITE}${UNDERLINE}https://github.com/${gh_owner}/${gh_repo}/settings/keys/new${NC}"
            else
                echo -e "  ${BOLD}Add this key in your repository Deploy Keys settings.${NC}"
            fi
            echo -e "  ${BOLD}Title:${NC} ${ORANGE}${key_title}${NC}"
            echo -e "  ${BOLD}Key:${NC}   ${ORANGE}${pubkey}${NC}"
            echo -e "  ${BOLD}${ORANGE}(Enable Allow write access)${NC}"
            echo ""

            # Test write access (dry-run push) if git+ssh are available
            if command -v ssh &>/dev/null && command -v git &>/dev/null; then
                while true; do
                    read -r -p "$(echo -e "  Press ${BOLD}Enter${NC} to test SSH access...")" _

                    printf '  Testing...'

                    local git_host
                    git_host="$(echo "$scb_repo" | sed -n 's/.*@\([^:]*\):.*/\1/p')"
                    if [[ -z "$git_host" ]]; then
                        print_warn "Could not parse git host from repository URL"
                        return
                    fi

                    if command -v ssh-keyscan &>/dev/null; then
                        ssh-keyscan -t ed25519 "$git_host" >> "${scb_ssh_dir}/known_hosts" 2>/dev/null || true
                    fi

                    local test_dir branch_name push_test
                    test_dir="$(mktemp -d)"
                    branch_name="awning-write-check-$(date +%s)"
                    git -C "$test_dir" init -q
                    git -C "$test_dir" remote add origin "$scb_repo"
                    echo "write-check $(date)" > "${test_dir}/.scb-write-check"
                    git -C "$test_dir" add .scb-write-check
                    git -C "$test_dir" -c user.email="awning@backup" -c user.name="Awning SCB" commit -q -m "SCB write check"
                    push_test="$(GIT_SSH_COMMAND="ssh -i ${key_priv} -o UserKnownHostsFile=${scb_ssh_dir}/known_hosts -o StrictHostKeyChecking=yes" \
                        git -C "$test_dir" push --dry-run origin "HEAD:refs/heads/${branch_name}" 2>&1)" || true
                    rm -rf "$test_dir"

                    if echo "$push_test" | grep -qiE "Everything up-to-date|new branch|\\[new branch\\]|To "; then
                        printf '\r\033[K'
                        print_check "Repository write access OK (dry-run push)"
                        break
                    fi

                    printf '\r\033[K'
                    print_fail "SSH write access test failed"
                    if echo "$push_test" | grep -qi "Permission denied"; then
                        print_fail "Deploy key missing or write access not enabled."
                    fi
                    print_fail "Fix the deploy key, then press Enter to test again."
                done
            else
                print_info "git/ssh client not on host; SCB container will test connectivity on startup"
            fi
        fi
    else
        _env_set "$(awning_path .env)" "SCB_REPO" ""
        export SCB_REPO=""
        print_info "SCB disabled"
    fi
}

# ============================================================
# Step 3: RTL (Ride The Lightning) web interface
# ============================================================
step_rtl_config() {
    print_step "Step 3/7: RTL Web Interface"
    echo ""
    print_info "RTL provides a browser-based interface for managing your Lightning node."
    print_info "It runs locally and connects to LND over the Docker network."
    echo ""

    local existing_rtl_password="${RTL_PASSWORD:-}"
    if [[ -n "$existing_rtl_password" ]]; then
        print_info "RTL is currently ${BOLD}enabled${NC}"
    fi

    if confirm "Enable RTL web interface?" "y"; then
        # RTL version selection
        local rtl_version
        rtl_version="$(select_version_interactive "RTL" "Ride-The-Lightning/RTL" "$FALLBACK_RTL_VERSION" "${RTL_VERSION:-}")"

        # RTL password
        local rtl_password
        if [[ -n "$existing_rtl_password" ]]; then
            echo ""
            print_info "Current RTL password is set."
            if confirm "Keep current RTL password?" "y"; then
                rtl_password="$existing_rtl_password"
            else
                while true; do
                    rtl_password="$(read_password "New RTL password")"
                    if validate_password "$rtl_password" "$MIN_PASSWORD_LENGTH"; then
                        break
                    fi
                done
            fi
        else
            echo ""
            print_info "Choose a password for the RTL web interface."
            while true; do
                rtl_password="$(read_password "RTL password")"
                if validate_password "$rtl_password" "$MIN_PASSWORD_LENGTH"; then
                    break
                fi
            done
        fi

        # RTL bind address and port
        local rtl_bind="${RTL_BIND:-127.0.0.1}"
        local rtl_port="${RTL_PORT:-3000}"

        # Save to .env
        local env_file
        env_file="$(awning_path .env)"
        _env_set "$env_file" "RTL_VERSION" "$rtl_version"
        _env_set "$env_file" "RTL_PASSWORD" "$rtl_password"
        _env_set "$env_file" "RTL_BIND" "$rtl_bind"
        _env_set "$env_file" "RTL_PORT" "$rtl_port"
        export RTL_VERSION="$rtl_version"
        export RTL_PASSWORD="$rtl_password"
        export RTL_BIND="$rtl_bind"
        export RTL_PORT="$rtl_port"

        echo ""
        print_check "RTL enabled (v${rtl_version}, port ${rtl_port})"
    else
        local env_file
        env_file="$(awning_path .env)"
        _env_set "$env_file" "RTL_PASSWORD" ""
        export RTL_PASSWORD=""
        print_info "RTL disabled"
    fi
}

# ============================================================
# Step 4: Generate configs from templates
# ============================================================
step_generate_configs() {
    if [[ "${AUTO_SETUP_MODE:-0}" == "1" ]]; then
        print_step "Generating Configuration"
    else
        print_step "Step 4/7: Generating Configuration"
    fi

    # Keep existing credentials on setup rerun to avoid RPC auth mismatches.
    local rpc_user rpc_password tor_password
    rpc_user="${BITCOIN_RPC_USER:-awning}"
    if [[ -n "${BITCOIN_RPC_PASSWORD:-}" ]]; then
        rpc_password="${BITCOIN_RPC_PASSWORD}"
        print_info "Reusing existing Bitcoin RPC password"
    else
        rpc_password="$(generate_password 32)"
    fi
    if [[ -n "${TOR_CONTROL_PASSWORD:-}" ]]; then
        tor_password="${TOR_CONTROL_PASSWORD}"
        print_info "Reusing existing Tor control password"
    else
        tor_password="$(generate_password 32)"
    fi

    # Update credentials in .env (upsert to avoid duplicates on rerun)
    local env_file
    env_file="$(awning_path .env)"
    _env_set "$env_file" "BITCOIN_RPC_USER" "$rpc_user"
    _env_set "$env_file" "BITCOIN_RPC_PASSWORD" "$rpc_password"
    _env_set "$env_file" "TOR_CONTROL_PASSWORD" "$tor_password"

    # Generate Bitcoin rpcauth line (via Docker if openssl not on host)
    local rpcauth_line
    rpcauth_line="$(generate_rpcauth "$rpc_user" "$rpc_password")"
    print_check "Bitcoin RPC credentials"

    # Generate Tor hashed password (via Docker if python3 not on host)
    local tor_hashed
    tor_hashed="$(generate_tor_hash "$tor_password")"
    print_check "Tor control password"

    # Process templates
    local configs_dir templates_dir user_configs_dir
    configs_dir="$(awning_path configs)"
    templates_dir="${configs_dir}/templates"
    user_configs_dir="${configs_dir}/user"
    mkdir -p "$templates_dir" "$user_configs_dir"

    # Helper: escape sed replacement metacharacters (|, &, \, newline)
    _sed_escape() {
        local s="$1"
        s="${s//\\/\\\\}"
        s="${s//|/\\|}"
        s="${s//&/\\&}"
        printf '%s' "$s"
    }

    local esc_rpcauth esc_rpc_user esc_rpc_password esc_tor_password esc_tor_hashed
    esc_rpcauth="$(_sed_escape "$rpcauth_line")"
    esc_rpc_user="$(_sed_escape "$rpc_user")"
    esc_rpc_password="$(_sed_escape "$rpc_password")"
    esc_tor_password="$(_sed_escape "$tor_password")"
    esc_tor_hashed="$(_sed_escape "$tor_hashed")"

    # Append user overrides for text-based config files.
    # WARNING: invalid overrides can break service startup.
    _append_user_override() {
        local target_file="$1"
        local user_file="$2"
        local label="$3"
        if [[ -s "$user_file" ]]; then
            {
                echo ""
                echo "# --- BEGIN user overrides (${label}) ---"
                cat "$user_file"
                echo ""
                echo "# --- END user overrides (${label}) ---"
            } >> "$target_file"
            print_warn "${label} includes user overrides (${user_file})"
        fi
    }

    # bitcoin.conf
    sed "s|{{BITCOIN_RPCAUTH}}|${esc_rpcauth}|g" \
        "${templates_dir}/bitcoin.conf.template" > "${configs_dir}/bitcoin.conf"
    _append_user_override "${configs_dir}/bitcoin.conf" "${user_configs_dir}/bitcoin.user.conf" "bitcoin.conf"
    print_check "bitcoin.conf"

    # lnd.conf
    sed -e "s|{{BITCOIN_RPC_USER}}|${esc_rpc_user}|g" \
        -e "s|{{BITCOIN_RPC_PASSWORD}}|${esc_rpc_password}|g" \
        -e "s|{{TOR_CONTROL_PASSWORD}}|${esc_tor_password}|g" \
        "${templates_dir}/lnd.conf.template" > "${configs_dir}/lnd.conf"
    _append_user_override "${configs_dir}/lnd.conf" "${user_configs_dir}/lnd.user.conf" "lnd.conf"
    print_check "lnd.conf"

    # electrs.toml
    sed -e "s|{{BITCOIN_RPC_USER}}|${esc_rpc_user}|g" \
        -e "s|{{BITCOIN_RPC_PASSWORD}}|${esc_rpc_password}|g" \
        "${templates_dir}/electrs.toml.template" > "${configs_dir}/electrs.toml"
    _append_user_override "${configs_dir}/electrs.toml" "${user_configs_dir}/electrs.user.conf" "electrs.toml"
    print_check "electrs.toml"

    # torrc
    sed "s|{{TOR_HASHED_PASSWORD}}|${esc_tor_hashed}|g" \
        "${templates_dir}/torrc.template" > "${configs_dir}/torrc"
    _append_user_override "${configs_dir}/torrc" "${user_configs_dir}/torrc.user.conf" "torrc"
    print_check "torrc"

    # rtl.conf (only when RTL is enabled)
    if [[ -n "${RTL_PASSWORD:-}" ]]; then
        local node_alias
        node_alias="${NODE_ALIAS:-AwningNode}"
        local esc_rtl_password esc_node_alias
        esc_rtl_password="$(_sed_escape "${RTL_PASSWORD}")"
        esc_node_alias="$(_sed_escape "$node_alias")"
        sed -e "s|{{RTL_PASSWORD}}|${esc_rtl_password}|g" \
            -e "s|{{NODE_ALIAS}}|${esc_node_alias}|g" \
            "${templates_dir}/rtl.conf.template" > "${configs_dir}/rtl.conf"
        # rtl.user.conf is a full override (JSON), not an append fragment.
        if [[ -s "${user_configs_dir}/rtl.user.conf" ]]; then
            cp "${user_configs_dir}/rtl.user.conf" "${configs_dir}/rtl.conf"
            print_warn "rtl.conf replaced by user override (${user_configs_dir}/rtl.user.conf)"
        fi
        # RTL needs the config in its data dir (it writes to it at runtime)
        local rtl_dir rtl_config
        rtl_dir="$(awning_path data/rtl)"
        rtl_config="${rtl_dir}/RTL-Config.json"
        mkdir -p "$rtl_dir"
        if [[ ! -w "$rtl_dir" ]]; then
            local owner_uid owner_gid
            owner_uid="${HOST_UID:-$(id -u)}"
            owner_gid="${HOST_GID:-$(id -g)}"
            if command -v sudo &>/dev/null; then
                sudo chown -R "${owner_uid}:${owner_gid}" "$rtl_dir" 2>/dev/null || true
            else
                chown -R "${owner_uid}:${owner_gid}" "$rtl_dir" 2>/dev/null || true
            fi
        fi
        if [[ -e "$rtl_config" ]] && [[ ! -w "$rtl_config" ]]; then
            if command -v sudo &>/dev/null; then
                sudo rm -f "$rtl_config" 2>/dev/null || true
            else
                rm -f "$rtl_config" 2>/dev/null || true
            fi
        fi
        cp "${configs_dir}/rtl.conf" "$rtl_config" 2>/dev/null || true
        if [[ ! -s "${configs_dir}/rtl.conf" ]] || [[ ! -s "$rtl_config" ]]; then
            print_fail "RTL config generation failed (empty or unwritable config)"
            return 1
        fi
        print_check "rtl.conf"
    fi

    # .env
    print_check ".env"

    # Create data directories
    for dir in bitcoin lnd electrs tor scb rtl; do
        mkdir -p "$(awning_path "data/${dir}")"
    done
}

# Generate rpcauth line compatible with Bitcoin Core.
# Uses openssl on host if available, otherwise runs via Docker with Python.
# Args:
#   $1 - RPC username
#   $2 - RPC password (plaintext)
# Output: rpcauth=<user>:<salt>$<hmac> on stdout
# Returns: 1 on failure
generate_rpcauth() {
    local user="$1"
    local password="$2"

    local salt hmac

    if command -v openssl &>/dev/null; then
        salt="$(openssl rand -hex 16)"
        hmac="$(echo -n "${password}" | openssl dgst -sha256 -hmac "${salt}" -binary | od -A n -t x1 | tr -d ' \n')"
    else
        # Run via Docker using Python (no host Python dependency)
        local result
        result="$(_docker run --rm -i python:3-slim python3 - "$password" <<'PY'
import hashlib, hmac as h, os, sys
password = sys.argv[1].encode()
salt = os.urandom(16).hex()
mac = h.new(salt.encode(), password, hashlib.sha256).hexdigest()
print(salt + ' ' + mac)
PY
)" || true
        salt="$(echo "$result" | tail -1 | awk '{print $1}')"
        hmac="$(echo "$result" | tail -1 | awk '{print $2}')"
    fi

    if [[ -z "$salt" || -z "$hmac" ]]; then
        print_fail "Failed to generate RPC auth credentials"
        return 1
    fi

    echo "rpcauth=${user}:${salt}\$${hmac}"
}

# Generate Tor hashed control password via Docker.
# Args:
#   $1 - Tor control password (plaintext)
# Output: Hashed password string (16:...) on stdout
# Returns: 1 on failure
generate_tor_hash() {
    local password="$1"
    local hash
    hash="$(_docker run --rm -i python:3-slim python3 - "$password" <<'PY'
import hashlib, os, binascii, sys
password = sys.argv[1].encode()
indicator = 96
count = (16 + (indicator & 15)) << ((indicator >> 4) + 6)
salt = os.urandom(8)
data = salt + password
hash_input = b''
while len(hash_input) < count:
    hash_input += data
hash_input = hash_input[:count]
h = hashlib.sha1(hash_input).digest()
print('16:' + binascii.hexlify(salt).decode().upper() + '{:02X}'.format(indicator) + binascii.hexlify(h).decode().upper())
PY
)" || true

    if [[ -z "$hash" ]]; then
        print_fail "Failed to generate Tor password hash"
        return 1
    fi

    echo "$hash"
}

# ============================================================
# Step 5: Build Docker images
# ============================================================
step_build_and_start() {
    print_step "Step 5/7: Building Docker Images"
    echo ""
    print_info "Building Electrs from source can take ${BOLD}up to 1 hour${NC} on ARM."
    echo ""

    if ! confirm "Start building?" "y"; then
        echo ""
        print_info "You can build and start later with: ./awning.sh start"
        return 0
    fi

    echo ""
    if ! dc_build_services; then
        print_warn "Build failed. Fix the error and re-run: ./awning.sh build"
        return 1
    fi

    # Step 6: Recreate services so new images/config/env are applied.
    print_step "Step 6/7: Restarting Services"
    echo ""
    ensure_lnd_password_file
    dc_restart >/dev/null 2>&1 &
    local restart_pid=$!
    if ! spinner "$restart_pid" "Recreating services with updated configuration..."; then
        print_fail "Failed to restart services with updated configuration"
        return 1
    fi
}

# ============================================================
# Step 7: Initialize LND wallet
# ============================================================
step_initialize_wallet() {
    print_step "Step 7/7: Initialize LND Wallet"
    echo ""

    local macaroon
    macaroon="$(awning_path "data/lnd/${ADMIN_MACAROON_SUBPATH}")"
    if [[ -f "$macaroon" ]]; then
        print_info "Wallet already initialized, skipping."
        return 0
    fi

    if ! dc_is_running lnd; then
        print_warn "LND is not running. Attempting to start required services..."
        dc_start_services lnd >/dev/null 2>&1 || true
        sleep 2
        if ! dc_is_running lnd; then
            print_warn "LND is still not running, wallet initialization skipped."
            print_info "Check logs with: ${CYAN}./awning.sh logs lnd${NC}"
            return 0
        fi
        print_check "LND started"
    fi

    local lnd_password
    local password_file
    password_file="$(awning_path data/lnd/password.txt)"
    mkdir -p "$(awning_path data/lnd)"

    echo ""
    print_info "Enter the LND auto-unlock password (saved in password.txt)."
    print_info "Use the same password you will enter in wallet creation."
    while true; do
        lnd_password="$(read_password "LND auto-unlock password")"
        if validate_password "$lnd_password" "$MIN_PASSWORD_LENGTH"; then
            break
        fi
    done
    umask 077
    printf '%s\n' "$lnd_password" > "$password_file"
    chmod 600 "$password_file"
    print_check "Auto-unlock password saved"

    print_info "LND will ask for wallet password twice."
    print_info "Use the same password you just saved for auto-unlock."
    print_warn "IMPORTANT: Write down the seed phrase displayed below!"
    echo ""

    if ! wait_for_lnd_stable; then
        print_fail "LND is not stable yet (still restarting)."
        print_info "Try again in a minute with: ${CYAN}./awning.sh setup${NC}"
        return 1
    fi

    if dc_exec lnd lncli create; then
        print_check "Wallet initialized"
        return 0
    fi

    print_fail "Wallet initialization failed"
    return 1
}

ensure_lnd_password_file() {
    local password_file
    password_file="$(awning_path data/lnd/password.txt)"
    mkdir -p "$(awning_path data/lnd)"
    if [[ ! -f "$password_file" ]]; then
        # Empty file to satisfy lnd startup validation before wallet init.
        umask 077
        : > "$password_file"
        chmod 600 "$password_file"
    fi
}

wait_for_lnd_stable() {
    local timeout_s="${LND_STABLE_TIMEOUT:-90}"
    local elapsed=0
    local status=""

    while (( elapsed < timeout_s )); do
        status="$(_dc ps --format '{{.Status}}' lnd 2>/dev/null)" || status=""
        if [[ -n "$status" ]] && echo "$status" | grep -qi "up"; then
            if ! echo "$status" | grep -qi "restarting"; then
                return 0
            fi
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done

    return 1
}

# ============================================================
# Auto-setup: LND REST API wallet initialization
# ============================================================

# Global array to hold the 24-word seed after wallet creation
_AUTO_SEED_WORDS=()

# Wait for LND REST API to be in wallet-creation-ready state.
# Returns: 0 = ready (NON_EXISTING), 1 = timeout, 2 = wallet already exists
wait_for_lnd_api() {
    local timeout_s="${LND_API_TIMEOUT:-120}"
    local elapsed=0

    while (( elapsed < timeout_s )); do
        local response
        response="$(dc_exec -T lnd sh -c \
            'curl -sf --max-time 10 --connect-timeout 5 --cacert /data/.lnd/tls.cert https://localhost:8080/v1/state 2>/dev/null' \
        )" || true

        if echo "$response" | grep -q "NON_EXISTING" 2>/dev/null; then
            return 0
        fi
        if echo "$response" | grep -qE "RPC_ACTIVE|SERVER_ACTIVE|UNLOCKED" 2>/dev/null; then
            return 2
        fi

        sleep 2
        elapsed=$((elapsed + 2))
    done

    return 1
}

# Wrapper: runs wait_for_lnd_api under a spinner but handles exit code 2
# (wallet already exists) without the spinner displaying a false error.
# Returns: 0 = ready, 1 = timeout, 2 = wallet already exists
_wait_for_lnd_api_with_spinner() {
    local status_file
    status_file="$(mktemp /tmp/awning_lnd_api_status.XXXXXX)"
    (
        wait_for_lnd_api
        echo $? > "$status_file"
    ) &
    local wait_pid=$!

    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0
    local message="Waiting for LND..."
    while kill -0 "$wait_pid" 2>/dev/null; do
        printf "\r  [${CYAN}%s${NC}] %s" "${frames[i++ % ${#frames[@]}]}" "$message"
        sleep 0.1
    done
    wait "$wait_pid" 2>/dev/null || true
    printf "\r\033[K"

    local api_status=1
    if [[ -f "$status_file" ]]; then
        api_status="$(cat "$status_file")"
        rm -f "$status_file"
    fi

    if [[ "$api_status" -eq 0 ]]; then
        print_check "$message"
    elif [[ "$api_status" -eq 2 ]]; then
        print_info "Wallet already exists"
    else
        print_fail "$message (timed out)"
    fi

    return "$api_status"
}

# Initialize LND wallet via REST API (non-interactive).
# Two-step process: 1) /v1/genseed to generate seed, 2) /v1/initwallet with seed + password.
# Writes password.txt, captures seed in _AUTO_SEED_WORDS.
# Returns: 0 = success, 1 = failure
auto_initialize_wallet() {
    local lnd_password
    lnd_password="$(generate_password 16)"
    local password_file
    password_file="$(awning_path data/lnd/password.txt)"
    mkdir -p "$(awning_path data/lnd)"

    # Skip if wallet already exists (macaroon present)
    local macaroon
    macaroon="$(awning_path "data/lnd/${ADMIN_MACAROON_SUBPATH}")"
    if [[ -f "$macaroon" ]]; then
        print_info "Wallet already initialized, skipping."
        return 0
    fi

    # Write the auto-unlock password
    umask 077
    printf '%s\n' "$lnd_password" > "$password_file"
    chmod 600 "$password_file"

    echo -e "  ${BOLD}${CYAN}Initializing LND wallet...${NC}"

    # Wait for LND container to stabilize
    if ! wait_for_lnd_stable; then
        print_fail "LND container is not stable (still restarting)."
        print_info "Check logs with: ${CYAN}./awning.sh logs lnd${NC}"
        return 1
    fi

    # Wait for LND REST API to be ready for wallet creation
    local api_status=0
    _wait_for_lnd_api_with_spinner || api_status=$?

    if [[ $api_status -eq 2 ]]; then
        print_info "Wallet already exists, skipping creation."
        return 0
    fi
    if [[ $api_status -ne 0 ]]; then
        print_fail "LND REST API did not become ready within ${LND_API_TIMEOUT:-120} seconds."
        print_info "Check logs with: ${CYAN}./awning.sh logs lnd${NC}"
        return 1
    fi

    # Step 1: Generate seed via /v1/genseed
    local genseed_response
    genseed_response="$(dc_exec -T lnd sh -c \
        'curl -s --max-time 30 --connect-timeout 10 --cacert /data/.lnd/tls.cert https://localhost:8080/v1/genseed' \
    )" || true

    if [[ -z "$genseed_response" ]]; then
        print_fail "genseed API returned empty response."
        return 1
    fi

    # Check for error in genseed response
    local genseed_error
    genseed_error="$(echo "$genseed_response" | jq -r '.message // empty' 2>/dev/null)" || true
    if [[ -n "$genseed_error" ]]; then
        print_fail "genseed error: ${genseed_error}"
        return 1
    fi

    # Extract the seed mnemonic array as JSON for re-use in initwallet
    local seed_array
    seed_array="$(echo "$genseed_response" | jq -c '.cipher_seed_mnemonic' 2>/dev/null)" || true
    if [[ -z "$seed_array" || "$seed_array" == "null" ]]; then
        print_fail "Could not extract seed from genseed response."
        return 1
    fi

    # Step 2: Initialize wallet with seed + password via /v1/initwallet
    local password_b64
    password_b64="$(printf '%s' "$lnd_password" | base64)"

    local init_payload
    init_payload="{\"wallet_password\":\"${password_b64}\",\"cipher_seed_mnemonic\":${seed_array}}"

    local init_response
    init_response="$(printf '%s' "$init_payload" | dc_exec -T lnd sh -c \
        'curl -s --max-time 30 --cacert /data/.lnd/tls.cert https://localhost:8080/v1/initwallet -d @-' \
    )" || true

    if [[ -z "$init_response" ]]; then
        print_fail "initwallet API returned empty response."
        return 1
    fi

    # Check for error in initwallet response
    local init_error
    init_error="$(echo "$init_response" | jq -r '.message // empty' 2>/dev/null)" || true
    if [[ -n "$init_error" ]]; then
        print_fail "initwallet error: ${init_error}"
        return 1
    fi

    # Extract seed words from the genseed response for display
    local seed_words_raw
    seed_words_raw="$(echo "$genseed_response" | jq -r '.cipher_seed_mnemonic[]' 2>/dev/null)" || true

    if [[ -z "$seed_words_raw" ]]; then
        print_fail "Could not extract seed words for display."
        return 1
    fi

    # Store seed words in global array
    _AUTO_SEED_WORDS=()
    while IFS= read -r word; do
        _AUTO_SEED_WORDS+=("$word")
    done <<< "$seed_words_raw"

    if [[ ${#_AUTO_SEED_WORDS[@]} -ne 24 ]]; then
        print_fail "Expected 24 seed words, got ${#_AUTO_SEED_WORDS[@]}."
        return 1
    fi

    print_check "Wallet created"
    return 0
}

# ============================================================
# Auto-setup: Seed display screen
# ============================================================

# Display the 24-word seed in a polished TUI screen.
# Reads from the global _AUTO_SEED_WORDS array.
show_seed_screen() {
    if [[ ${#_AUTO_SEED_WORDS[@]} -ne 24 ]]; then
        print_warn "No seed to display."
        return
    fi

    clear
    draw_header "WALLET CREATED" "Write down your seed"

    echo ""

    # Build the 3-column x 8-row grid
    local grid_lines=()
    local row col idx num word padded_num padded_word line
    for (( row = 0; row < 8; row++ )); do
        line=""
        for (( col = 0; col < 3; col++ )); do
            idx=$(( row + col * 8 ))
            num=$(( idx + 1 ))
            word="${_AUTO_SEED_WORDS[$idx]}"
            padded_num="$(printf "%2d" "$num")"
            padded_word="$(printf "%-10s" "$word")"
            if [[ -n "$line" ]]; then
                line="${line}  "
            fi
            line="${line}${padded_num}. ${padded_word}"
        done
        grid_lines+=("$line")
    done

    # Display inside a titled box
    draw_titled_info_box \
        "24-word recovery seed" \
        " " \
        "  ${grid_lines[0]}" \
        "  ${grid_lines[1]}" \
        "  ${grid_lines[2]}" \
        "  ${grid_lines[3]}" \
        "  ${grid_lines[4]}" \
        "  ${grid_lines[5]}" \
        "  ${grid_lines[6]}" \
        "  ${grid_lines[7]}" \
        " "

    echo ""
    print_warn "${BOLD}IMPORTANT:${NC} Write these words down and store them safely."
    print_warn "They ${BOLD}CANNOT${NC} be shown again. This is your only backup."
    echo ""

    # Show RTL URL only when enabled, honoring configured bind/port.
    if [[ -n "${RTL_PASSWORD:-}" ]]; then
        local lan_ip rtl_bind rtl_port rtl_host
        lan_ip="$(get_lan_ip)"
        rtl_bind="${RTL_BIND:-127.0.0.1}"
        rtl_port="${RTL_PORT:-3000}"
        rtl_host="$rtl_bind"
        if [[ "$rtl_bind" == "0.0.0.0" ]]; then
            rtl_host="$lan_ip"
        fi
        draw_titled_info_box \
            "RTL web interface" \
            " " \
            "URL: ${BOLD}http://${rtl_host}:${rtl_port}${NC}" \
            "Password: ${ORANGE}${RTL_PASSWORD}${NC}" \
            " " \
            "${DIM}Password can be changed from the web interface.${NC}" \
            " "
        echo ""
    else
        print_info "RTL web interface is disabled."
        echo ""
    fi
    print_info "To change settings or enable SCB backups, use:"
    print_info "Menu > Tools > Setup wizard"
    echo ""

    read -r -n 1 -s -p "$(echo -e "  Press any key to continue to dashboard...")" < /dev/tty
    echo ""
}
