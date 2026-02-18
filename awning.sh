#!/bin/bash
# Awning v2: Bitcoin + Lightning Node Manager
# https://github.com/giovantenne/awning

set -euo pipefail

# Resolve project directory (where this script lives)
AWNING_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export AWNING_DIR

# Source library modules
source "${AWNING_DIR}/lib/common.sh"
source "${AWNING_DIR}/lib/docker.sh"
source "${AWNING_DIR}/lib/setup.sh"
source "${AWNING_DIR}/lib/health.sh"
source "${AWNING_DIR}/lib/menu.sh"

# --- Main ---
main() {
    local command="${1:-}"

    # If no .env exists, run setup wizard
    if [[ -z "$command" && ! -f "$(awning_path .env)" ]]; then
        run_setup
        return
    fi

    case "$command" in
        # No argument: show interactive menu
        "")
            show_menu
            ;;

        # Setup
        setup)
            run_setup
            ;;

        # Service management
        start)
            dc_start_services
            ;;
        stop)
            dc_down
            print_check "Services stopped"
            ;;
        restart)
            dc_restart "${@:2}"
            print_check "Services restarted"
            ;;
        build)
            dc_build_services "${@:2}"
            ;;
        update)
            dc_down
            dc_build_services
            dc_start_services
            print_check "Update complete"
            ;;

        # Monitoring
        status)
            show_status
            ;;
        logs)
            dc_logs -f --tail 50 "${@:2}"
            ;;
        connections)
            show_connections
            ;;

        # Wallet
        wallet-create)
            wallet_create
            ;;
        wallet-unlock)
            wallet_unlock
            ;;
        zeus-connect)
            zeus_connect
            ;;

        # CLI access
        bitcoin-cli)
            bitcoin_cli "${@:2}"
            ;;
        lncli)
            lncli "${@:2}"
            ;;

        # Help
        help|-h|--help)
            show_help
            ;;

        *)
            print_fail "Unknown command: $command"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

show_help() {
    draw_header "AWNING v2.0" "Bitcoin + Lightning Node"
    echo ""
    echo -e "  ${BOLD}Usage:${NC} ./awning.sh [command]"
    echo ""
    echo -e "  ${BOLD}Commands:${NC}"
    echo -e "    ${CYAN}(none)${NC}          Interactive menu (or setup on first run)"
    echo -e "    ${CYAN}setup${NC}           Run the setup wizard"
    echo ""
    echo -e "  ${BOLD}Services:${NC}"
    echo -e "    ${CYAN}start${NC}           Start all services"
    echo -e "    ${CYAN}stop${NC}            Stop all services"
    echo -e "    ${CYAN}restart${NC} [svc]   Restart services"
    echo -e "    ${CYAN}build${NC} [svc]     Build Docker images"
    echo -e "    ${CYAN}update${NC}          Rebuild and restart all"
    echo ""
    echo -e "  ${BOLD}Monitoring:${NC}"
    echo -e "    ${CYAN}status${NC}          Service status and sync progress"
    echo -e "    ${CYAN}logs${NC} [svc]      Follow service logs"
    echo -e "    ${CYAN}connections${NC}     Wallet connection info"
    echo ""
    echo -e "  ${BOLD}Wallet:${NC}"
    echo -e "    ${CYAN}wallet-create${NC}   Create LND wallet (first time)"
    echo -e "    ${CYAN}wallet-unlock${NC}   Manually unlock LND wallet"
    echo -e "    ${CYAN}zeus-connect${NC}    Generate Zeus connection URI"
    echo ""
    echo -e "  ${BOLD}CLI:${NC}"
    echo -e "    ${CYAN}bitcoin-cli${NC}     Run bitcoin-cli commands"
    echo -e "    ${CYAN}lncli${NC}           Run lncli commands"
    echo ""
}

main "$@"
