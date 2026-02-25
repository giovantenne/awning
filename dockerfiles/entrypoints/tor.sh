#!/bin/bash
set -euo pipefail

# Render torrc with runtime-resolved service IPs for HiddenServicePort.
# Tor requires numeric target addresses for HiddenServicePort directives.
#
# Strategy: Tor starts immediately (as SOCKS/control proxy). If LND/Electrs
# DNS is not yet available, hidden services are omitted from the initial
# torrc. A background loop keeps retrying DNS resolution and, once all
# services are found, regenerates torrc with hidden services and sends
# SIGHUP to Tor to reload the config without restarting.

TORRC_SRC="/etc/tor/torrc"
TORRC_RENDERED="/tmp/torrc.rendered"

resolve_service_ip() {
    local service="$1"
    local max_attempts="${2:-10}"
    local ip=""
    local i

    for ((i = 1; i <= max_attempts; i++)); do
        ip="$(getent hosts "$service" 2>/dev/null | awk '{print $1; exit}')" || true
        if [[ -n "$ip" ]]; then
            echo "$ip"
            return 0
        fi
        sleep 1
    done
    return 1
}

render_torrc_with_services() {
    local lnd="$1" electrs="$2" rtl="${3:-}"

    sed -e "s|lnd:8080|${lnd}:8080|g" \
        -e "s|electrs:50001|${electrs}:50001|g" \
        "$TORRC_SRC" > "$TORRC_RENDERED"

    if [[ -n "$rtl" ]]; then
        sed -i "s|rtl:3001|${rtl}:3001|g" "$TORRC_RENDERED"
    else
        grep -v -E '(hidden_service_rtl|rtl:)' "$TORRC_RENDERED" > "${TORRC_RENDERED}.tmp"
        mv "${TORRC_RENDERED}.tmp" "$TORRC_RENDERED"
    fi
}

render_torrc_without_services() {
    grep -v -E '(HiddenService|lnd:|electrs:|rtl:)' "$TORRC_SRC" > "$TORRC_RENDERED"
}

# --- Initial DNS check (quick, non-blocking) ---

echo "Checking service DNS..."

lnd_ip="$(resolve_service_ip lnd 5)" || lnd_ip=""
electrs_ip="$(resolve_service_ip electrs 5)" || electrs_ip=""
rtl_ip="$(resolve_service_ip rtl 3)" || rtl_ip=""

if [[ -n "$lnd_ip" && -n "$electrs_ip" ]]; then
    echo "Resolved: lnd=${lnd_ip}, electrs=${electrs_ip}${rtl_ip:+, rtl=${rtl_ip}}"
    render_torrc_with_services "$lnd_ip" "$electrs_ip" "$rtl_ip"
    exec tor -f "$TORRC_RENDERED"
fi

# --- Services not ready: start Tor without hidden services ---

echo "Services not ready yet (lnd=${lnd_ip:-?}, electrs=${electrs_ip:-?})"
echo "Starting Tor without hidden services. Will enable them automatically."
render_torrc_without_services

tor -f "$TORRC_RENDERED" &
tor_pid=$!

# Forward SIGTERM/SIGINT to Tor for graceful shutdown
trap 'kill -TERM "$tor_pid" 2>/dev/null; wait "$tor_pid"' TERM INT

# --- Background loop: wait for services, then reload Tor ---

(
    max_wait=300
    waited=0

    while (( waited < max_wait )); do
        sleep 10
        waited=$((waited + 10))

        lnd_ip="$(resolve_service_ip lnd 3)" || lnd_ip=""
        electrs_ip="$(resolve_service_ip electrs 3)" || electrs_ip=""
        rtl_ip="$(resolve_service_ip rtl 2)" || rtl_ip=""

        if [[ -n "$lnd_ip" && -n "$electrs_ip" ]]; then
            echo "Resolved: lnd=${lnd_ip}, electrs=${electrs_ip}${rtl_ip:+, rtl=${rtl_ip}}"
            render_torrc_with_services "$lnd_ip" "$electrs_ip" "$rtl_ip"
            echo "Reloading Tor with hidden services (SIGHUP)..."
            kill -HUP "$tor_pid" 2>/dev/null || true
            exit 0
        fi

        echo "Waiting for services... (${waited}s/${max_wait}s)"
    done

    echo "WARNING: Gave up waiting for services after ${max_wait}s. Hidden services not active." >&2
) &

# Wait for Tor process (keeps container alive)
wait "$tor_pid"
