#!/bin/bash
set -euo pipefail

# Render torrc with runtime-resolved service IPs for HiddenServicePort.
# Tor requires numeric target addresses here.

TORRC_SRC="/etc/tor/torrc"
TORRC_RENDERED="/tmp/torrc.rendered"

resolve_service_ip() {
    local service="$1"
    local ip=""
    local i
    for i in {1..30}; do
        ip="$(getent hosts "$service" | awk '{print $1; exit}')"
        if [[ -n "$ip" ]]; then
            echo "$ip"
            return 0
        fi
        sleep 1
    done
    echo ""
    return 1
}

lnd_ip="$(resolve_service_ip lnd || true)"
electrs_ip="$(resolve_service_ip electrs || true)"

if [[ -z "$lnd_ip" || -z "$electrs_ip" ]]; then
    echo "Failed to resolve lnd/electrs service IPs for tor hidden service mapping" >&2
    exit 1
fi

sed -e "s|lnd:8080|${lnd_ip}:8080|g" \
    -e "s|electrs:50001|${electrs_ip}:50001|g" \
    "$TORRC_SRC" > "$TORRC_RENDERED"

exec tor -f "$TORRC_RENDERED"
