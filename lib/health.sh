#!/bin/bash
# Awning v2: Health and status checks
# Service status, blockchain sync progress, and connection info

# Show status of all services
show_status() {
    log_step "Service Status"
    echo ""

    # Docker compose status
    dc_ps
    echo ""

    # Bitcoin sync status
    if is_running bitcoin; then
        show_bitcoin_status
    else
        log_warn "Bitcoin Core is not running"
    fi

    echo ""

    # LND status
    if is_running lnd; then
        show_lnd_status
    else
        log_warn "LND is not running"
    fi

    echo ""

    # Electrs status
    if is_running electrs; then
        log_success "Electrs is running"
    else
        log_warn "Electrs is not running"
    fi

    # Tor hidden services
    if is_running tor; then
        show_tor_status
    else
        log_warn "Tor is not running"
    fi
}

# Bitcoin Core sync status with progress bar
show_bitcoin_status() {
    local info
    info="$(bitcoin_cli getblockchaininfo 2>/dev/null)" || {
        log_warn "Bitcoin Core: cannot connect (starting up?)"
        return
    }

    local chain blocks headers progress size
    chain="$(echo "$info" | jq -r '.chain')"
    blocks="$(echo "$info" | jq -r '.blocks')"
    headers="$(echo "$info" | jq -r '.headers')"
    progress="$(echo "$info" | jq -r '.verificationprogress')"
    size="$(echo "$info" | jq -r '.size_on_disk')"

    # Convert progress to percentage
    local pct
    pct="$(echo "$progress" | awk '{printf "%.2f", $1 * 100}')"

    # Convert size to GB
    local size_gb
    size_gb="$(echo "$size" | awk '{printf "%.1f", $1 / 1073741824}')"

    echo -e "${BOLD}Bitcoin Core${NC} (${chain})"
    echo -e "  Blocks:   ${blocks} / ${headers}"
    echo -e "  Size:     ${size_gb} GB"

    # Progress bar
    local bar_width=40
    local filled
    filled="$(echo "$pct $bar_width" | awk '{printf "%d", ($1 / 100) * $2}')"
    local empty=$((bar_width - filled))

    printf "  Sync:     ["
    printf "%0.s#" $(seq 1 "$filled" 2>/dev/null) || true
    printf "%0.s-" $(seq 1 "$empty" 2>/dev/null) || true
    printf "] %s%%\n" "$pct"

    # Peer info
    local peers
    peers="$(bitcoin_cli getconnectioncount 2>/dev/null)" || peers="?"
    echo -e "  Peers:    ${peers}"
}

# LND status
show_lnd_status() {
    local info
    info="$(lncli getinfo 2>/dev/null)" || {
        log_warn "LND: cannot connect (wallet locked or starting up?)"
        return
    }

    local alias synced_chain synced_graph num_peers num_channels
    alias="$(echo "$info" | jq -r '.alias')"
    synced_chain="$(echo "$info" | jq -r '.synced_to_chain')"
    synced_graph="$(echo "$info" | jq -r '.synced_to_graph')"
    num_peers="$(echo "$info" | jq -r '.num_peers')"
    num_channels="$(echo "$info" | jq -r '.num_active_channels')"

    echo -e "${BOLD}LND${NC} (${alias})"
    echo -e "  Chain sync:   $(bool_icon "$synced_chain")"
    echo -e "  Graph sync:   $(bool_icon "$synced_graph")"
    echo -e "  Peers:        ${num_peers}"
    echo -e "  Channels:     ${num_channels}"

    # Balance
    local balance
    balance="$(lncli walletbalance 2>/dev/null)" || return
    local onchain
    onchain="$(echo "$balance" | jq -r '.total_balance')"
    echo -e "  On-chain:     ${onchain} sats"

    local ch_balance
    ch_balance="$(lncli channelbalance 2>/dev/null)" || return
    local lightning
    lightning="$(echo "$ch_balance" | jq -r '.local_balance.sat // "0"')"
    echo -e "  Lightning:    ${lightning} sats"
}

# Tor hidden service addresses
show_tor_status() {
    echo ""
    echo -e "${BOLD}Tor Hidden Services${NC}"

    local tor_data
    tor_data="$(awning_path data/tor)"

    # LND REST
    local lnd_onion="${tor_data}/hidden_service_lnd_rest/hostname"
    if [[ -f "$lnd_onion" ]]; then
        echo -e "  LND REST:   $(cat "$lnd_onion"):8080"
    else
        echo -e "  LND REST:   (not yet generated)"
    fi

    # Electrs
    local electrs_onion="${tor_data}/hidden_service_electrs/hostname"
    if [[ -f "$electrs_onion" ]]; then
        echo -e "  Electrs:    $(cat "$electrs_onion"):50001"
    else
        echo -e "  Electrs:    (not yet generated)"
    fi
}

# Boolean icon helper
bool_icon() {
    if [[ "$1" == "true" ]]; then
        echo -e "${GREEN}yes${NC}"
    else
        echo -e "${YELLOW}no${NC}"
    fi
}

# Show connection info for wallets (Zeus, Sparrow, etc.)
show_connections() {
    log_step "Connection Info"

    echo ""
    echo -e "${BOLD}Local Network${NC}"
    local local_ip
    local_ip="$(hostname -I 2>/dev/null | awk '{print $1}')" || local_ip="<your-ip>"
    echo -e "  LND REST (TLS):    https://${local_ip}:8080"
    echo -e "  Electrs (SSL):     ${local_ip}:50002"

    show_tor_status

    echo ""
    echo -e "${BOLD}Zeus Wallet${NC}"
    if is_running lnd; then
        local lnd_data
        lnd_data="$(awning_path data/lnd)"
        if [[ -f "${lnd_data}/data/chain/bitcoin/mainnet/admin.macaroon" ]]; then
            log_info "Generate Zeus connection QR with: ./awning.sh zeus-connect"
        else
            log_warn "LND macaroon not yet generated (wallet needs to be created first)"
        fi
    else
        log_warn "LND is not running"
    fi
}

# Generate Zeus connection QR using lndconnect
zeus_connect() {
    log_step "Zeus Wallet Connection"

    if ! is_running lnd; then
        log_error "LND is not running"
        return 1
    fi

    local tor_data lnd_onion
    tor_data="$(awning_path data/tor)"
    lnd_onion="${tor_data}/hidden_service_lnd_rest/hostname"

    if [[ ! -f "$lnd_onion" ]]; then
        log_error "Tor hidden service not yet generated"
        return 1
    fi

    local onion
    onion="$(cat "$lnd_onion")"

    log_info "Generating lndconnect URI for Zeus..."
    dc_exec lnd lndconnect \
        --host="${onion}" \
        --port=8080 \
        --adminmacaroonpath=/data/.lnd/data/chain/bitcoin/mainnet/admin.macaroon \
        --tlscertpath=/data/.lnd/tls.cert \
        --nocert

    echo ""
    log_info "Use the URI above to connect Zeus wallet"
    log_info "In Zeus: Add Node > lndconnect REST"
}
