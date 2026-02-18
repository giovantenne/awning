#!/bin/bash
# Awning v2: Interactive management menu
# Main menu for day-to-day node management

show_menu() {
    while true; do
        echo ""
        echo -e "${BOLD}${CYAN}=== Awning Node Manager ===${NC}"
        echo ""
        echo "  1) Status          Show service status and sync progress"
        echo "  2) Logs            View service logs"
        echo "  3) Connections     Show connection info for wallets"
        echo "  4) Start           Start all services"
        echo "  5) Stop            Stop all services"
        echo "  6) Restart         Restart all services"
        echo "  7) Update          Rebuild and restart services"
        echo "  8) Wallet          LND wallet management"
        echo "  9) Bitcoin CLI     Run bitcoin-cli commands"
        echo " 10) LND CLI         Run lncli commands"
        echo "  q) Quit"
        echo ""

        local choice
        read -r -p "$(echo -e "${CYAN}Choose [1-10, q]:${NC} ")" choice

        case "$choice" in
            1)  show_status ;;
            2)  menu_logs ;;
            3)  show_connections ;;
            4)  dc_up; log_success "Services started" ;;
            5)  dc_down; log_success "Services stopped" ;;
            6)  dc_restart; log_success "Services restarted" ;;
            7)  menu_update ;;
            8)  menu_wallet ;;
            9)  menu_bitcoin_cli ;;
            10) menu_lncli ;;
            q|Q) echo "Bye!"; exit 0 ;;
            *)  log_warn "Invalid choice" ;;
        esac
    done
}

# --- Log viewer ---
menu_logs() {
    echo ""
    echo "  1) All services"
    echo "  2) Bitcoin Core"
    echo "  3) LND"
    echo "  4) Electrs"
    echo "  5) Tor"
    echo "  6) Nginx"
    echo "  7) SCB"
    echo ""

    local choice
    read -r -p "$(echo -e "${CYAN}Service [1-7]:${NC} ")" choice

    local service=""
    case "$choice" in
        1) service="" ;;
        2) service="bitcoin" ;;
        3) service="lnd" ;;
        4) service="electrs" ;;
        5) service="tor" ;;
        6) service="nginx" ;;
        7) service="scb" ;;
        *) log_warn "Invalid choice"; return ;;
    esac

    log_info "Showing logs (Ctrl+C to exit)..."
    dc_logs -f --tail 50 $service
}

# --- Update (rebuild) ---
menu_update() {
    log_step "Update Services"
    echo ""
    log_info "This will rebuild Docker images with current versions from .env"
    log_info "and restart all services."
    echo ""

    if confirm "Proceed with update?" "y"; then
        dc_down
        dc_build
        dc_up
        log_success "Update complete"
    fi
}

# --- Wallet management ---
menu_wallet() {
    echo ""
    echo "  1) Create wallet     First-time wallet creation"
    echo "  2) Unlock wallet     Manually unlock (if auto-unlock disabled)"
    echo "  3) Wallet balance    Show on-chain balance"
    echo "  4) Channel balance   Show Lightning balance"
    echo "  5) New address       Generate new on-chain address"
    echo "  6) Zeus connect      Generate Zeus wallet connection"
    echo ""

    local choice
    read -r -p "$(echo -e "${CYAN}Choose [1-6]:${NC} ")" choice

    case "$choice" in
        1) wallet_create ;;
        2) wallet_unlock ;;
        3) lncli walletbalance ;;
        4) lncli channelbalance ;;
        5) lncli newaddress p2tr ;;
        6) zeus_connect ;;
        *) log_warn "Invalid choice" ;;
    esac
}

# Create LND wallet
wallet_create() {
    log_step "Create LND Wallet"

    if ! is_running lnd; then
        log_error "LND is not running. Start services first."
        return 1
    fi

    local lnd_data
    lnd_data="$(awning_path data/lnd)"
    local password_file="${lnd_data}/password.txt"

    if [[ ! -f "$password_file" ]]; then
        log_error "Password file not found. Run setup first."
        return 1
    fi

    log_info "Creating wallet with auto-unlock password..."
    log_warn "IMPORTANT: Write down the seed phrase displayed below!"
    echo ""

    # Create wallet using the password from file
    local password
    password="$(cat "$password_file")"
    dc_exec lnd lncli create <<EOF
$password
$password
n
EOF

    echo ""
    log_success "Wallet created!"
    log_info "LND will now sync to the blockchain. This may take a while."
}

# Unlock LND wallet
wallet_unlock() {
    if ! is_running lnd; then
        log_error "LND is not running"
        return 1
    fi

    local password_file
    password_file="$(awning_path data/lnd/password.txt)"

    if [[ -f "$password_file" ]]; then
        local password
        password="$(cat "$password_file")"
        echo "$password" | dc_exec lnd lncli unlock --stdin
        log_success "Wallet unlocked"
    else
        log_info "Enter your wallet password:"
        dc_exec lnd lncli unlock
    fi
}

# --- Interactive CLI ---
menu_bitcoin_cli() {
    log_info "Interactive bitcoin-cli (type 'exit' to return)"
    echo ""
    while true; do
        local cmd
        read -r -p "$(echo -e "${YELLOW}bitcoin-cli>${NC} ")" cmd
        [[ "$cmd" == "exit" || "$cmd" == "quit" ]] && break
        [[ -z "$cmd" ]] && continue
        bitcoin_cli $cmd || true
    done
}

menu_lncli() {
    log_info "Interactive lncli (type 'exit' to return)"
    echo ""
    while true; do
        local cmd
        read -r -p "$(echo -e "${YELLOW}lncli>${NC} ")" cmd
        [[ "$cmd" == "exit" || "$cmd" == "quit" ]] && break
        [[ -z "$cmd" ]] && continue
        lncli $cmd || true
    done
}
