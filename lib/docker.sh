#!/bin/bash
# Awning v2: Docker compose wrappers
# Auto-detects sudo requirement and provides consistent interface

# All 6 services in dependency order
ALL_SERVICES=(tor bitcoin lnd electrs scb nginx)

# Detect if sudo is needed for docker
_docker_cmd() {
    if docker info &>/dev/null 2>&1; then
        echo "docker"
    else
        echo "sudo docker"
    fi
}

# Get the docker compose command
_compose_cmd() {
    local docker
    docker="$(_docker_cmd)"
    echo "${docker} compose -f $(awning_path docker-compose.yml)"
}

# --- Compose wrappers ---

dc_build() {
    local services=("$@")
    eval "$(_compose_cmd) build ${services[*]:-}"
}

dc_up() {
    local services=("$@")
    eval "$(_compose_cmd) up -d ${services[*]:-}"
}

dc_down() {
    eval "$(_compose_cmd) down"
}

dc_stop() {
    local services=("$@")
    eval "$(_compose_cmd) stop ${services[*]:-}"
}

dc_restart() {
    local services=("$@")
    eval "$(_compose_cmd) restart ${services[*]:-}"
}

dc_logs() {
    local args=("$@")
    eval "$(_compose_cmd) logs ${args[*]:-}"
}

dc_exec() {
    local service="$1"
    shift
    eval "$(_compose_cmd) exec ${service} $*"
}

dc_ps() {
    eval "$(_compose_cmd) ps --format 'table {{.Name}}\t{{.Status}}\t{{.Ports}}'"
}

# --- Service-by-service build with progress ---
# Shows "Building tor... (1/6)" with live status
dc_build_services() {
    local services=("${@:-${ALL_SERVICES[@]}}")
    local total=${#services[@]}
    local i=0

    for service in "${services[@]}"; do
        ((i++))
        printf "\r\033[K"
        printf '  %b Building %s... (%d/%d)' "${ICON_ARROW}" "$service" "$i" "$total"

        if eval "$(_compose_cmd) build ${service}" &>/dev/null 2>&1; then
            printf "\r\033[K"
            print_check "${service} built"
        else
            printf "\r\033[K"
            print_fail "${service} build failed"
            log_error "Run './awning.sh logs' or rebuild with './awning.sh build ${service}' for details"
            return 1
        fi
    done
}

# --- Service-by-service startup with status ---
# Shows each service starting and reports when healthy
dc_start_services() {
    local services=("${@:-${ALL_SERVICES[@]}}")

    print_step "Starting services..."
    echo ""

    dc_up "${services[@]}" 2>/dev/null

    # Give containers a moment to start
    sleep 2

    # Report status of each service
    for service in "${services[@]}"; do
        local status
        status="$(eval "$(_compose_cmd) ps --format '{{.Status}}' ${service} 2>/dev/null")" || status=""

        if [[ -z "$status" ]]; then
            print_fail "${service} (not found)"
        elif echo "$status" | grep -qi "up\|running\|healthy\|starting"; then
            local annotation=""
            case "$service" in
                bitcoin)
                    # Check if syncing
                    local progress
                    progress="$(bitcoin_cli getblockchaininfo 2>/dev/null | jq -r '.verificationprogress // empty' 2>/dev/null)" || true
                    if [[ -n "$progress" ]]; then
                        local pct
                        pct="$(echo "$progress" | awk '{printf "%.2f", $1 * 100}')"
                        if (( $(echo "$pct < 99.9" | bc -l 2>/dev/null || echo 1) )); then
                            annotation="${DIM}(syncing: ${pct}%)${NC}"
                        fi
                    fi
                    ;;
                lnd)
                    local lnd_info
                    lnd_info="$(lncli getinfo 2>/dev/null)" || true
                    if [[ -z "$lnd_info" ]]; then
                        annotation="${DIM}(waiting for bitcoin sync)${NC}"
                    fi
                    ;;
                electrs)
                    annotation="${DIM}(waiting for bitcoin sync)${NC}"
                    ;;
            esac
            print_check "${service} ${annotation}"
        else
            print_fail "${service} (${status})"
        fi
    done
}

# --- Convenience shortcuts ---

bitcoin_cli() {
    dc_exec bitcoin bitcoin-cli -datadir=/data/.bitcoin "$@"
}

lncli() {
    dc_exec lnd lncli --network mainnet "$@"
}

# Check if a service is running
is_running() {
    local service="$1"
    local status
    status="$(eval "$(_compose_cmd) ps --status running --format '{{.Name}}' 2>/dev/null")" || return 1
    echo "$status" | grep -q "${service}"
}

# Check if services are built
is_built() {
    local docker
    docker="$(_docker_cmd)"
    eval "${docker} image ls --format '{{.Repository}}' 2>/dev/null" | grep -q "awning"
}
