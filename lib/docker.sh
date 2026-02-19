#!/bin/bash
# Awning v2: Docker compose wrappers
# Auto-detects sudo requirement and provides consistent interface

# Core services in dependency order (always started)
CORE_SERVICES=(tor bitcoin lnd electrs nginx)

# All services including optional ones
# SCB is only included when SCB_REPO is configured
active_services() {
    local services=("${CORE_SERVICES[@]}")
    if [[ -n "${SCB_REPO:-}" ]]; then
        services+=(scb)
    fi
    echo "${services[@]}"
}

# Detect if sudo is needed for docker (cached)
_DOCKER_NEEDS_SUDO=""
_COMPOSE_CMD=""
_needs_sudo() {
    if [[ -z "$_DOCKER_NEEDS_SUDO" ]]; then
        if docker info &>/dev/null; then
            _DOCKER_NEEDS_SUDO="no"

            # If both user and root daemons are reachable, prefer the one that
            # actually contains awning containers.
            if sudo docker info &>/dev/null; then
                local service_names_regex user_has_awning root_has_awning
                service_names_regex='^(tor|bitcoin|lnd|electrs|nginx|scb)$'
                user_has_awning="$(docker ps --format '{{.Names}}' 2>/dev/null | grep -E "$service_names_regex" || true)"
                root_has_awning="$(sudo docker ps --format '{{.Names}}' 2>/dev/null | grep -E "$service_names_regex" || true)"
                if [[ -z "$user_has_awning" && -n "$root_has_awning" ]]; then
                    _DOCKER_NEEDS_SUDO="yes"
                fi
            fi
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
    if sudo docker compose version &>/dev/null 2>&1; then
        _COMPOSE_CMD="docker-compose-plugin"
        return 0
    fi
    if command -v docker-compose &>/dev/null 2>&1 && sudo docker-compose version &>/dev/null 2>&1; then
        _COMPOSE_CMD="docker-compose-standalone"
        return 0
    fi

    return 1
}

# Run docker compose with correct prefix
_dc() {
    local compose_file
    compose_file="$(awning_path docker-compose.yml)"
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

# --- Compose wrappers ---

dc_build() {
    _dc build "$@"
}

dc_up() {
    _dc up -d "$@"
}

dc_down() {
    _dc down
}

dc_down_with_spinner() {
    _dc down >/dev/null 2>&1 &
    local down_pid=$!
    if ! spinner "$down_pid" "Stopping and removing existing containers..."; then
        print_fail "Failed to stop/remove existing containers"
        return 1
    fi
}

dc_stop() {
    _dc stop "$@"
}

dc_restart() {
    _dc restart "$@"
}

dc_logs() {
    _dc logs "$@"
}

dc_exec() {
    _dc exec "$@"
}

dc_exec_t() {
    _dc exec -T "$@"
}

dc_ps() {
    _dc ps --format 'table {{.Name}}\t{{.Status}}\t{{.Ports}}'
}

# --- Service-by-service build with progress ---
# Build output goes to a log file; on failure, show the tail
dc_build_services() {
    local services=("$@")
    if [[ ${#services[@]} -eq 0 ]]; then
        read -ra services <<< "$(active_services)"
    fi
    local total=${#services[@]}
    local i=0
    local build_log
    build_log="$(awning_path .build.log)"

    for service in "${services[@]}"; do
        ((i++))
        _dc build "$service" > "$build_log" 2>&1 &
        local build_pid=$!
        if spinner "$build_pid" "Building ${service}... (${i}/${total})"; then
            print_check "${service} built"
        else
            print_fail "${service} build failed"
            echo ""
            echo -e "  ${DIM}--- Last 30 lines of build output ---${NC}"
            tail -30 "$build_log" | while IFS= read -r line; do
                echo "  $line"
            done
            echo -e "  ${DIM}--- Full log: .build.log ---${NC}"
            echo ""
            return 1
        fi
    done
    rm -f "$build_log"
}

# --- Service-by-service startup with status ---
dc_start_services() {
    local services=("$@")
    if [[ ${#services[@]} -eq 0 ]]; then
        read -ra services <<< "$(active_services)"
    fi

    # Avoid redundant startup when everything is already running.
    local pending=()
    local service
    for service in "${services[@]}"; do
        if ! is_running "$service" 2>/dev/null; then
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
    local i=0
    for service in "${services[@]}"; do
        ((i++))
        _dc up -d "$service" >/dev/null 2>&1 &
        local up_pid=$!
        if ! spinner "$up_pid" "Starting ${service}... (${i}/${total})"; then
            print_fail "${service} failed to start"
        fi
    done

    # Give containers a moment to start
    sleep 2

    # Report status of each service
    for service in "${services[@]}"; do
        local status health
        status="$(_docker inspect --format '{{.State.Status}}' "$service" 2>/dev/null)" || status=""
        health="$(_docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$service" 2>/dev/null)" || health=""

        if [[ -z "$status" ]]; then
            print_fail "${service} (not found)"
        elif [[ "$status" == "running" || "$status" == "restarting" ]]; then
            local annotation=""
            case "$service" in
                bitcoin)
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

# --- Service-by-service stop with progress ---
dc_stop_services() {
    local services=("$@")
    if [[ ${#services[@]} -eq 0 ]]; then
        read -ra services <<< "$(active_services)"
    fi

    print_step "Stopping services..."
    echo ""

    local total=${#services[@]}
    local i=0
    local idx
    for ((idx = total - 1; idx >= 0; idx--)); do
        local service="${services[idx]}"
        ((i++))
        _dc stop "$service" >/dev/null 2>&1 &
        local stop_pid=$!
        if ! spinner "$stop_pid" "Stopping ${service}... (${i}/${total})"; then
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
    status="$(_docker inspect --format '{{.State.Status}}' "$service" 2>/dev/null)" || return 1
    [[ "$status" == "running" ]]
}

# Check if services are built
is_built() {
    _docker image ls --format '{{.Repository}}' 2>/dev/null | grep -q "awning"
}
