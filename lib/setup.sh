#!/bin/bash
# Awning v2: Setup wizard
# Guided setup with polished terminal UI

run_setup() {
    draw_header "AWNING SETUP" "Bitcoin + Lightning Node"

    step_prerequisites
    step_node_config
    step_scb_config
    step_generate_configs
    step_build_and_start

    echo ""
    echo -e "  ${ICON_BOLT} ${BOLD}Your node is starting!${NC} Bitcoin sync will take several days."
    echo -e "  Run ${CYAN}./awning.sh${NC} again to access the management menu."
    echo ""
}

# ============================================================
# Pre-step: Prerequisites
# ============================================================
step_prerequisites() {
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
        missing=1
    fi

    # Docker compose plugin
    if docker compose version &>/dev/null 2>&1 || sudo docker compose version &>/dev/null 2>&1; then
        local compose_ver
        compose_ver="$(docker compose version 2>/dev/null | grep -oP '\d+\.\d+(\.\d+)?' | head -1)" || compose_ver="unknown"
        print_check "docker compose v${compose_ver}"
    else
        print_fail "docker compose plugin not found"
        missing=1
    fi

    # Docker daemon running
    if docker info &>/dev/null 2>&1 || sudo docker info &>/dev/null 2>&1; then
        : # daemon is running, already shown via docker version
    else
        print_fail "Docker daemon is not running"
        missing=1
    fi

    # Git
    if command -v git &>/dev/null; then
        print_check "git"
    else
        print_fail "git not found"
        missing=1
    fi

    # OpenSSL
    if command -v openssl &>/dev/null; then
        print_check "openssl"
    else
        print_fail "openssl not found"
        missing=1
    fi

    # Python3 (needed for Tor hash)
    if command -v python3 &>/dev/null; then
        print_check "python3"
    else
        print_fail "python3 not found (required for Tor password hashing)"
        missing=1
    fi

    # Disk space check
    local avail_kb avail_gb
    avail_kb="$(df --output=avail "$(awning_path .)" 2>/dev/null | tail -1 | tr -d ' ')" || avail_kb=0
    avail_gb="$(echo "$avail_kb" | awk '{printf "%.1f", $1 / 1048576}')"
    local avail_gb_int="${avail_gb%.*}"

    if [[ "$avail_gb_int" -ge 900 ]]; then
        print_check "Disk space: ${avail_gb} GB available (900 GB required)"
    elif [[ "$avail_gb_int" -ge 600 ]]; then
        print_warn "Disk space: ${avail_gb} GB available (900 GB recommended)"
    else
        print_fail "Disk space: ${avail_gb} GB available (900 GB required)"
        missing=1
    fi

    # Internet connectivity
    if curl -sf --max-time 5 https://api.github.com &>/dev/null || \
       wget -q --timeout=5 -O /dev/null https://api.github.com 2>/dev/null; then
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
step_node_config() {
    print_step "Step 1/5: Node Configuration"

    # Detect architecture
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
    print_info "Architecture: ${arch}"

    # Node alias
    local node_alias
    node_alias="$(read_input "Enter LND alias" "AwningNode")"

    # Versions
    local btc_version lnd_version electrs_version
    btc_version="$(read_input "Bitcoin Core version" "29.1")"
    lnd_version="$(read_input "LND version" "0.19.3-beta")"
    electrs_version="$(read_input "Electrs version" "0.10.10")"

    # LND wallet password
    echo ""
    print_info "Set your LND wallet password (min 8 characters)"
    print_info "This password unlocks your Lightning wallet on startup"
    local lnd_password lnd_password_confirm
    while true; do
        lnd_password="$(read_password "LND wallet password")"
        if ! validate_password "$lnd_password" 8; then
            continue
        fi
        lnd_password_confirm="$(read_password "Confirm password")"
        if [[ "$lnd_password" != "$lnd_password_confirm" ]]; then
            print_fail "Passwords do not match"
            continue
        fi
        break
    done
    print_check "Password set"

    # Save to .env
    local env_file
    env_file="$(awning_path .env)"

    cat > "$env_file" <<EOF
# Awning v2 - Generated by setup wizard on $(date)
UID=$(id -u)
GID=$(id -g)
BITCOIN_ARCH=${bitcoin_arch}
LND_ARCH=${lnd_arch}
BITCOIN_CORE_VERSION=${btc_version}
LND_VERSION=${lnd_version}
ELECTRS_VERSION=${electrs_version}
NODE_ALIAS=${node_alias}
LND_PASSWORD=${lnd_password}
EOF

    # Store LND password for wallet auto-unlock
    mkdir -p "$(awning_path data/lnd)"
    echo "$lnd_password" > "$(awning_path data/lnd/password.txt)"

    echo ""
    print_check "Node configuration saved"
}

# ============================================================
# Step 2: SCB configuration
# ============================================================
step_scb_config() {
    print_step "Step 2/5: Channel Backup (SCB)"
    echo ""
    print_info "SCB automatically backs up your Lightning channel state to GitHub."
    print_info "You need a private GitHub repository and an SSH deploy key."
    echo ""

    if confirm "Enable Static Channel Backup?" "y"; then
        local scb_repo
        scb_repo="$(read_input "GitHub SSH URL (e.g. git@github.com:user/lnd-backup.git)" "")"

        if [[ -z "$scb_repo" ]]; then
            print_warn "No repository provided, SCB will be disabled"
            echo "SCB_REPO=" >> "$(awning_path .env)"
            return
        fi

        echo "SCB_REPO=${scb_repo}" >> "$(awning_path .env)"

        # Generate SSH key immediately
        local scb_ssh_dir
        scb_ssh_dir="$(awning_path data/scb/.ssh)"
        mkdir -p "$scb_ssh_dir"

        if [[ ! -f "${scb_ssh_dir}/id_ed25519" ]]; then
            ssh-keygen -t ed25519 -f "${scb_ssh_dir}/id_ed25519" -N "" -C "scb@awning" &>/dev/null
            print_check "SSH key generated"
        else
            print_info "SSH key already exists"
        fi

        # Display the public key in a box
        local pubkey
        pubkey="$(cat "${scb_ssh_dir}/id_ed25519.pub")"
        draw_content_box "Deploy Key" "$pubkey"

        echo ""
        print_info "Add this key at: ${CYAN}${scb_repo%%.git}/settings/keys/new${NC}"
        print_info "(Enable ${BOLD}Allow write access${NC})"
        echo ""

        # Interactive test
        read -r -p "$(echo -e "  Press ${BOLD}Enter${NC} to test SSH access...")" _

        printf '  Testing...'

        # Extract host from git URL (e.g., git@github.com:user/repo.git -> github.com)
        local git_host
        git_host="$(echo "$scb_repo" | sed -n 's/.*@\([^:]*\):.*/\1/p')"

        # Add host to known_hosts if not already there
        ssh-keyscan -t ed25519 "$git_host" >> "${scb_ssh_dir}/known_hosts" 2>/dev/null || true

        # Test SSH access
        local ssh_test
        ssh_test="$(ssh -i "${scb_ssh_dir}/id_ed25519" \
            -o UserKnownHostsFile="${scb_ssh_dir}/known_hosts" \
            -o StrictHostKeyChecking=no \
            -T "git@${git_host}" 2>&1)" || true

        if echo "$ssh_test" | grep -qi "successfully authenticated\|Hi \|welcome"; then
            printf '\r\033[K'
            print_check "SSH authentication OK"
        else
            printf '\r\033[K'
            print_warn "SSH test inconclusive (key may not be added yet)"
            print_info "You can add the deploy key later; SCB will retry on startup"
        fi

        # Test git clone
        local test_dir
        test_dir="$(mktemp -d)"
        if GIT_SSH_COMMAND="ssh -i ${scb_ssh_dir}/id_ed25519 -o UserKnownHostsFile=${scb_ssh_dir}/known_hosts -o StrictHostKeyChecking=no" \
           git clone "$scb_repo" "$test_dir/test" &>/dev/null 2>&1; then
            print_check "Repository access OK"
            rm -rf "$test_dir"
        else
            print_warn "Repository clone failed (deploy key may not be configured yet)"
            rm -rf "$test_dir"
        fi
    else
        echo "SCB_REPO=" >> "$(awning_path .env)"
        print_info "SCB disabled"
    fi
}

# ============================================================
# Step 3: Generate configs from templates
# ============================================================
step_generate_configs() {
    print_step "Step 3/5: Generating Configuration"

    # Generate random credentials
    local rpc_user rpc_password tor_password
    rpc_user="awning"
    rpc_password="$(generate_password 32)"
    tor_password="$(generate_password 32)"

    # Append to .env
    local env_file
    env_file="$(awning_path .env)"
    cat >> "$env_file" <<EOF
BITCOIN_RPC_USER=${rpc_user}
BITCOIN_RPC_PASSWORD=${rpc_password}
TOR_CONTROL_PASSWORD=${tor_password}
EOF

    # Generate Bitcoin rpcauth line
    local rpcauth_line
    rpcauth_line="$(generate_rpcauth "$rpc_user" "$rpc_password")"
    print_check "Bitcoin RPC credentials"

    # Generate Tor hashed password
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
generate_rpcauth() {
    local user="$1"
    local password="$2"

    local salt
    salt="$(openssl rand -hex 16)"

    local hmac
    hmac="$(echo -n "${password}" | openssl dgst -sha256 -hmac "${salt}" -binary | xxd -p -c 256)"

    echo "rpcauth=${user}:${salt}\$${hmac}"
}

# Generate Tor hashed control password
generate_tor_hash() {
    local password="$1"

    local hash
    hash="$(python3 -c "
import hashlib, os, binascii
password = b'${password}'
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
" 2>/dev/null)"

    if [[ -z "$hash" ]]; then
        log_error "Failed to generate Tor password hash (python3 required)"
        exit 1
    fi

    echo "$hash"
}

# ============================================================
# Step 4: Build Docker images
# ============================================================
step_build_and_start() {
    print_step "Step 4/5: Building Docker Images"
    echo ""
    print_info "Building Electrs from source can take ${BOLD}up to 1 hour${NC} on ARM."
    echo ""

    if ! confirm "Start building?" "y"; then
        echo ""
        print_info "You can build and start later with: ./awning.sh start"
        return 0
    fi

    echo ""
    dc_build_services

    # Step 5: Start services
    print_step "Step 5/5: Starting Services"
    echo ""
    dc_start_services
}
