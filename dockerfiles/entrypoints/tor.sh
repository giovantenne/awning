#!/bin/bash
set -euo pipefail

# Render torrc with runtime-resolved service IPs for HiddenServicePort.
# Tor requires numeric target addresses for HiddenServicePort directives.
#
# Challenge: Tor starts before LND/Electrs (they depend on Tor for SOCKS),
# so we wait for Docker DNS to resolve their container IPs. Docker creates
# the containers (and assigns IPs) before starting their processes, so
# the DNS entries become available shortly after `docker compose up`.

TORRC_SRC="/etc/tor/torrc"
TORRC_RENDERED="/tmp/torrc.rendered"

resolve_service_ip() {
    local service="$1"
    local max_attempts="${2:-60}"
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

echo "Waiting for service DNS resolution..."

lnd_ip="$(resolve_service_ip lnd 15)" || lnd_ip=""
electrs_ip="$(resolve_service_ip electrs 15)" || electrs_ip=""
rtl_ip="$(resolve_service_ip rtl 10)" || rtl_ip=""

if [[ -z "$lnd_ip" || -z "$electrs_ip" ]]; then
    echo "WARNING: Could not resolve all service IPs (lnd=${lnd_ip:-?}, electrs=${electrs_ip:-?})" >&2
    echo "Starting Tor without hidden services. Restart Tor after all services are up." >&2
    # Strip hidden service blocks from torrc so Tor can start without them
    grep -v -E '(HiddenService|lnd:|electrs:|rtl:)' "$TORRC_SRC" > "$TORRC_RENDERED"
else
    echo "Resolved: lnd=${lnd_ip}, electrs=${electrs_ip}${rtl_ip:+, rtl=${rtl_ip}}"
    sed -e "s|lnd:8080|${lnd_ip}:8080|g" \
        -e "s|electrs:50001|${electrs_ip}:50001|g" \
        "$TORRC_SRC" > "$TORRC_RENDERED"

    # RTL is optional; strip its hidden service block if not resolvable
    if [[ -n "$rtl_ip" ]]; then
        sed -i "s|rtl:3000|${rtl_ip}:3000|g" "$TORRC_RENDERED"
    else
        echo "INFO: RTL not running, stripping RTL hidden service from torrc" >&2
        grep -v -E '(hidden_service_rtl|rtl:)' "$TORRC_RENDERED" > "${TORRC_RENDERED}.tmp"
        mv "${TORRC_RENDERED}.tmp" "$TORRC_RENDERED"
    fi
fi

exec tor -f "$TORRC_RENDERED"
