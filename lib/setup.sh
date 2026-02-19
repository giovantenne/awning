#!/bin/bash
# Awning v2: Setup wizard
# Guided setup with polished terminal UI
# Only requirement: Docker (with compose plugin)

run_setup() {
    local ignore_disk_space="${1:-0}"
    draw_header "AWNING SETUP" "Bitcoin + Lightning Node"

    step_prerequisites "$ignore_disk_space"
    step_node_config
    step_scb_config
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
# Pre-step: Prerequisites (only Docker required on host)
# ============================================================
step_prerequisites() {
    local ignore_disk_space="${1:-0}"
    echo ""
    echo -e "  ${BOLD}Checking prerequisites...${NC}"

    local missing=0

    # Docker
    if command -v docker &>/dev/null; then
        local docker_ver
        docker_ver="$(docker --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1)" || docker_ver="unknown"
        print_check "Docker v${docker_ver}"
    else
        print_fail "Docker not found"
        print_info "Install: https://docs.docker.com/engine/install/"
        missing=1
    fi

    # Docker compose (plugin or standalone)
    if docker compose version &>/dev/null 2>&1 || sudo docker compose version &>/dev/null 2>&1 || \
       docker-compose version &>/dev/null 2>&1 || sudo docker-compose version &>/dev/null 2>&1; then
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
    if docker info &>/dev/null 2>&1 || sudo docker info &>/dev/null 2>&1; then
        print_check "Docker daemon running"
    else
        print_fail "Docker daemon is not running"
        missing=1
    fi

    # Disk space check
    # If data/bitcoin already contains blockchain data, count it as reusable space.
    local avail_kb avail_gb existing_bitcoin_kb existing_bitcoin_gb effective_kb effective_gb
    avail_kb="$(df --output=avail "$(awning_path .)" 2>/dev/null | tail -1 | tr -d ' ')" || avail_kb=0
    avail_gb="$(echo "$avail_kb" | awk '{printf "%.1f", $1 / 1048576}')"
    existing_bitcoin_kb="$(du -sk "$(awning_path data/bitcoin)" 2>/dev/null | awk '{print $1}')" || existing_bitcoin_kb=0
    existing_bitcoin_kb="${existing_bitcoin_kb:-0}"
    existing_bitcoin_gb="$(echo "$existing_bitcoin_kb" | awk '{printf "%.1f", $1 / 1048576}')"
    effective_kb=$((avail_kb + existing_bitcoin_kb))
    effective_gb="$(echo "$effective_kb" | awk '{printf "%.1f", $1 / 1048576}')"
    local effective_gb_int="${effective_gb%.*}"

    if [[ "$effective_gb_int" -ge 900 ]]; then
        if [[ "$existing_bitcoin_kb" -gt 0 ]]; then
            print_check "Disk space: ${avail_gb} GB free + ${existing_bitcoin_gb} GB existing bitcoin data = ${effective_gb} GB effective (900 GB required)"
        else
            print_check "Disk space: ${avail_gb} GB available (900 GB required)"
        fi
    elif [[ "$effective_gb_int" -ge 600 ]]; then
        if [[ "$existing_bitcoin_kb" -gt 0 ]]; then
            print_warn "Disk space: ${avail_gb} GB free + ${existing_bitcoin_gb} GB existing bitcoin data = ${effective_gb} GB effective (900 GB recommended)"
        else
            print_warn "Disk space: ${avail_gb} GB available (900 GB recommended)"
        fi
    elif [[ "$ignore_disk_space" == "1" ]]; then
        if [[ "$existing_bitcoin_kb" -gt 0 ]]; then
            print_warn "Disk space: ${avail_gb} GB free + ${existing_bitcoin_gb} GB existing bitcoin data = ${effective_gb} GB effective (below minimum, override enabled)"
        else
            print_warn "Disk space: ${avail_gb} GB available (below minimum, override enabled)"
        fi
    else
        if [[ "$existing_bitcoin_kb" -gt 0 ]]; then
            print_fail "Disk space: ${avail_gb} GB free + ${existing_bitcoin_gb} GB existing bitcoin data = ${effective_gb} GB effective (900 GB required)"
        else
            print_fail "Disk space: ${avail_gb} GB available (900 GB required)"
        fi
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
        log_error "Please install missing prerequisites and re-run setup"
        exit 1
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
        echo "    ${i}) ${opt}" >&2
        ((i++))
    done
    echo "    ${i}) Custom" >&2

    while true; do
        local choice
        read -r -p "  Choose [default ${default}]: " choice < /dev/tty

        if [[ -z "$choice" ]]; then
            echo "$default"
            return
        fi

        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#options[@]} + 1 )); then
            if (( choice == ${#options[@]} + 1 )); then
                local custom
                read -r -p "  Enter ${label} version [${default}]: " custom < /dev/tty
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

fetch_github_versions() {
    local repo="$1"
    local limit="${2:-5}"
    local output=""

    output="$(_docker run --rm -i python:3-slim python3 - "$repo" "$limit" <<'PY'
import json, sys, urllib.request
repo = sys.argv[1]
limit = int(sys.argv[2])
url = f"https://api.github.com/repos/{repo}/releases?per_page={limit}"
req = urllib.request.Request(url, headers={"User-Agent": "awning-setup"})
with urllib.request.urlopen(req, timeout=10) as r:
    data = json.load(r)
versions = []
for rel in data:
    tag = rel.get("tag_name", "")
    if tag.startswith("v"):
        tag = tag[1:]
    if tag and tag not in versions:
        versions.append(tag)
for v in versions:
    print(v)
PY
)" || true

    if [[ -z "$output" ]]; then
        return 1
    fi

    echo "$output"
}

fetch_latest_github_version() {
    local repo="$1"
    local output=""

    output="$(_docker run --rm -i python:3-slim python3 - "$repo" <<'PY'
import json, sys, urllib.request
repo = sys.argv[1]
url = f"https://api.github.com/repos/{repo}/releases/latest"
req = urllib.request.Request(url, headers={"User-Agent": "awning-setup"})
with urllib.request.urlopen(req, timeout=10) as r:
    data = json.load(r)
tag = data.get("tag_name", "")
if tag.startswith("v"):
    tag = tag[1:]
print(tag)
PY
)" || true

    [[ -n "$output" ]] || return 1
    echo "$output"
}

select_version_interactive() {
    local label="$1"
    local repo="$2"
    local fallback_latest="$3"
    local current_value="${4:-}"

    local latest
    latest="$(fetch_latest_github_version "$repo" 2>/dev/null)" || latest="$fallback_latest"

    echo "" >&2
    echo -e "  ${BOLD}${label} version${NC}" >&2
    local default_choice=1
    local custom_default="$latest"
    if [[ -n "$current_value" ]]; then
        echo -e "    1) Keep current (${current_value})" >&2
        echo -e "    2) Latest (${latest})" >&2
        echo "    3) Custom version" >&2
        echo "    4) Show recent releases" >&2
        custom_default="$current_value"
    else
        echo -e "    1) Latest (${latest})" >&2
        echo "    2) Custom version" >&2
        echo "    3) Show recent releases" >&2
    fi

    while true; do
        local choice
        read -r -p "  Choose [default ${default_choice}]: " choice < /dev/tty
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
                read -r -p "  Enter ${label} version [${custom_default}]: " custom < /dev/tty
                echo "${custom:-$custom_default}"
                return
                ;;
            3)
                if [[ -n "$current_value" ]]; then
                    local custom
                    read -r -p "  Enter ${label} version [${custom_default}]: " custom < /dev/tty
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
    print_step "Step 1/6: Node Configuration"

    # Auto-detect architecture
    local arch
    arch="$(uname -m)"
    local bitcoin_arch lnd_arch
    case "$arch" in
        x86_64)  bitcoin_arch="x86_64"; lnd_arch="amd64" ;;
        aarch64) bitcoin_arch="aarch64"; lnd_arch="arm64" ;;
        *)
            log_error "Unsupported architecture: $arch"
            exit 1
            ;;
    esac
    print_info "Architecture: ${arch} (auto-detected)"

    # Auto-detect UID/GID
    local host_uid host_gid
    host_uid="$(id -u)"
    host_gid="$(id -g)"
    print_info "UID/GID: ${host_uid}/${host_gid} (auto-detected)"

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
    btc_version="$(select_version_interactive "Bitcoin Core" "bitcoin/bitcoin" "29.1" "${BITCOIN_CORE_VERSION:-}")"
    lnd_version="$(select_version_interactive "LND" "lightningnetwork/lnd" "0.19.3-beta" "${LND_VERSION:-}")"
    electrs_version="$(select_version_interactive "Electrs" "romanz/electrs" "0.10.10" "${ELECTRS_VERSION:-}")"

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
}

# ============================================================
# Step 2: SCB configuration
# ============================================================
step_scb_config() {
    print_step "Step 2/6: Channel Backup (SCB)"
    echo ""
    print_info "SCB automatically backs up your Lightning channel state to GitHub."
    print_info "You need a private GitHub repository and an SSH deploy key."
    echo ""

    local existing_scb_repo="${SCB_REPO:-}"
    local default_enable="y"
    if [[ -n "$existing_scb_repo" ]]; then
        print_info "Current SCB repository: ${CYAN}${existing_scb_repo}${NC}"
    fi

    if confirm "Enable Static Channel Backup?" "$default_enable"; then
        local scb_repo
        print_info "Need a private GitHub repo? Create one at: ${CYAN}https://github.com/new${NC}"
        while true; do
            scb_repo="$(read_input "GitHub SSH URL (e.g. git@github.com:user/lnd-backup.git)" "$existing_scb_repo")"
            if [[ -z "$scb_repo" ]]; then
                if [[ -n "$existing_scb_repo" ]]; then
                    scb_repo="$existing_scb_repo"
                    print_info "Keeping existing SCB repository"
                else
                    print_warn "No repository provided, SCB will be disabled"
                    echo "SCB_REPO=" >> "$(awning_path .env)"
                    export SCB_REPO=""
                    return
                fi
            fi
            if validate_scb_repo "$scb_repo"; then
                break
            fi
            print_info "Please enter a valid SSH URL or leave blank to disable SCB."
        done

        echo "SCB_REPO=${scb_repo}" >> "$(awning_path .env)"
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
                _docker run --rm -v "${scb_ssh_dir}:/keys" debian:bookworm-slim \
                    bash -c "apt-get update -qq && apt-get install -y -qq openssh-client >/dev/null 2>&1 && ssh-keygen -t ed25519 -f /keys/id_ed25519 -N '' -C 'scb@awning' && chown $(id -u):$(id -g) /keys/id_ed25519 /keys/id_ed25519.pub" &>/dev/null
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
                echo -e "  ${BOLD}Add this key at:${NC} ${CYAN}https://github.com/${gh_owner}/${gh_repo}/settings/keys/new${NC}"
            else
                echo -e "  ${BOLD}Add this key in your repository Deploy Keys settings.${NC}"
            fi
            echo -e "  ${BOLD}Title:${NC} ${YELLOW}${key_title}${NC}"
            echo -e "  ${BOLD}Key:${NC}   ${YELLOW}${pubkey}${NC}"
            echo -e "  ${BOLD}(Enable Allow write access)${NC}"
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
                        git -C "$test_dir" push --dry-run origin HEAD:refs/heads/${branch_name} 2>&1)" || true
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
        echo "SCB_REPO=" >> "$(awning_path .env)"
        export SCB_REPO=""
        print_info "SCB disabled"
    fi
}

# ============================================================
# Step 3: Generate configs from templates
# ============================================================
step_generate_configs() {
    print_step "Step 3/6: Generating Configuration"

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

    # Append to .env
    local env_file
    env_file="$(awning_path .env)"
    cat >> "$env_file" <<EOF

# Credentials (auto-generated, do not edit)
BITCOIN_RPC_USER=${rpc_user}
BITCOIN_RPC_PASSWORD=${rpc_password}
TOR_CONTROL_PASSWORD=${tor_password}
EOF

    # Generate Bitcoin rpcauth line (via Docker if openssl not on host)
    local rpcauth_line
    rpcauth_line="$(generate_rpcauth "$rpc_user" "$rpc_password")"
    print_check "Bitcoin RPC credentials"

    # Generate Tor hashed password (via Docker if python3 not on host)
    local tor_hashed
    tor_hashed="$(generate_tor_hash "$tor_password")"
    print_check "Tor control password"

    # Process templates
    local configs_dir
    configs_dir="$(awning_path configs)"

    # bitcoin.conf
    sed "s|{{BITCOIN_RPCAUTH}}|${rpcauth_line}|g" \
        "${configs_dir}/bitcoin.conf.template" > "${configs_dir}/bitcoin.conf"
    print_check "bitcoin.conf"

    # lnd.conf
    sed -e "s|{{BITCOIN_RPC_USER}}|${rpc_user}|g" \
        -e "s|{{BITCOIN_RPC_PASSWORD}}|${rpc_password}|g" \
        -e "s|{{TOR_CONTROL_PASSWORD}}|${tor_password}|g" \
        "${configs_dir}/lnd.conf.template" > "${configs_dir}/lnd.conf"
    print_check "lnd.conf"

    # electrs.toml
    sed -e "s|{{BITCOIN_RPC_USER}}|${rpc_user}|g" \
        -e "s|{{BITCOIN_RPC_PASSWORD}}|${rpc_password}|g" \
        "${configs_dir}/electrs.toml.template" > "${configs_dir}/electrs.toml"
    print_check "electrs.toml"

    # torrc
    sed "s|{{TOR_HASHED_PASSWORD}}|${tor_hashed}|g" \
        "${configs_dir}/torrc.template" > "${configs_dir}/torrc"
    print_check "torrc"

    # .env
    print_check ".env"

    # Create data directories
    for dir in bitcoin lnd electrs tor scb; do
        mkdir -p "$(awning_path "data/${dir}")"
    done
}

# Generate rpcauth line compatible with Bitcoin Core
# Uses openssl on host if available, otherwise runs via Docker with Python
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
        log_error "Failed to generate RPC auth credentials"
        exit 1
    fi

    echo "rpcauth=${user}:${salt}\$${hmac}"
}

# Generate Tor hashed control password via Docker
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
        log_error "Failed to generate Tor password hash"
        exit 1
    fi

    echo "$hash"
}

# ============================================================
# Step 4: Build Docker images
# ============================================================
step_build_and_start() {
    print_step "Step 4/6: Building Docker Images"
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

    # Step 5: Start services
    print_step "Step 5/6: Starting Services"
    echo ""
    ensure_lnd_password_file
    dc_start_services
}

# ============================================================
# Step 6: Initialize LND wallet
# ============================================================
step_initialize_wallet() {
    print_step "Step 6/6: Initialize LND Wallet"
    echo ""

    local macaroon
    macaroon="$(awning_path data/lnd/data/chain/bitcoin/mainnet/admin.macaroon)"
    if [[ -f "$macaroon" ]]; then
        print_info "Wallet already initialized, skipping."
        return 0
    fi

    if ! is_running lnd; then
        print_warn "LND is not running. Attempting to start required services..."
        dc_start_services lnd >/dev/null 2>&1 || true
        sleep 2
        if ! is_running lnd; then
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
        if validate_password "$lnd_password" 8; then
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
    local timeout_s=90
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
