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

    local services
    local bitcoin_wait_detail=""
    if dc_is_running bitcoin 2>/dev/null; then
        local binfo bprogress bblocks bheaders bibd bpct
        binfo="$(bitcoin_cli getblockchaininfo 2>/dev/null)" || binfo=""
        if [[ -n "$binfo" ]]; then
            bprogress="$(echo "$binfo" | jq -r '.verificationprogress // empty')"
            bblocks="$(echo "$binfo" | jq -r '.blocks // 0')"
            bheaders="$(echo "$binfo" | jq -r '.headers // 0')"
            bibd="$(echo "$binfo" | jq -r '.initialblockdownload // false')"
            bpct="$(echo "${bprogress:-0}" | awk '{printf "%.2f", $1 * 100}')"
            if [[ "$bibd" == "true" ]] || [[ "${bblocks:-0}" -lt "${bheaders:-0}" ]] || (( $(echo "${bpct:-0} < 99.99" | bc -l 2>/dev/null || echo 0) )); then
                bitcoin_wait_detail="waiting for bitcoin sync (${bpct}%)"
            fi
        fi
    fi

    read -ra services <<< "$(dc_active_services)"
    printf "  %-10s %-12s %s\n" "SERVICE" "STATE" "DETAILS"
    echo -e "  ${DIM}---------------------------------------------${NC}"
    for service in "${services[@]}"; do
        local status health detail state_label
        status="$(dc_get_status "$service")"
        health="$(dc_get_health "$service")"
        detail=""
        state_label=""

        if [[ -z "$status" ]]; then
            printf "  %-10s ${RED}%-12s${NC} %s\n" "$service" "not found" ""
        else
            case "$status" in
                restarting)
                    if [[ ("$service" == "lnd" || "$service" == "electrs") && -n "$bitcoin_wait_detail" ]]; then
                        detail="$bitcoin_wait_detail"
                    fi
                    state_label="restarting"
                    printf "  %-10s ${YELLOW}%-12s${NC} %s\n" "$service" "$state_label" "$detail"
                    ;;
                running)
                    if [[ "$health" == "healthy" ]]; then
                        state_label="healthy"
                        printf "  %-10s ${GREEN}%-12s${NC} %s\n" "$service" "$state_label" "$detail"
                    elif [[ "$health" == "starting" ]]; then
                        if [[ ("$service" == "lnd" || "$service" == "electrs") && -n "$bitcoin_wait_detail" ]]; then
                            detail="$bitcoin_wait_detail"
                        fi
                        state_label="starting"
                        printf "  %-10s ${YELLOW}%-12s${NC} %s\n" "$service" "$state_label" "$detail"
                    elif [[ "$health" == "unhealthy" ]]; then
                        if [[ ("$service" == "lnd" || "$service" == "electrs") && -n "$bitcoin_wait_detail" ]]; then
                            detail="$bitcoin_wait_detail"
                        fi
                        state_label="unhealthy"
                        printf "  %-10s ${RED}%-12s${NC} %s\n" "$service" "$state_label" "$detail"
                    else
                        state_label="running"
                        printf "  %-10s ${GREEN}%-12s${NC} %s\n" "$service" "$state_label" "$detail"
                    fi
                    ;;
                exited|dead)
                    state_label="$status"
                    printf "  %-10s ${RED}%-12s${NC} %s\n" "$service" "$state_label" "$detail"
                    ;;
                *)
                    state_label="$status"
                    printf "  %-10s ${RED}%-12s${NC} %s\n" "$service" "$state_label" "$detail"
                    ;;
            esac
        fi
    done

    echo ""

    # Bitcoin sync status
    if dc_is_running bitcoin; then
        show_bitcoin_status
    fi

    # LND status
    if dc_is_running lnd; then
        show_lnd_status
    fi

    # Electrs status
    if dc_is_running electrs; then
        show_electrs_status
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

    # Progress bar (progress_bar already outputs a trailing newline)
    printf '  '
    progress_bar "$progress" 1 30 ""

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

# Electrs status with indexing progress (best effort from logs)
show_electrs_status() {
    local health
    health="$(dc_get_health electrs)"
    [[ -z "$health" ]] && health="unknown"

    local logs last_chain_line last_index_line electrs_height electrs_tip index_range
    logs="$(_docker logs --tail 200 electrs 2>/dev/null)" || logs=""
    if [[ -z "$logs" ]]; then
        logs="$(_dc logs --no-log-prefix --tail 200 electrs 2>/dev/null)" || logs=""
    fi
    last_chain_line="$(echo "$logs" | grep 'chain updated: tip=' | tail -1)" || last_chain_line=""
    last_index_line="$(echo "$logs" | grep 'indexing ' | tail -1)" || last_index_line=""

    electrs_height="$(echo "$last_chain_line" | sed -n 's/.*height=\([0-9]\+\).*/\1/p')"
    electrs_tip="$(echo "$last_chain_line" | sed -n 's/.*tip=\([0-9a-f]\{64\}\).*/\1/p')"
    index_range="$(echo "$last_index_line" | sed -n 's/.*indexing [0-9]\+ blocks: \(\[[0-9]\+\.\.[0-9]\+\]\).*/\1/p')"

    local availability="unknown"
    local availability_detail=""
    local ready_icon="${GREEN}✓${NC}"
    local wait_icon="${YELLOW}…${NC}"

    echo -e "  ${BOLD}Electrs${NC}"
    echo -e "    Health:      ${health}"

    if [[ -n "$electrs_height" ]]; then
        echo -e "    Indexed:     height ${electrs_height}"
    fi

    if [[ -n "$index_range" ]]; then
        echo -e "    Indexing:    ${index_range}"
    fi

    # If Electrs logs show active indexing, it is not yet usable.
    if [[ -n "$index_range" ]]; then
        availability="not ready"
        availability_detail="syncing"
    fi

    if [[ -n "$electrs_height" ]] && dc_is_running bitcoin 2>/dev/null; then
        local binfo bheight pct
        binfo="$(bitcoin_cli getblockchaininfo 2>/dev/null)" || binfo=""
        bheight="$(echo "$binfo" | jq -r '.blocks // empty' 2>/dev/null)" || bheight=""
        if [[ -n "$bheight" ]] && [[ "$bheight" =~ ^[0-9]+$ ]] && [[ "$bheight" -gt 0 ]]; then
            pct="$(awk -v e="$electrs_height" -v b="$bheight" 'BEGIN { printf "%.2f", (e*100)/b }')"
            echo -e "    Progress:    ${pct}% (${electrs_height}/${bheight})"
            if [[ "$electrs_height" -lt "$bheight" ]]; then
                availability="not ready"
                availability_detail="syncing"
            else
                if [[ "$availability" != "not ready" ]]; then
                    availability="ready"
                fi
            fi
        fi
    fi

    if [[ -n "$electrs_tip" ]]; then
        echo -e "    Tip:         ${electrs_tip}"
    fi

    # Fallback readiness when height comparison is unavailable.
    if [[ "$availability" == "unknown" ]]; then
        if [[ -n "$index_range" ]] || [[ "$health" == "starting" ]]; then
            availability="not ready"
            availability_detail="syncing"
        elif [[ "$health" == "healthy" ]]; then
            availability="unknown"
            availability_detail="cannot verify sync progress"
        else
            availability="not ready"
            availability_detail="$health"
        fi
    fi

    if [[ "$availability" == "ready" ]]; then
        echo -e "    Usability:   ${ready_icon} ready for wallets"
    elif [[ "$availability" == "unknown" ]]; then
        echo -e "    Usability:   ${YELLOW}?${NC} unknown ${DIM}(${availability_detail})${NC}"
    else
        echo -e "    Usability:   ${wait_icon} not ready ${DIM}(${availability_detail})${NC}"
    fi

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
        echo -e "    LND REST:  $(cat "$lnd_onion"):${LND_REST_DEFAULT_PORT}"
    else
        echo -e "    LND REST:  ${DIM}(not yet generated)${NC}"
    fi

    # Electrs
    local electrs_onion="${tor_data}/hidden_service_electrs/hostname"
    if [[ -f "$electrs_onion" ]]; then
        echo -e "    Electrs:   $(cat "$electrs_onion"):${ELECTRS_TCP_PORT}"
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
    local local_ip lnd_bind lnd_port electrs_bind electrs_port lnd_host electrs_host
    local_ip="$(hostname -I 2>/dev/null | awk '{print $1}')" || local_ip="<your-ip>"
    lnd_bind="${LND_REST_BIND:-127.0.0.1}"
    lnd_port="${LND_REST_PORT:-8080}"
    electrs_bind="${ELECTRS_SSL_BIND:-127.0.0.1}"
    electrs_port="${ELECTRS_SSL_PORT:-50002}"
    lnd_host="${lnd_bind}"
    electrs_host="${electrs_bind}"
    [[ "$lnd_bind" == "0.0.0.0" ]] && lnd_host="$local_ip"
    [[ "$electrs_bind" == "0.0.0.0" ]] && electrs_host="$local_ip"

    echo -e "    LND REST (TLS):  https://${lnd_host}:${lnd_port}"
    echo -e "    Electrs (SSL):   ${electrs_host}:${electrs_port}"
    echo ""

    # Tor addresses
    if dc_is_running tor; then
        show_tor_status
    else
        echo -e "  ${BOLD}Tor Hidden Services${NC}"
        print_warn "Tor is not running"
        echo ""
    fi

    # Zeus info
    echo -e "  ${BOLD}Zeus Wallet${NC}"
    if dc_is_running lnd; then
        local lnd_data
        lnd_data="$(awning_path data/lnd)"
        if [[ -f "${lnd_data}/${ADMIN_MACAROON_SUBPATH}" ]]; then
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

    if ! dc_is_running lnd; then
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
    local macaroon
    macaroon="$(awning_path "data/lnd/${ADMIN_MACAROON_SUBPATH}")"

    if [[ ! -f "$macaroon" ]]; then
        print_fail "LND admin macaroon not found (create and unlock wallet first)"
        return 1
    fi

    print_info "Generating lndconnect URI for Zeus..."
    echo ""
    if ! dc_exec lnd lndconnect \
        --host="${onion}" \
        --port="${LND_REST_DEFAULT_PORT}" \
        --adminmacaroonpath=/data/.lnd/data/chain/bitcoin/mainnet/admin.macaroon \
        --tlscertpath=/data/.lnd/tls.cert \
        --nocert; then
        print_fail "Failed to generate lndconnect URI"
        return 1
    fi

    echo ""
    print_info "In Zeus: ${BOLD}Add Node${NC} > ${BOLD}lndconnect REST${NC}"
}
