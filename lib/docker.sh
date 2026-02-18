#!/bin/bash
# Awning v2: Docker compose wrappers
# Auto-detects sudo requirement and provides consistent interface

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
    log_info "Building${services:+ ${services[*]}}..."
    eval "$(_compose_cmd) build ${services[*]:-}"
}

dc_up() {
    local services=("$@")
    log_info "Starting${services:+ ${services[*]}}..."
    eval "$(_compose_cmd) up -d ${services[*]:-}"
}

dc_down() {
    log_info "Stopping all services..."
    eval "$(_compose_cmd) down"
}

dc_stop() {
    local services=("$@")
    log_info "Stopping${services:+ ${services[*]}}..."
    eval "$(_compose_cmd) stop ${services[*]:-}"
}

dc_restart() {
    local services=("$@")
    log_info "Restarting${services:+ ${services[*]}}..."
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
    echo "$status" | grep -q "^${service}$"
}

# Check if services are built
is_built() {
    local docker
    docker="$(_docker_cmd)"
    eval "${docker} image ls --format '{{.Repository}}' 2>/dev/null" | grep -q "awning"
}
