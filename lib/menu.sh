#!/bin/bash
# Awning v2: Interactive management menu
# Boxed header with live status, 6 organized categories

show_menu() {
    while true; do
        clear 2>/dev/null || true

        # Get live status for header
        local status_label
        status_label="$(get_status_label)"

        draw_header "AWNING v2.0" ""
        # Print status below the box
        echo -e "  ${status_label}"
        echo ""
        echo -e "  ${BOLD}1)${NC} Status        ${DIM}Dashboard with sync progress${NC}"
        echo -e "  ${BOLD}2)${NC} Logs          ${DIM}View service logs${NC}"
        echo -e "  ${BOLD}3)${NC} Connections   ${DIM}Tor addresses, LND connect URI${NC}"
        echo -e "  ${BOLD}4)${NC} Wallet        ${DIM}Create, unlock, balances${NC}"
        echo -e "  ${BOLD}5)${NC} Tools         ${DIM}Start, stop, rebuild, CLI${NC}"
        echo -e "  ${BOLD}6)${NC} Backup        ${DIM}SCB status, manual trigger${NC}"
        echo -e "  ${BOLD}0)${NC} Exit"
        echo ""

        local choice
        read -r -p "$(echo -e "  ${CYAN}Choose [0-6]:${NC} ")" choice

        case "$choice" in
            1) show_status; menu_pause ;;
            2) menu_logs ;;
            3) show_connections; menu_pause ;;
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
    echo ""
    echo -e "  ${BOLD}View Logs${NC}"
    echo ""
    echo -e "  ${BOLD}1)${NC} All services"
    echo -e "  ${BOLD}2)${NC} Bitcoin Core"
    echo -e "  ${BOLD}3)${NC} LND"
    echo -e "  ${BOLD}4)${NC} Electrs"
    echo -e "  ${BOLD}5)${NC} Tor"
    echo -e "  ${BOLD}6)${NC} Nginx"
    echo -e "  ${BOLD}7)${NC} SCB"
    echo ""

    local choice
    read -r -p "$(echo -e "  ${CYAN}Service [1-7]:${NC} ")" choice

    local service=""
    case "$choice" in
        1) service="" ;;
        2) service="bitcoin" ;;
        3) service="lnd" ;;
        4) service="electrs" ;;
        5) service="tor" ;;
        6) service="nginx" ;;
        7) service="scb" ;;
        *) return ;;
    esac

    print_info "Showing logs (Ctrl+C to exit)..."
    dc_logs -f --tail 50 $service
}

# --- Tools submenu ---
menu_tools() {
    echo ""
    echo -e "  ${BOLD}Tools${NC}"
    echo ""
    echo -e "  ${BOLD}1)${NC} Start          ${DIM}Start all services${NC}"
    echo -e "  ${BOLD}2)${NC} Stop           ${DIM}Stop all services${NC}"
    echo -e "  ${BOLD}3)${NC} Restart        ${DIM}Restart all services${NC}"
    echo -e "  ${BOLD}4)${NC} Rebuild        ${DIM}Rebuild and restart${NC}"
    echo -e "  ${BOLD}5)${NC} Bitcoin CLI    ${DIM}Interactive bitcoin-cli${NC}"
    echo -e "  ${BOLD}6)${NC} LND CLI        ${DIM}Interactive lncli${NC}"
    echo ""

    local choice
    read -r -p "$(echo -e "  ${CYAN}Choose [1-6]:${NC} ")" choice

    case "$choice" in
        1)  echo ""
            dc_up
            print_check "Services started"
            menu_pause
            ;;
        2)  echo ""
            dc_down
            print_check "Services stopped"
            menu_pause
            ;;
        3)  echo ""
            dc_restart
            print_check "Services restarted"
            menu_pause
            ;;
        4)  menu_update ;;
        5)  menu_bitcoin_cli ;;
        6)  menu_lncli ;;
        *)  ;;
    esac
}

# --- Update (rebuild) ---
menu_update() {
    echo ""
    print_step "Rebuild Services"
    echo ""
    print_info "This will rebuild Docker images with current versions from .env"
    print_info "and restart all services."
    echo ""

    if confirm "Proceed with rebuild?" "y"; then
        echo ""
        dc_down
        echo ""
        dc_build_services
        echo ""
        dc_start_services
        echo ""
        print_check "Rebuild complete"
    fi
    menu_pause
}

# --- Wallet submenu ---
menu_wallet() {
    echo ""
    echo -e "  ${BOLD}Wallet${NC}"
    echo ""
    echo -e "  ${BOLD}1)${NC} Create wallet     ${DIM}First-time wallet creation${NC}"
    echo -e "  ${BOLD}2)${NC} Unlock wallet     ${DIM}Manually unlock${NC}"
    echo -e "  ${BOLD}3)${NC} Wallet balance    ${DIM}On-chain balance${NC}"
    echo -e "  ${BOLD}4)${NC} Channel balance   ${DIM}Lightning balance${NC}"
    echo -e "  ${BOLD}5)${NC} New address       ${DIM}Generate on-chain address${NC}"
    echo -e "  ${BOLD}6)${NC} Zeus connect      ${DIM}Connection URI for Zeus${NC}"
    echo ""

    local choice
    read -r -p "$(echo -e "  ${CYAN}Choose [1-6]:${NC} ")" choice

    case "$choice" in
        1) wallet_create; menu_pause ;;
        2) wallet_unlock; menu_pause ;;
        3) echo ""; lncli walletbalance; menu_pause ;;
        4) echo ""; lncli channelbalance; menu_pause ;;
        5) echo ""; lncli newaddress p2tr; menu_pause ;;
        6) zeus_connect; menu_pause ;;
        *) ;;
    esac
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

    print_info "Creating wallet with auto-unlock password..."
    print_warn "IMPORTANT: Write down the seed phrase displayed below!"
    echo ""

    local password
    password="$(cat "$password_file")"
    dc_exec lnd lncli create <<EOF
$password
$password
n
EOF

    echo ""
    print_check "Wallet created!"
    print_info "LND will now sync to the blockchain. This may take a while."
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
        echo "$password" | dc_exec lnd lncli unlock --stdin
        print_check "Wallet unlocked"
    else
        print_info "Enter your wallet password:"
        dc_exec lnd lncli unlock
    fi
}

# --- Backup submenu ---
menu_backup() {
    echo ""
    echo -e "  ${BOLD}Backup (SCB)${NC}"
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

    if is_running scb; then
        print_check "SCB service is running"
    else
        print_fail "SCB service is not running"
    fi

    # Check last backup
    local scb_data
    scb_data="$(awning_path data/scb)"
    if [[ -d "${scb_data}/repo/.git" ]]; then
        local last_commit
        last_commit="$(git -C "${scb_data}/repo" log -1 --format='%ar' 2>/dev/null)" || last_commit="unknown"
        echo -e "    Last backup: ${last_commit}"
    fi

    echo ""
    echo -e "  ${BOLD}1)${NC} Trigger backup now    ${DIM}Force a manual backup${NC}"
    echo -e "  ${BOLD}2)${NC} View SCB logs         ${DIM}Recent backup activity${NC}"
    echo ""

    local choice
    read -r -p "$(echo -e "  ${CYAN}Choose [1-2]:${NC} ")" choice

    case "$choice" in
        1)
            echo ""
            if is_running scb; then
                # Restart SCB to trigger a backup cycle
                dc_restart scb
                print_check "Backup triggered (SCB restarted)"
            else
                print_fail "SCB is not running"
            fi
            menu_pause
            ;;
        2)
            dc_logs --tail 30 scb
            menu_pause
            ;;
        *)  ;;
    esac
}

# --- Interactive CLI ---
menu_bitcoin_cli() {
    echo ""
    print_info "Interactive bitcoin-cli ${DIM}(type 'exit' to return)${NC}"
    echo ""
    while true; do
        local cmd
        read -r -p "$(echo -e "  ${YELLOW}bitcoin-cli>${NC} ")" cmd
        [[ "$cmd" == "exit" || "$cmd" == "quit" ]] && break
        [[ -z "$cmd" ]] && continue
        bitcoin_cli $cmd || true
    done
}

menu_lncli() {
    echo ""
    print_info "Interactive lncli ${DIM}(type 'exit' to return)${NC}"
    echo ""
    while true; do
        local cmd
        read -r -p "$(echo -e "  ${YELLOW}lncli>${NC} ")" cmd
        [[ "$cmd" == "exit" || "$cmd" == "quit" ]] && break
        [[ -z "$cmd" ]] && continue
        lncli $cmd || true
    done
}
