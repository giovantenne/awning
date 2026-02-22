#!/bin/bash
# Awning v2: Electrs entrypoint
# Starts stunnel (SSL termination on port 50002) then runs electrs

set -euo pipefail

# Start stunnel in background for SSL termination
# Config has foreground=yes so it doesn't daemonize; we background it here
stunnel /etc/stunnel/stunnel.conf &

# Run electrs with all passed arguments
exec electrs "$@"
