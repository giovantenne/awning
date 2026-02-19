#!/bin/bash
set -euo pipefail

# Awning v2: LND entrypoint
# Starts lnd with the container's IP for Tor target and the configured node alias

# Get a single container IP for Tor hidden service routing.
# `hostname -i` may return multiple addresses when attached to multiple networks.
CONTAINER_IP="$(hostname -i | awk '{print $1}')"

echo "Starting LND..."
echo "  Node alias:  ${NODE_ALIAS:-awning}"
echo "  Tor target:  ${CONTAINER_IP}"

exec lnd \
    --tor.targetipaddress="${CONTAINER_IP}" \
    --alias="${NODE_ALIAS:-awning}"
