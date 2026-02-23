#!/bin/bash
# Awning v2: Docker Compose wrappers
# Auto-detects sudo requirement, compose variant, and provides consistent interface

# ============================================================
# Service definitions
# ============================================================

# Core services in dependency order (always started)
CORE_SERVICES=(tor bitcoin lnd electrs)

# All services including optional ones
# SCB is only included when SCB_REPO is configured
# RTL is only included when RTL_PASSWORD is configured
dc_active_services() {
    local services=("${CORE_SERVICES[@]}")
    if [[ -n "${SCB_REPO:-}" ]]; then
        services+=(scb)
    fi
    if [[ -n "${RTL_PASSWORD:-}" ]]; then
        services+=(rtl)
    fi
    printf '%s ' "${services[@]}"
}

# ============================================================
# Docker detection and auto-configuration
# ============================================================

# Detect if sudo is needed for docker (cached)
_DOCKER_NEEDS_SUDO=""
_COMPOSE_CMD=""
_needs_sudo() {
    if [[ -z "$_DOCKER_NEEDS_SUDO" ]]; then
        if docker info &>/dev/null; then
            _DOCKER_NEEDS_SUDO="no"
        else
            _DOCKER_NEEDS_SUDO="yes"
        fi
    fi
    [[ "$_DOCKER_NEEDS_SUDO" == "yes" ]]
}

_detect_compose_cmd() {
    [[ -n "$_COMPOSE_CMD" ]] && return 0

    if docker compose version &>/dev/null 2>&1; then
        _COMPOSE_CMD="docker-compose-plugin"
        return 0
    fi
    if command -v docker-compose &>/dev/null 2>&1; then
        _COMPOSE_CMD="docker-compose-standalone"
        return 0
    fi

    if _needs_sudo; then
        if sudo docker compose version &>/dev/null 2>&1; then
            _COMPOSE_CMD="docker-compose-plugin"
            return 0
        fi
        if command -v docker-compose &>/dev/null 2>&1 && sudo docker-compose version &>/dev/null 2>&1; then
            _COMPOSE_CMD="docker-compose-standalone"
            return 0
        fi
    fi

    return 1
}

# Run docker compose with correct prefix
_dc() {
    local compose_file
    compose_file="$(awning_path docker-compose.yml)"
    # Refresh exported vars from .env on each compose call, so runtime changes
    # made by setup/manual edits are picked up without restarting awning.sh.
    if declare -F load_env_file >/dev/null 2>&1; then
        load_env_file
    fi
    if ! _detect_compose_cmd; then
        print_fail "Neither 'docker compose' nor 'docker-compose' is available"
        return 127
    fi

    if [[ "$_COMPOSE_CMD" == "docker-compose-plugin" ]]; then
        if _needs_sudo; then
            sudo docker compose -f "$compose_file" "$@"
        else
            docker compose -f "$compose_file" "$@"
        fi
    else
        if _needs_sudo; then
            sudo docker-compose -f "$compose_file" "$@"
        else
            docker-compose -f "$compose_file" "$@"
        fi
    fi
}

# Run raw docker with correct prefix
_docker() {
    if _needs_sudo; then
        sudo docker "$@"
    else
        docker "$@"
    fi
}

# ============================================================
# jq wrapper: native if available, Docker fallback otherwise
# ============================================================
if ! command -v jq &>/dev/null; then
    jq() {
        _docker run --rm -i ghcr.io/jqlang/jq "$@"
    }
fi

# ============================================================
# Compose wrappers
# ============================================================

dc_up() {
    _dc up -d "$@"

    # If Tor is force-recreated without LND, LND can keep stale SOCKS connections.
    # Restart LND to force re-resolve of `tor:9050`.
    if _should_refresh_lnd_after_tor_change "up" "$@"; then
        print_info "Tor was recreated, restarting lnd to refresh Tor SOCKS endpoint..."
        _dc restart lnd >/dev/null 2>&1 || print_warn "Could not restart lnd automatically"
    fi
}

dc_down_with_spinner() {
    _dc down >/dev/null 2>&1 &
    local down_pid=$!
    if ! spinner "$down_pid" "Stopping and removing existing containers..."; then
        print_fail "Failed to stop/remove existing containers"
        return 1
    fi
}

dc_restart() {
    _dc up -d --force-recreate --no-build "$@"

    if _should_refresh_lnd_after_tor_change "restart" "$@"; then
        print_info "Tor was restarted, restarting lnd to refresh Tor SOCKS endpoint..."
        _dc restart lnd >/dev/null 2>&1 || print_warn "Could not restart lnd automatically"
    fi
}

dc_logs() {
    _dc logs "$@"
}

dc_exec() {
    _dc exec "$@"
}

# Return success when LND should be refreshed after Tor changes.
_should_refresh_lnd_after_tor_change() {
    local op="$1"
    shift

    local has_force_recreate=0 has_any_service=0 has_tor=0 has_lnd=0 arg
    for arg in "$@"; do
        case "$arg" in
            --force-recreate)
                has_force_recreate=1
                ;;
            --*)
                ;;
            -*)
                ;;
            tor)
                has_any_service=1
                has_tor=1
                ;;
            lnd)
                has_any_service=1
                has_lnd=1
                ;;
            *)
                has_any_service=1
                ;;
        esac
    done

    # `restart tor` while LND keeps running causes stale proxy target in LND.
    if [[ "$op" == "restart" ]]; then
        [[ "$has_tor" -eq 1 ]] || return 1
        [[ "$has_lnd" -eq 0 ]] || return 1
        dc_is_running lnd || return 1
        return 0
    fi

    # `up --force-recreate` with Tor involved can change Tor container IP.
    if [[ "$op" == "up" ]]; then
        [[ "$has_force_recreate" -eq 1 ]] || return 1
        if [[ "$has_any_service" -eq 0 ]]; then
            # No explicit services means all services, LND is recreated too.
            return 1
        fi
        [[ "$has_tor" -eq 1 ]] || return 1
        [[ "$has_lnd" -eq 0 ]] || return 1
        dc_is_running lnd || return 1
        return 0
    fi

    return 1
}

# Build Docker images one service at a time with spinner progress.
# Build output goes to a log file; on failure the tail is shown.
# Args: [service...] - services to build (defaults to all active services)
# Returns: 1 if any build fails
dc_build_services() {
    local services=("$@")
    if [[ ${#services[@]} -eq 0 ]]; then
        read -ra services <<< "$(dc_active_services)"
    fi
    local total=${#services[@]}
    local i=0
    local build_log
    build_log="$(awning_path .build.log)"

    local total_width=${#total}
    # Find longest service name for alignment
    local max_svc_len=0
    for service in "${services[@]}"; do
        [[ ${#service} -gt $max_svc_len ]] && max_svc_len=${#service}
    done

    for service in "${services[@]}"; do
        ((i++))
        local padded_i padded_svc
        padded_i="$(printf "%${total_width}d" "$i")"
        padded_svc="$(printf "%-${max_svc_len}s" "$service")"
        _dc build "$service" > "$build_log" 2>&1 &
        local build_pid=$!
        if ! spinner "$build_pid" "Building ${padded_svc}  (${padded_i}/${total})" "$build_log"; then
            echo ""
            echo -e "  ${DIM}--- Last 30 lines of build output ---${NC}"
            tail -30 "$build_log" | while IFS= read -r line; do
                echo "  $line"
            done
            echo -e "  ${DIM}--- Full log: .build.log ---${NC}"
            echo ""
            rm -f "$build_log"
            return 1
        fi
    done
    rm -f "$build_log"
}

# Start services one at a time with spinner and post-start status report.
# Skips services that are already running.
# Args: [service...] - services to start (defaults to all active services)
dc_start_services() {
    local services=("$@")
    if [[ ${#services[@]} -eq 0 ]]; then
        read -ra services <<< "$(dc_active_services)"
    fi

    # Avoid redundant startup when everything is already running.
    local pending=()
    local service
    for service in "${services[@]}"; do
        if ! dc_is_running "$service" 2>/dev/null; then
            pending+=("$service")
        fi
    done
    if [[ ${#pending[@]} -eq 0 ]]; then
        print_info "All services are already running"
        return 0
    fi
    services=("${pending[@]}")

    print_step "Starting services..."
    echo ""

    local total=${#services[@]}
    local total_width=${#total}
    local max_svc_len=0
    for service in "${services[@]}"; do
        [[ ${#service} -gt $max_svc_len ]] && max_svc_len=${#service}
    done
    local i=0
    for service in "${services[@]}"; do
        ((i++))
        local padded_i padded_svc
        padded_i="$(printf "%${total_width}d" "$i")"
        padded_svc="$(printf "%-${max_svc_len}s" "$service")"
        _dc up -d "$service" >/dev/null 2>&1 &
        local up_pid=$!
        if ! spinner "$up_pid" "Starting ${padded_svc}  (${padded_i}/${total})"; then
            print_fail "${service} failed to start"
        fi
    done

    # Give containers a moment to start
    sleep 2

    # Report status of each service
    for service in "${services[@]}"; do
        local status health
        status="$(dc_get_status "$service")"
        health="$(dc_get_health "$service")"

        if [[ -z "$status" ]]; then
            print_fail "${service} (stopped)"
        elif [[ "$status" == "running" || "$status" == "restarting" ]]; then
            local annotation=""
            case "$service" in
                bitcoin)
                    local progress
                    progress="$(bitcoin_cli getblockchaininfo 2>/dev/null | jq -r '.verificationprogress // empty' 2>/dev/null)" || true
                    if [[ -n "$progress" ]]; then
                        local pct
                        pct="$(echo "$progress" | awk '{printf "%.2f", $1 * 100}')"
                        if awk "BEGIN {exit ($pct >= 99.9)}" 2>/dev/null; then
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

            if [[ "$status" == "running" && "$health" == "unhealthy" ]]; then
                print_fail "${service} (unhealthy)"
            elif [[ "$status" == "restarting" ]]; then
                print_warn "${service} restarting ${annotation}"
            else
                print_check "${service} ${annotation}"
            fi
        else
            print_fail "${service} (${status})"
        fi
    done
}

# Stop services in reverse dependency order with spinner, then tear down.
# Args: [service...] - services to stop (defaults to all active services)
dc_stop_services() {
    local services=("$@")
    if [[ ${#services[@]} -eq 0 ]]; then
        read -ra services <<< "$(dc_active_services)"
    fi

    print_step "Stopping services..."
    echo ""

    local total=${#services[@]}
    local total_width=${#total}
    local max_svc_len=0
    for service in "${services[@]}"; do
        [[ ${#service} -gt $max_svc_len ]] && max_svc_len=${#service}
    done
    local i=0
    local idx
    for ((idx = total - 1; idx >= 0; idx--)); do
        local service="${services[idx]}"
        ((i++))
        local padded_i padded_svc
        padded_i="$(printf "%${total_width}d" "$i")"
        padded_svc="$(printf "%-${max_svc_len}s" "$service")"
        _dc stop "$service" >/dev/null 2>&1 &
        local stop_pid=$!
        if ! spinner "$stop_pid" "Stopping ${padded_svc}  (${padded_i}/${total})"; then
            print_fail "${service} failed to stop"
        fi
    done

    _dc down >/dev/null 2>&1 &
    local down_pid=$!
    if ! spinner "$down_pid" "Removing containers and network..."; then
        print_fail "Teardown failed"
        return 1
    fi
}

# ============================================================
# Convenience shortcuts
# ============================================================

# Non-interactive exec (for scripted/status queries)
bitcoin_cli() {
    dc_exec -T bitcoin bitcoin-cli -datadir=/data/.bitcoin "$@"
}

lncli() {
    dc_exec -T lnd lncli --lnddir=/data/.lnd --network "${BITCOIN_NETWORK}" "$@"
}

# Interactive exec (for wallet creation, manual CLI)
lncli_interactive() {
    dc_exec lnd lncli --lnddir=/data/.lnd --network "${BITCOIN_NETWORK}" "$@"
}

# Get the state status of a container (running, exited, restarting, etc.)
dc_get_status() {
    local service="$1"
    _docker inspect --format '{{.State.Status}}' "$service" 2>/dev/null || echo ""
}

# Get the healthcheck status of a container (healthy, unhealthy, starting, or empty)
dc_get_health() {
    local service="$1"
    _docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$service" 2>/dev/null || echo ""
}

# Check if a service is running
dc_is_running() {
    local service="$1"
    local status
    status="$(dc_get_status "$service")"
    [[ "$status" == "running" ]]
}

# Check if services are built
dc_is_built() {
    _docker image ls --format '{{.Repository}}' 2>/dev/null | grep -q "awning"
}
