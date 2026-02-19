#!/bin/bash
# Awning v2: Interactive management menu
# Boxed header with live status, 6 organized categories
# All submenus have clear screen, back option, and robust input handling

show_menu() {
    while true; do
        clear 2>/dev/null || true

        # Get live status for header
        local status_label
        status_label="$(get_status_label 2>/dev/null)" || status_label="${DIM}unknown${NC}"

        draw_header "AWNING v2.0" ""
        echo -e "  ${status_label}"
        echo ""
        echo -e "  ${BOLD}${YELLOW}1)${NC} Status        ${DIM}Dashboard with sync progress${NC}"
        echo -e "  ${BOLD}${YELLOW}2)${NC} Logs          ${DIM}View service logs${NC}"
        echo -e "  ${BOLD}${YELLOW}3)${NC} Connections   ${DIM}Tor addresses, LND connect URI${NC}"
        echo -e "  ${BOLD}${YELLOW}4)${NC} Wallet        ${DIM}Create, unlock, balances${NC}"
        echo -e "  ${BOLD}${YELLOW}5)${NC} Tools         ${DIM}Start, stop, rebuild, CLI${NC}"
        echo -e "  ${BOLD}${YELLOW}6)${NC} Backup        ${DIM}SCB status, manual trigger${NC}"
        echo -e "  ${BOLD}${YELLOW}0)${NC} Exit"
        echo ""

        local choice
        read -r -p "$(echo -e "  ${CYAN}Choose [0-6]:${NC} ")" choice

        case "$choice" in
            1) show_status 2>/dev/null; menu_pause ;;
            2) menu_logs ;;
            3) show_connections 2>/dev/null; menu_pause ;;
            4) menu_wallet ;;
            5) menu_tools ;;
            6) menu_backup ;;
            0|q|Q) echo ""; exit 0 ;;
            *) ;;
        esac
    done
}

# Pause before returning to menu
menu_pause() {
    echo ""
    read -r -p "$(echo -e "  ${DIM}Press Enter to continue...${NC}")" _
}

# --- Logs submenu ---
menu_logs() {
    clear 2>/dev/null || true
    draw_header "VIEW LOGS" ""
    echo ""
    echo -e "  ${BOLD}${YELLOW}1)${NC} All services"
    echo -e "  ${BOLD}${YELLOW}2)${NC} Bitcoin Core"
    echo -e "  ${BOLD}${YELLOW}3)${NC} LND"
    echo -e "  ${BOLD}${YELLOW}4)${NC} Electrs"
    echo -e "  ${BOLD}${YELLOW}5)${NC} Tor"
    echo -e "  ${BOLD}${YELLOW}6)${NC} Nginx"
    echo -e "  ${BOLD}${YELLOW}7)${NC} SCB"
    echo -e "  ${BOLD}${YELLOW}0)${NC} Back"
    echo ""

    local choice
    read -r -p "$(echo -e "  ${CYAN}Service [0-7]:${NC} ")" choice

    local service=""
    case "$choice" in
        1) service="" ;;
        2) service="bitcoin" ;;
        3) service="lnd" ;;
        4) service="electrs" ;;
        5) service="tor" ;;
        6) service="nginx" ;;
        7) service="scb" ;;
        0|"") return ;;
        *) return ;;
    esac

    echo ""
    print_info "Showing logs (Ctrl+C to exit)..."
    # Use trap to catch Ctrl+C gracefully instead of killing the script
    (
        trap 'exit 0' INT
        if [[ -z "$service" ]]; then
            dc_logs -f --tail 50 2>/dev/null
        else
            dc_logs -f --tail 50 "$service" 2>/dev/null
        fi
    ) || true
}

# --- Tools submenu ---
menu_tools() {
    clear 2>/dev/null || true
    draw_header "TOOLS" ""
    echo ""
    echo -e "  ${BOLD}${YELLOW}1)${NC} Start          ${DIM}Start all services${NC}"
    echo -e "  ${BOLD}${YELLOW}2)${NC} Stop           ${DIM}Stop all services${NC}"
    echo -e "  ${BOLD}${YELLOW}3)${NC} Restart        ${DIM}Restart all services${NC}"
    echo -e "  ${BOLD}${YELLOW}4)${NC} Rebuild        ${DIM}Rebuild and restart${NC}"
    echo -e "  ${BOLD}${YELLOW}5)${NC} Bitcoin CLI    ${DIM}Interactive bitcoin-cli${NC}"
    echo -e "  ${BOLD}${YELLOW}6)${NC} LND CLI        ${DIM}Interactive lncli${NC}"
    echo -e "  ${BOLD}${YELLOW}0)${NC} Back"
    echo ""

    local choice
    read -r -p "$(echo -e "  ${CYAN}Choose [0-6]:${NC} ")" choice

    case "$choice" in
        1)  echo ""
            dc_start_services 2>/dev/null
            menu_pause
            ;;
        2)  echo ""
            dc_stop_services 2>/dev/null
            print_check "Services stopped"
            menu_pause
            ;;
        3)  echo ""
            dc_restart 2>/dev/null
            print_check "Services restarted"
            menu_pause
            ;;
        4)  menu_update ;;
        5)  menu_bitcoin_cli ;;
        6)  menu_lncli ;;
        0|"") ;;
        *)  ;;
    esac
}

# --- Update (rebuild) ---
menu_update() {
    clear 2>/dev/null || true
    draw_header "REBUILD" ""
    echo ""
    print_info "This will rebuild Docker images with current versions from .env"
    print_info "and restart all services."
    echo ""

    if confirm "Proceed with rebuild?" "y"; then
        echo ""
        dc_down_with_spinner 2>/dev/null || {
            menu_pause
            return
        }
        echo ""
        dc_build_services
        echo ""
        dc_start_services 2>/dev/null
        echo ""
        print_check "Rebuild complete"
    fi
    menu_pause
}

# --- Wallet submenu ---
menu_wallet() {
    while true; do
        clear 2>/dev/null || true
        draw_header "WALLET" ""
        echo ""
        echo -e "  ${BOLD}${YELLOW}1)${NC} Wallet balance    ${DIM}On-chain balance${NC}"
        echo -e "  ${BOLD}${YELLOW}2)${NC} Channel balance   ${DIM}Lightning balance${NC}"
        echo -e "  ${BOLD}${YELLOW}3)${NC} New address       ${DIM}Generate on-chain address${NC}"
        echo -e "  ${BOLD}${YELLOW}4)${NC} Zeus connect      ${DIM}Connection URI for Zeus${NC}"
        echo -e "  ${BOLD}${YELLOW}0)${NC} Back"
        echo ""

        local choice
        read -r -p "$(echo -e "  ${CYAN}Choose [0-4]:${NC} ")" choice

        case "$choice" in
            1) echo "";
               if has_admin_macaroon; then
                   show_wallet_balance_ui
               else
                   print_warn "Wallet not initialized yet. Run setup first."
               fi
               menu_pause ;;
            2) echo "";
               if has_admin_macaroon; then
                   show_channel_balance_ui
               else
                   print_warn "Wallet not initialized yet. Run setup first."
               fi
               menu_pause ;;
            3) echo "";
               if has_admin_macaroon; then
                   show_new_address_ui
               else
                   print_warn "Wallet not initialized yet. Run setup first."
               fi
               menu_pause ;;
            4) zeus_connect; menu_pause ;;
            0|"") return ;;
            *) ;;
        esac
    done
}

# Create LND wallet
wallet_create() {
    print_step "Create LND Wallet"
    echo ""

    if ! is_running lnd; then
        print_fail "LND is not running. Start services first."
        return 1
    fi

    local lnd_data
    lnd_data="$(awning_path data/lnd)"
    local password_file="${lnd_data}/password.txt"

    if [[ ! -f "$password_file" ]]; then
        print_fail "Password file not found. Run setup first."
        return 1
    fi

    print_info "Creating wallet with the setup password..."
    print_warn "IMPORTANT: Write down the seed phrase displayed below!"
    echo ""

    print_info "When prompted, enter the same password from setup."
    if dc_exec lnd lncli create
    then
        echo ""
        print_check "Wallet created"
        sync_auto_unlock_password
        print_info "Auto-unlock password updated."
        print_info "LND will now sync to the blockchain. This may take a while."
    else
        echo ""
        print_fail "Wallet creation failed"
        return 1
    fi
}

has_admin_macaroon() {
    local path
    path="$(awning_path data/lnd/data/chain/bitcoin/mainnet/admin.macaroon)"
    [[ -f "$path" ]]
}

sync_auto_unlock_password() {
    local p1 p2
    local password_file
    password_file="$(awning_path data/lnd/password.txt)"

    print_info "To enable auto-unlock, re-enter the wallet password you just used."
    while true; do
        p1="$(read_password "Wallet password")"
        if ! validate_password "$p1" 8; then
            continue
        fi
        p2="$(read_password "Confirm wallet password")"
        if [[ "$p1" != "$p2" ]]; then
            print_fail "Passwords do not match"
            continue
        fi
        break
    done

    umask 077
    printf '%s\n' "$p1" > "$password_file"
    chmod 600 "$password_file"
    print_check "Auto-unlock password saved"
}

show_wallet_balance_ui() {
    local out
    out="$(lncli walletbalance 2>/dev/null)" || {
        print_warn "Cannot connect to LND"
        return 1
    }

    if command -v jq >/dev/null 2>&1; then
        local total confirmed unconfirmed locked
        total="$(echo "$out" | jq -r '.total_balance // "0"')"
        confirmed="$(echo "$out" | jq -r '.confirmed_balance // "0"')"
        unconfirmed="$(echo "$out" | jq -r '.unconfirmed_balance // "0"')"
        locked="$(echo "$out" | jq -r '.locked_balance // "0"')"
        draw_info_box \
            "${BOLD}On-chain Wallet${NC}" \
            "Total:       ${total} sats" \
            "Confirmed:   ${confirmed} sats" \
            "Unconfirmed: ${unconfirmed} sats" \
            "Locked:      ${locked} sats"
    else
        echo "$out"
    fi
}

show_channel_balance_ui() {
    local out
    out="$(lncli channelbalance 2>/dev/null)" || {
        print_warn "Cannot connect to LND"
        return 1
    }

    if command -v jq >/dev/null 2>&1; then
        local local_sat remote_sat unsettled pending_open
        local_sat="$(echo "$out" | jq -r '.local_balance.sat // "0"')"
        remote_sat="$(echo "$out" | jq -r '.remote_balance.sat // "0"')"
        unsettled="$(echo "$out" | jq -r '.unsettled_local_balance.sat // "0"')"
        pending_open="$(echo "$out" | jq -r '.pending_open_local_balance.sat // "0"')"
        draw_info_box \
            "${BOLD}Lightning Channel Balance${NC}" \
            "Local:         ${local_sat} sats" \
            "Remote:        ${remote_sat} sats" \
            "Unsettled:     ${unsettled} sats" \
            "Pending Open:  ${pending_open} sats"
    else
        echo "$out"
    fi
}

show_new_address_ui() {
    local out
    out="$(lncli newaddress p2wkh 2>/dev/null)" || {
        print_warn "Cannot connect to LND"
        return 1
    }

    if command -v jq >/dev/null 2>&1; then
        local address addr_type
        address="$(echo "$out" | jq -r '.address // empty')"
        addr_type="$(echo "$out" | jq -r '.address_type // empty')"
        if [[ -z "$address" ]]; then
            print_warn "Failed to parse new address"
            return 1
        fi
        if [[ -z "$addr_type" || "$addr_type" == "UNKNOWN" ]]; then
            if [[ "$address" == bc1q* ]]; then
                addr_type="Bech32 (p2wkh)"
            else
                addr_type="p2wkh"
            fi
        fi
        echo -e "  ${BOLD}New Address${NC}"
        echo -e "  ${YELLOW}${address}${NC}"
    else
        echo "$out"
    fi
}

# Unlock LND wallet
wallet_unlock() {
    echo ""
    if ! is_running lnd; then
        print_fail "LND is not running"
        return 1
    fi

    local password_file
    password_file="$(awning_path data/lnd/password.txt)"

    if [[ -f "$password_file" ]]; then
        local password
        password="$(cat "$password_file")"
        if echo "$password" | dc_exec_t lnd lncli unlock --stdin; then
            print_check "Wallet unlocked"
        else
            print_fail "Wallet unlock failed"
            return 1
        fi
    else
        print_info "Enter your wallet password:"
        if dc_exec lnd lncli unlock; then
            print_check "Wallet unlocked"
        else
            print_fail "Wallet unlock failed"
            return 1
        fi
    fi
}

# --- Backup submenu ---
menu_backup() {
    clear 2>/dev/null || true
    draw_header "BACKUP (SCB)" ""
    echo ""

    # Check SCB status
    local env_file
    env_file="$(awning_path .env)"
    local scb_repo=""
    if [[ -f "$env_file" ]]; then
        scb_repo="$(grep '^SCB_REPO=' "$env_file" | cut -d= -f2-)" || true
    fi

    if [[ -z "$scb_repo" ]]; then
        print_warn "SCB is not configured"
        print_info "Run ${CYAN}./awning.sh setup${NC} to enable channel backups"
        menu_pause
        return
    fi

    echo -e "    Repository: ${scb_repo}"
    echo ""

    if is_running scb 2>/dev/null; then
        print_check "SCB service is running"
    else
        print_fail "SCB service is not running"
    fi

    # Check last backup
    local scb_data
    scb_data="$(awning_path data/scb)"
    if [[ -d "${scb_data}/backups/.git" ]]; then
        local last_commit
        last_commit="$(git -C "${scb_data}/backups" log -1 --format='%ar' 2>/dev/null)" || last_commit="not available yet"
        [[ -z "$last_commit" ]] && last_commit="not available yet"
        echo -e "    Last backup: ${last_commit}"
    fi

    echo ""
    echo -e "  ${BOLD}${YELLOW}1)${NC} Trigger backup now    ${DIM}Force a manual backup${NC}"
    echo -e "  ${BOLD}${YELLOW}2)${NC} View SCB logs         ${DIM}Recent backup activity${NC}"
    echo -e "  ${BOLD}${YELLOW}0)${NC} Back"
    echo ""

    local choice
    read -r -p "$(echo -e "  ${CYAN}Choose [0-2]:${NC} ")" choice

    case "$choice" in
        1)
            echo ""
            if is_running scb 2>/dev/null; then
                dc_restart scb 2>/dev/null &
                local restart_pid=$!
                if spinner "$restart_pid" "Triggering backup (restarting SCB)..."; then
                    print_check "Backup triggered (SCB restarted)"
                else
                    print_fail "Failed to trigger backup"
                fi
            else
                print_fail "SCB is not running"
            fi
            menu_pause
            ;;
        2)
            dc_logs --tail 30 scb 2>/dev/null || print_warn "Cannot read SCB logs"
            menu_pause
            ;;
        0|"") ;;
        *)  ;;
    esac
}

# --- Interactive CLI ---
menu_bitcoin_cli() {
    clear 2>/dev/null || true
    draw_header "BITCOIN CLI" ""
    echo ""
    print_info "Interactive bitcoin-cli ${DIM}(type 'exit' or 'quit' to return)${NC}"
    echo ""

    if ! is_running bitcoin 2>/dev/null; then
        print_fail "Bitcoin Core is not running"
        menu_pause
        return
    fi

    while true; do
        local cmd
        read -r -p "$(echo -e "  ${YELLOW}bitcoin-cli>${NC} ")" cmd || break
        [[ "$cmd" == "exit" || "$cmd" == "quit" ]] && break
        [[ -z "$cmd" ]] && continue
        bitcoin_cli $cmd 2>/dev/null || true
    done
}

menu_lncli() {
    clear 2>/dev/null || true
    draw_header "LND CLI" ""
    echo ""
    print_info "Interactive lncli ${DIM}(type 'exit' or 'quit' to return)${NC}"
    echo ""

    if ! is_running lnd 2>/dev/null; then
        print_fail "LND is not running"
        menu_pause
        return
    fi

    while true; do
        local cmd
        read -r -p "$(echo -e "  ${YELLOW}lncli>${NC} ")" cmd || break
        [[ "$cmd" == "exit" || "$cmd" == "quit" ]] && break
        [[ -z "$cmd" ]] && continue
        lncli $cmd 2>/dev/null || true
    done
}
