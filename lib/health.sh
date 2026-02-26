#!/bin/bash
# Awning v2: Health and status checks
# Dashboard-style service status, sync progress, and connection info

# Show status dashboard
show_status() {
    draw_header "AWNING v$(get_awning_version)" "Service Dashboard"
    echo ""

    # Fetch Bitcoin blockchain info once (reused by sub-functions)
    local _cached_binfo=""
    if dc_is_running bitcoin 2>/dev/null; then
        _cached_binfo="$(bitcoin_cli getblockchaininfo 2>/dev/null)" || _cached_binfo=""
    fi

    # Service status table
    echo -e "  ${BOLD}Services${NC}"
    echo ""

    local services
    local bitcoin_sync_detail=""
    if [[ -n "$_cached_binfo" ]]; then
        local bblocks bheaders bpct _bsize bibd snapshot
        snapshot="$(domain_parse_bitcoin_sync_snapshot "$_cached_binfo" 2>/dev/null)" || snapshot=""
        if [[ -n "$snapshot" ]]; then
            IFS=$'\t' read -r bblocks bheaders bpct _bsize bibd <<< "$snapshot"
        fi
        if domain_bitcoin_sync_active "${bblocks:-0}" "${bheaders:-0}" "${bpct:-0}" "${bibd:-false}"; then
            bitcoin_sync_detail="sync (${bpct}%)"
        fi
    fi

    read -ra services <<< "$(dc_active_services)"
    printf "  %-10s %-12s %s\n" "SERVICE" "STATE" "DETAILS"
    echo -e "  ${DIM}---------------------------------------------${NC}"
    for service in "${services[@]}"; do
        local status health detail state_label
        status="$(dc_get_status "$service")"
        health="$(dc_get_health "$service")"
        detail="-"
        state_label=""

        # Show sync progress on the bitcoin row
        if [[ "$service" == "bitcoin" && -n "$bitcoin_sync_detail" ]]; then
            detail="$bitcoin_sync_detail"
        fi

        if [[ "$service" == "electrs" && -n "$bitcoin_sync_detail" ]]; then
            detail="waiting for bitcoin sync"
        fi

        if [[ -z "$status" ]]; then
            printf "  %-10s ${DIM}%-12s${NC} %s\n" "$service" "stopped" ""
        else
            case "$status" in
                restarting)
                    state_label="restarting"
                    printf "  %-10s ${YELLOW}%-12s${NC} %s\n" "$service" "$state_label" "$detail"
                    ;;
                running)
                    if [[ "$health" == "healthy" ]]; then
                        state_label="healthy"
                        printf "  %-10s ${GREEN}%-12s${NC} %s\n" "$service" "$state_label" "$detail"
                    elif [[ "$health" == "starting" ]]; then
                        state_label="starting"
                        printf "  %-10s ${YELLOW}%-12s${NC} %s\n" "$service" "$state_label" "$detail"
                    elif [[ "$health" == "unhealthy" ]]; then
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
        show_bitcoin_status "$_cached_binfo"
    fi

    # LND status
    if dc_is_running lnd; then
        show_lnd_status
    fi

    # Electrs status
    if dc_is_running electrs; then
        show_electrs_status "$_cached_binfo"
    fi

}

# Bitcoin Core sync status with progress bar
# Args: $1 - cached getblockchaininfo JSON (optional, fetched if empty)
show_bitcoin_status() {
    local info="${1:-}"
    if [[ -z "$info" ]]; then
        info="$(bitcoin_cli getblockchaininfo 2>/dev/null)" || {
            echo -e "  ${BOLD}Bitcoin Core${NC}"
            print_warn "Cannot connect (starting up?)"
            echo ""
            return
        }
    fi

    local chain blocks headers pct size_gb _ibd snapshot
    chain="$(echo "$info" | jq -r '.chain')"
    snapshot="$(domain_parse_bitcoin_sync_snapshot "$info" 2>/dev/null)" || snapshot=""
    if [[ -n "$snapshot" ]]; then
        IFS=$'\t' read -r blocks headers pct size_gb _ibd <<< "$snapshot"
    else
        blocks="$(echo "$info" | jq -r '.blocks')"
        headers="$(echo "$info" | jq -r '.headers')"
        pct="$(echo "$(echo "$info" | jq -r '.verificationprogress')" | LC_ALL=C awk '{printf "%.2f", $1 * 100}')"
        size_gb="$(echo "$(echo "$info" | jq -r '.size_on_disk')" | awk '{printf "%.1f", $1 / 1073741824}')"
    fi

    echo -e "  ${BOLD}Bitcoin Core${NC} ${DIM}(${chain})${NC}"
    echo -e "    Blocks:  ${blocks} / ${headers}"
    echo -e "    Size:    ${size_gb} GB"

    # Progress bar (progress_bar already outputs a trailing newline)
    printf '  '
    progress_bar "$pct" 100 30 ""

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
# Args: $1 - cached Bitcoin getblockchaininfo JSON (optional)
show_electrs_status() {
    local cached_binfo="${1:-}"

    echo -e "  ${BOLD}Electrs${NC}"

    local health
    health="$(dc_get_health electrs)"
    [[ -z "$health" ]] && health="unknown"

    # --- Parse Electrs logs for sync state ---
    local logs
    logs="$(_docker logs --tail 200 electrs 2>/dev/null)" || logs=""
    [[ -z "$logs" ]] && logs="$(_dc logs --no-log-prefix --tail 200 electrs 2>/dev/null)" || true

    local last_chain_line last_index_line last_ibd_line
    last_chain_line="$(echo "$logs" | grep 'chain updated: tip=' | tail -1)" || true
    last_index_line="$(echo "$logs" | grep 'indexing ' | tail -1)" || true
    last_ibd_line="$(echo "$logs" | grep -E 'waiting for [0-9]+ blocks to download \(IBD\)' | tail -1)" || true

    local electrs_height index_range
    electrs_height="$(echo "$last_chain_line" | sed -n 's/.*height=\([0-9]\+\).*/\1/p')"
    index_range="$(echo "$last_index_line" | sed -n 's/.*indexing [0-9]\+ blocks: \(\[[0-9]\+\.\.[0-9]\+\]\).*/\1/p')"

    # --- Resolve Bitcoin blockchain info (use cache when available) ---
    local binfo=""
    if dc_is_running bitcoin 2>/dev/null; then
        binfo="${cached_binfo:-}"
        [[ -z "$binfo" ]] && { binfo="$(bitcoin_cli getblockchaininfo 2>/dev/null)" || binfo=""; }
    fi

    local bheight="" bibd="false"
    if [[ -n "$binfo" ]]; then
        bheight="$(echo "$binfo" | jq -r '.blocks // empty' 2>/dev/null)" || bheight=""
        bibd="$(echo "$binfo" | jq -r '.initialblockdownload // false')"
    fi

    # --- Determine usability with early returns ---
    local availability="unknown" availability_detail=""

    # Primary: compare Electrs height to Bitcoin height
    if [[ -n "$electrs_height" && -n "$bheight" ]] && [[ "$bheight" =~ ^[0-9]+$ ]] && (( bheight > 0 )); then
        local pct lag
        pct="$(awk -v e="$electrs_height" -v b="$bheight" 'BEGIN { printf "%.2f", (e*100)/b }')"
        echo -e "    Progress:    ${pct}% (${electrs_height}/${bheight})"
        lag=$((bheight - electrs_height))
        if (( lag <= 2 )); then
            availability="ready"
        elif [[ "$bibd" == "true" ]]; then
            availability="not ready"; availability_detail="waiting for bitcoin sync"
        else
            availability="not ready"; availability_detail="syncing"
        fi
    # Fallback: use log heuristics
    elif [[ -n "$last_ibd_line" ]]; then
        availability="not ready"; availability_detail="waiting for bitcoin sync"
    elif [[ -n "$index_range" ]] || [[ "$health" == "starting" ]]; then
        availability="not ready"; availability_detail="syncing"
    elif [[ "$bibd" == "true" ]]; then
        availability="not ready"; availability_detail="waiting for bitcoin sync"
    elif [[ "$health" == "healthy" ]]; then
        availability="unknown"; availability_detail="cannot verify sync progress"
    elif [[ "$health" != "unknown" ]]; then
        availability="not ready"; availability_detail="$health"
    fi

    # --- Render usability ---
    case "$availability" in
        ready)     echo -e "    Usability:   ${GREEN}✓${NC} ready for wallets" ;;
        unknown)   echo -e "    Usability:   ${YELLOW}?${NC} unknown ${DIM}(${availability_detail})${NC}" ;;
        *)         echo -e "    Usability:   ${YELLOW}…${NC} not ready ${DIM}(${availability_detail})${NC}" ;;
    esac

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

    # RTL (only when enabled)
    if [[ -n "${RTL_PASSWORD:-}" ]]; then
        local rtl_onion="${tor_data}/hidden_service_rtl/hostname"
        if [[ -f "$rtl_onion" ]]; then
            echo -e "    RTL:       $(cat "$rtl_onion"):${RTL_PORT}"
        else
            echo -e "    RTL:       ${DIM}(not yet generated)${NC}"
        fi
    fi

    echo ""
}

# Show connection info for wallets
show_connections() {
    draw_header "CONNECTIONS" "Wallet & Service Access"
    echo ""

    # Check if any service is running
    local running_count
    running_count="$(count_running_services)"
    if [[ "$running_count" -eq 0 ]]; then
        print_warn "Services are not running. Start them with: ${CYAN}./awning.sh start${NC}"
        echo ""
        return
    fi

    echo -e "  ${BOLD}Local Network${NC}"
    local local_ip lnd_bind lnd_port electrs_bind electrs_port
    local has_lan_service=false
    local_ip="$(get_lan_ip)"
    lnd_bind="${LND_REST_BIND:-127.0.0.1}"
    lnd_port="${LND_REST_PORT:-8080}"
    electrs_bind="${ELECTRS_SSL_BIND:-127.0.0.1}"
    electrs_port="${ELECTRS_SSL_PORT:-50002}"

    if [[ "$lnd_bind" != "127.0.0.1" ]]; then
        local lnd_host="${lnd_bind}"
        [[ "$lnd_bind" == "0.0.0.0" ]] && lnd_host="$local_ip"
        echo -e "    LND REST (TLS):  ${WHITE}${UNDERLINE}https://${lnd_host}:${lnd_port}${NC}"
        has_lan_service=true
    fi

    if [[ "$electrs_bind" != "127.0.0.1" ]]; then
        local electrs_host="${electrs_bind}"
        [[ "$electrs_bind" == "0.0.0.0" ]] && electrs_host="$local_ip"
        echo -e "    Electrs (SSL):   ${WHITE}${UNDERLINE}${electrs_host}:${electrs_port}${NC}"
        has_lan_service=true
    fi

    # RTL local URL (only when enabled and not localhost-only)
    if [[ -n "${RTL_PASSWORD:-}" ]]; then
        local rtl_bind rtl_port
        rtl_bind="${RTL_BIND:-127.0.0.1}"
        rtl_port="${RTL_PORT:-3001}"
        if [[ "$rtl_bind" != "127.0.0.1" ]]; then
            local rtl_host="${rtl_bind}"
            [[ "$rtl_bind" == "0.0.0.0" ]] && rtl_host="$local_ip"
            echo -e "    RTL Web UI:      ${WHITE}${UNDERLINE}https://${rtl_host}:${rtl_port}${NC}"
            echo -e "                     ${ORANGE}Browser will warn about the self-signed cert${NC}"
            echo -e "                     ${ORANGE}Click Advanced > Proceed on your browser${NC}"
            has_lan_service=true
        fi
    fi

    if [[ "$has_lan_service" == false ]]; then
        print_info "No services exposed on local network (all bound to localhost)"
    fi

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
            print_info "Generate connection with: ${CYAN}Wallet > Zeus connect${NC} ${DIM}or${NC} ${CYAN}./awning.sh zeus-connect${NC}"
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
