#!/bin/bash
# Awning v2: RTL entrypoint
# Starts stunnel (HTTPS termination on port 3001) then runs RTL

set -euo pipefail

# Start stunnel in background for SSL termination
# Config has foreground=yes so it doesn't daemonize; we background it here
stunnel /etc/stunnel/stunnel.conf &

# Run RTL (node rtl) with all passed arguments
exec node rtl "$@"
