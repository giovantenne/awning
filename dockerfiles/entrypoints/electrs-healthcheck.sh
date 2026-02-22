#!/bin/sh
set -eu

# Normal ready state: both electrs and stunnel listeners are up.
if /bin/nc -4 -z 127.0.0.1 50001 && /bin/nc -4 -z 127.0.0.1 50002; then
    exit 0
fi

# During Bitcoin IBD, electrs may not be ready yet; avoid reporting unhealthy.
# But first verify that the electrs process is actually running.
if ! pgrep -x electrs >/dev/null 2>&1; then
    exit 1
fi

conf="/data/electrs.toml"
if [ ! -f "$conf" ]; then
    exit 1
fi

rpc_user="$(sed -n 's/^[[:space:]]*auth = "\(.*\):.*"$/\1/p' "$conf" | head -1)"
rpc_pass="$(sed -n 's/^[[:space:]]*auth = ".*:\(.*\)"$/\1/p' "$conf" | head -1)"

if [ -z "$rpc_user" ] || [ -z "$rpc_pass" ]; then
    exit 1
fi

response="$(curl -sS --max-time 3 \
    --user "${rpc_user}:${rpc_pass}" \
    --data-binary '{"jsonrpc":"1.0","id":"electrs-health","method":"getblockchaininfo","params":[]}' \
    -H 'content-type: text/plain;' \
    http://bitcoin:8332/ || true)"

echo "$response" | grep -q '"initialblockdownload"[[:space:]]*:[[:space:]]*true' && exit 0

exit 1
