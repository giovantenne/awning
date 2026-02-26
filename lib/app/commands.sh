#!/bin/bash
# Application command dispatcher.

awning_dispatch_command() {
    local command="$1"
    local setup_ignore_disk_space="${2:-0}"

    case "$command" in
        # No argument: show interactive menu
        "")
            show_menu
            ;;

        # Setup
        setup)
            ensure_setup_can_run || return 1
            case "${3:-}" in
                "" )
                    ;;
                --ignore-disk-space|--force)
                    setup_ignore_disk_space=1
                    ;;
                * )
                    print_fail "Unknown setup option: ${3}"
                    print_info "Use: ${CYAN}./awning.sh setup --ignore-disk-space${NC}"
                    return 1
                    ;;
            esac
            if run_setup "$setup_ignore_disk_space"; then
                if check_container_conflicts; then
                    show_menu
                else
                    return 1
                fi
            fi
            ;;

        # Service management
        start)
            dc_start_services
            ;;
        stop)
            dc_stop_services
            print_check "Services stopped"
            ;;
        restart)
            dc_restart "${@:3}"
            print_check "Services restarted"
            ;;
        build)
            dc_build_services "${@:3}"
            ;;
        rebuild)
            dc_down_with_spinner
            dc_build_services
            dc_start_services
            print_check "Rebuild complete"
            ;;

        # Monitoring
        status)
            show_status
            ;;
        version)
            echo "$(get_awning_version)"
            ;;
        logs)
            dc_logs -f --tail 50 "${@:3}"
            ;;
        connections)
            show_connections
            ;;

        # Wallet
        wallet-balance)
            require_wallet && show_wallet_balance_ui
            ;;
        channel-balance)
            require_wallet && show_channel_balance_ui
            ;;
        new-address)
            require_wallet && show_new_address_ui
            ;;
        zeus-connect)
            zeus_connect
            ;;

        # CLI access
        bitcoin-cli)
            bitcoin_cli "${@:3}"
            ;;
        lncli)
            lncli "${@:3}"
            ;;

        # Help
        help|-h|--help)
            show_help
            ;;

        *)
            print_fail "Unknown command: $command"
            echo ""
            show_help
            return 1
            ;;
    esac
}
