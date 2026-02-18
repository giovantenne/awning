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
            dc_up
            log_success "Services started"
            ;;
        stop)
            dc_down
            log_success "Services stopped"
            ;;
        restart)
            dc_restart "${@:2}"
            log_success "Services restarted"
            ;;
        build)
            dc_build "${@:2}"
            ;;
        update)
            dc_down
            dc_build
            dc_up
            log_success "Update complete"
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
            log_error "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

show_help() {
    echo -e "${BOLD}Awning v2${NC} - Bitcoin + Lightning Node Manager"
    echo ""
    echo "Usage: ./awning.sh [command]"
    echo ""
    echo "Commands:"
    echo "  (none)          Interactive menu (or setup wizard on first run)"
    echo "  setup           Run the setup wizard"
    echo ""
    echo "  start           Start all services"
    echo "  stop            Stop all services"
    echo "  restart [svc]   Restart services (optionally specify which)"
    echo "  build [svc]     Build Docker images"
    echo "  update          Rebuild and restart all services"
    echo ""
    echo "  status          Show service status and sync progress"
    echo "  logs [svc]      Follow service logs"
    echo "  connections     Show wallet connection info"
    echo ""
    echo "  wallet-create   Create LND wallet (first time)"
    echo "  wallet-unlock   Manually unlock LND wallet"
    echo "  zeus-connect    Generate Zeus wallet connection URI"
    echo ""
    echo "  bitcoin-cli     Run bitcoin-cli commands"
    echo "  lncli           Run lncli commands"
    echo ""
    echo "  help            Show this help"
}

main "$@"
