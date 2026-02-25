#!/bin/bash
# Awning v2: Bitcoin + Lightning Node Manager
# https://github.com/giovantenne/awning

# Strict mode: -u (error on undefined vars), -o pipefail (propagate pipe errors).
# Note: -e (errexit) is intentionally omitted because the interactive menu and
# subcommands must handle errors gracefully without killing the entire script.
set -uo pipefail

# Resolve project directory (where this script lives)
AWNING_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export AWNING_DIR

# Prevent concurrent executions (flock on file descriptor 9)
exec 9>"${AWNING_DIR}/.lock"
if ! flock -n 9; then
    echo "Error: another instance of awning.sh is already running." >&2
    exit 1
fi

# Source library modules
source "${AWNING_DIR}/lib/common.sh"
source "${AWNING_DIR}/lib/docker.sh"
source "${AWNING_DIR}/lib/setup.sh"
source "${AWNING_DIR}/lib/health.sh"
source "${AWNING_DIR}/lib/menu.sh"

# Load .env safely (do not execute shell expressions from config values)
load_env_file() {
    local env_file="${AWNING_DIR}/.env"
    [[ -f "$env_file" ]] || return 0

    local key value
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*([A-Z0-9_]+)=(.*)$ ]] || continue

        key="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"
        value="${value%%[[:space:]]#*}"
        # Strip surrounding double or single quotes
        value="${value%\"}"
        value="${value#\"}"
        value="${value%\'}"
        value="${value#\'}"

        case "$key" in
            HOST_UID|HOST_GID|BITCOIN_ARCH|LND_ARCH|BITCOIN_CORE_VERSION|LND_VERSION|ELECTRS_VERSION|RTL_VERSION|NODE_ALIAS|BITCOIN_RPC_USER|BITCOIN_RPC_PASSWORD|TOR_CONTROL_PASSWORD|RTL_PASSWORD|SCB_REPO|LND_REST_BIND|LND_REST_PORT|ELECTRS_SSL_BIND|ELECTRS_SSL_PORT|RTL_BIND|RTL_PORT|BITCOIN_MEM_LIMIT|BITCOIN_CPUS|ELECTRS_MEM_LIMIT|ELECTRS_CPUS)
                export "$key=$value"
                ;;
        esac
    done < "$env_file"
}

load_env_file

# Validate .env values after loading.
# Only runs when .env exists (i.e., after setup). Catches common misconfigurations
# early rather than letting them fail deep in Docker builds or at runtime.
validate_env() {
    local env_file="${AWNING_DIR}/.env"
    [[ -f "$env_file" ]] || return 0

    local errors=0

    # Helper: check that a variable is a positive integer
    _check_int() {
        local name="$1" val="$2"
        if [[ -n "$val" ]] && ! [[ "$val" =~ ^[0-9]+$ ]]; then
            echo "  .env: ${name}='${val}' is not a valid integer" >&2
            errors=$((errors + 1))
        fi
    }

    # Helper: check port range (1-65535)
    _check_port() {
        local name="$1" val="$2"
        if [[ -n "$val" ]]; then
            if ! [[ "$val" =~ ^[0-9]+$ ]] || (( val < 1 || val > 65535 )); then
                echo "  .env: ${name}='${val}' is not a valid port (1-65535)" >&2
                errors=$((errors + 1))
            fi
        fi
    }

    # UID/GID must be numeric
    _check_int "HOST_UID" "${HOST_UID:-}"
    _check_int "HOST_GID" "${HOST_GID:-}"

    # Architecture must be known
    if [[ -n "${BITCOIN_ARCH:-}" ]] && [[ "$BITCOIN_ARCH" != "x86_64" && "$BITCOIN_ARCH" != "aarch64" ]]; then
        echo "  .env: BITCOIN_ARCH='${BITCOIN_ARCH}' is not supported (x86_64 or aarch64)" >&2
        errors=$((errors + 1))
    fi
    if [[ -n "${LND_ARCH:-}" ]] && [[ "$LND_ARCH" != "amd64" && "$LND_ARCH" != "arm64" ]]; then
        echo "  .env: LND_ARCH='${LND_ARCH}' is not supported (amd64 or arm64)" >&2
        errors=$((errors + 1))
    fi

    # Versions must not be empty if set
    local ver_var
    for ver_var in BITCOIN_CORE_VERSION LND_VERSION ELECTRS_VERSION; do
        local ver_val="${!ver_var:-}"
        if [[ -n "$ver_val" ]] && [[ ! "$ver_val" =~ ^[0-9] ]]; then
            echo "  .env: ${ver_var}='${ver_val}' does not look like a version" >&2
            errors=$((errors + 1))
        fi
    done

    # Ports must be valid
    _check_port "LND_REST_PORT" "${LND_REST_PORT:-}"
    _check_port "ELECTRS_SSL_PORT" "${ELECTRS_SSL_PORT:-}"
    _check_port "RTL_PORT" "${RTL_PORT:-}"

    # Bind addresses must be valid IPv4
    local bind_var
    for bind_var in LND_REST_BIND ELECTRS_SSL_BIND RTL_BIND; do
        local bind_val="${!bind_var:-}"
        if [[ -n "$bind_val" ]] && ! [[ "$bind_val" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "  .env: ${bind_var}='${bind_val}' is not a valid IPv4 address" >&2
            errors=$((errors + 1))
        fi
    done

    if [[ "$errors" -gt 0 ]]; then
        echo "  Found ${errors} invalid value(s) in .env. Fix them or rerun: ./awning.sh setup" >&2
        return 1
    fi
}

validate_env

# Block setup flows only when another installation directory already owns
# the same container names. In-directory setup must remain allowed.
ensure_setup_can_run() {
    # Keep conflict messaging consistent with other operational commands:
    # when running from another directory, show both installation paths.
    if ! check_container_conflicts; then
        return 1
    fi
    return 0
}

# --- Main ---
main() {
    local command="${1:-}"
    local setup_ignore_disk_space=0
    local env_file
    env_file="$(awning_path .env)"

    # If no .env exists and no command given, run auto-setup
    if [[ -z "$command" && ! -f "$env_file" ]]; then
        ensure_setup_can_run || return 1
        if run_auto_setup "$setup_ignore_disk_space"; then
            if check_container_conflicts; then
                show_menu
            else
                return 1
            fi
        fi
        return
    fi
    # Also handle: ./awning.sh --ignore-disk-space (no .env, triggers auto-setup)
    if [[ ! -f "$env_file" ]] && [[ "$command" == "--ignore-disk-space" || "$command" == "--force" ]]; then
        ensure_setup_can_run || return 1
        if run_auto_setup 1; then
            if check_container_conflicts; then
                show_menu
            else
                return 1
            fi
        fi
        return
    fi

    # Block operational commands until setup has generated .env
    if [[ ! -f "$env_file" ]]; then
        case "$command" in
            setup|help|-h|--help|version)
                ;;
            *)
                print_fail "Node is not configured yet (.env not found)."
                print_info "Run ${CYAN}./awning.sh setup${NC} first."
                return 1
                ;;
        esac
    fi

    # Prevent running operational commands from a different installation
    # directory when another awning instance already owns these container names.
    case "$command" in
        setup|help|-h|--help|version)
            ;;
        *)
            if ! check_container_conflicts; then
                return 1
            fi
            ;;
    esac

    case "$command" in
        # No argument: show interactive menu
        "")
            show_menu
            ;;

        # Setup
        setup)
            ensure_setup_can_run || return 1
            case "${2:-}" in
                "" )
                    ;;
                --ignore-disk-space|--force)
                    setup_ignore_disk_space=1
                    ;;
                * )
                    print_fail "Unknown setup option: ${2}"
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
            dc_restart "${@:2}"
            print_check "Services restarted"
            ;;
        build)
            dc_build_services "${@:2}"
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
            dc_logs -f --tail 50 "${@:2}"
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
    draw_header "AWNING v$(get_awning_version)" "Bitcoin + Lightning Node"
    echo ""
    echo -e "  ${BOLD}Usage:${NC} ./awning.sh [command]"
    echo ""
    echo -e "  ${BOLD}Commands:${NC}"
    echo -e "    ${CYAN}(none)${NC}          Interactive menu (or setup on first run)"
    echo -e "    ${CYAN}setup${NC}           Run the setup wizard"
    echo -e "    ${CYAN}setup --ignore-disk-space${NC}  Run setup ignoring low disk space"
    echo ""
    echo -e "  ${BOLD}Services:${NC}"
    echo -e "    ${CYAN}start${NC}           Start all services"
    echo -e "    ${CYAN}stop${NC}            Stop all services"
    echo -e "    ${CYAN}restart${NC} [svc]   Restart services"
    echo -e "    ${CYAN}build${NC} [svc]     Build Docker images"
    echo -e "    ${CYAN}rebuild${NC}         Rebuild and restart all"
    echo ""
    echo -e "  ${BOLD}Monitoring:${NC}"
    echo -e "    ${CYAN}status${NC}          Service status and sync progress"
    echo -e "    ${CYAN}version${NC}         Show Awning version"
    echo -e "    ${CYAN}logs${NC} [svc]      Follow service logs"
    echo -e "    ${CYAN}connections${NC}     Wallet connection info"
    echo ""
    echo -e "  ${BOLD}Wallet:${NC}"
    echo -e "    ${CYAN}wallet-balance${NC}  Show LND on-chain balance"
    echo -e "    ${CYAN}channel-balance${NC} Show LND Lightning balance"
    echo -e "    ${CYAN}new-address${NC}     Generate a new on-chain address"
    echo -e "    ${CYAN}zeus-connect${NC}    Generate Zeus connection URI"
    echo ""
    echo -e "  ${BOLD}CLI:${NC}"
    echo -e "    ${CYAN}bitcoin-cli${NC}     Run bitcoin-cli commands"
    echo -e "    ${CYAN}lncli${NC}           Run lncli commands"
    echo ""
}

main "$@"
