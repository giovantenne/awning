#!/bin/bash
# Awning v2: Health and status checks
# Dashboard-style service status, sync progress, and connection info

# Show status dashboard
show_status() {
    draw_header "AWNING STATUS" "Service Dashboard"
    echo ""

    # Service status table
    echo -e "  ${BOLD}Services${NC}"
    echo ""

    for service in "${ALL_SERVICES[@]}"; do
        local status
        status="$(eval "$(_compose_cmd) ps --format '{{.Status}}' ${service} 2>/dev/null")" || status=""

        if [[ -z "$status" ]]; then
            print_fail "${service}  ${DIM}not found${NC}"
        elif echo "$status" | grep -qi "up\|running\|healthy"; then
            local uptime
            uptime="$(echo "$status" | grep -oP '\(\K[^)]+' | head -1)" || uptime=""
            if [[ -n "$uptime" ]]; then
                print_check "${service}  ${DIM}${uptime}${NC}"
            else
                print_check "${service}"
            fi
        else
            print_fail "${service}  ${DIM}${status}${NC}"
        fi
    done

    echo ""

    # Bitcoin sync status
    if is_running bitcoin; then
        show_bitcoin_status
    fi

    # LND status
    if is_running lnd; then
        show_lnd_status
    fi
}

# Bitcoin Core sync status with progress bar
show_bitcoin_status() {
    local info
    info="$(bitcoin_cli getblockchaininfo 2>/dev/null)" || {
        echo -e "  ${BOLD}Bitcoin Core${NC}"
        print_warn "Cannot connect (starting up?)"
        echo ""
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

    echo -e "  ${BOLD}Bitcoin Core${NC} ${DIM}(${chain})${NC}"
    echo -e "    Blocks:  ${blocks} / ${headers}"
    echo -e "    Size:    ${size_gb} GB"

    # Progress bar
    printf '  '
    progress_bar "$progress" 1 30 ""
    printf '\n' # extra line after section

    # Peer info
    local peers
    peers="$(bitcoin_cli getconnectioncount 2>/dev/null)" || peers="?"
    echo -e "    Peers:   ${peers}"

    echo ""
}

# LND status with balances
show_lnd_status() {
    local info
    info="$(lncli getinfo 2>/dev/null)" || {
        echo -e "  ${BOLD}LND${NC}"
        print_warn "Cannot connect (wallet locked or starting up?)"
        echo ""
        return
    }

    local alias synced_chain synced_graph num_peers num_channels
    alias="$(echo "$info" | jq -r '.alias')"
    synced_chain="$(echo "$info" | jq -r '.synced_to_chain')"
    synced_graph="$(echo "$info" | jq -r '.synced_to_graph')"
    num_peers="$(echo "$info" | jq -r '.num_peers')"
    num_channels="$(echo "$info" | jq -r '.num_active_channels')"

    echo -e "  ${BOLD}LND${NC} ${DIM}(${alias})${NC}"
    echo -e "    Chain sync:  $(bool_icon "$synced_chain")"
    echo -e "    Graph sync:  $(bool_icon "$synced_graph")"
    echo -e "    Peers:       ${num_peers}"
    echo -e "    Channels:    ${num_channels}"

    # Balance
    local balance
    balance="$(lncli walletbalance 2>/dev/null)" || return
    local onchain
    onchain="$(echo "$balance" | jq -r '.total_balance')"
    echo -e "    On-chain:    ${onchain} sats"

    local ch_balance
    ch_balance="$(lncli channelbalance 2>/dev/null)" || return
    local lightning
    lightning="$(echo "$ch_balance" | jq -r '.local_balance.sat // "0"')"
    echo -e "    Lightning:   ${lightning} sats"

    echo ""
}

# Tor hidden service addresses
show_tor_status() {
    echo -e "  ${BOLD}Tor Hidden Services${NC}"

    local tor_data
    tor_data="$(awning_path data/tor)"

    # LND REST
    local lnd_onion="${tor_data}/hidden_service_lnd_rest/hostname"
    if [[ -f "$lnd_onion" ]]; then
        echo -e "    LND REST:  $(cat "$lnd_onion"):8080"
    else
        echo -e "    LND REST:  ${DIM}(not yet generated)${NC}"
    fi

    # Electrs
    local electrs_onion="${tor_data}/hidden_service_electrs/hostname"
    if [[ -f "$electrs_onion" ]]; then
        echo -e "    Electrs:   $(cat "$electrs_onion"):50001"
    else
        echo -e "    Electrs:   ${DIM}(not yet generated)${NC}"
    fi

    echo ""
}

# Show connection info for wallets
show_connections() {
    draw_header "CONNECTIONS" "Wallet & Service Access"
    echo ""

    echo -e "  ${BOLD}Local Network${NC}"
    local local_ip
    local_ip="$(hostname -I 2>/dev/null | awk '{print $1}')" || local_ip="<your-ip>"
    echo -e "    LND REST (TLS):  https://${local_ip}:8080"
    echo -e "    Electrs (SSL):   ${local_ip}:50002"
    echo ""

    # Tor addresses
    if is_running tor; then
        show_tor_status
    else
        echo -e "  ${BOLD}Tor Hidden Services${NC}"
        print_warn "Tor is not running"
        echo ""
    fi

    # Zeus info
    echo -e "  ${BOLD}Zeus Wallet${NC}"
    if is_running lnd; then
        local lnd_data
        lnd_data="$(awning_path data/lnd)"
        if [[ -f "${lnd_data}/data/chain/bitcoin/mainnet/admin.macaroon" ]]; then
            print_info "Generate connection with: ${CYAN}./awning.sh zeus-connect${NC}"
        else
            print_warn "LND macaroon not yet generated (create wallet first)"
        fi
    else
        print_warn "LND is not running"
    fi
    echo ""
}

# Generate Zeus connection QR using lndconnect
zeus_connect() {
    draw_header "ZEUS CONNECT" "Wallet Connection"
    echo ""

    if ! is_running lnd; then
        print_fail "LND is not running"
        return 1
    fi

    local tor_data lnd_onion
    tor_data="$(awning_path data/tor)"
    lnd_onion="${tor_data}/hidden_service_lnd_rest/hostname"

    if [[ ! -f "$lnd_onion" ]]; then
        print_fail "Tor hidden service not yet generated"
        return 1
    fi

    local onion
    onion="$(cat "$lnd_onion")"

    print_info "Generating lndconnect URI for Zeus..."
    echo ""
    dc_exec lnd lndconnect \
        --host="${onion}" \
        --port=8080 \
        --adminmacaroonpath=/data/.lnd/data/chain/bitcoin/mainnet/admin.macaroon \
        --tlscertpath=/data/.lnd/tls.cert \
        --nocert

    echo ""
    print_info "In Zeus: ${BOLD}Add Node${NC} > ${BOLD}lndconnect REST${NC}"
}
