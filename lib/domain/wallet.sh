#!/bin/bash
# Domain helpers: wallet readiness checks.
# Depends on: lib/common.sh (awning_path, ADMIN_MACAROON_SUBPATH, print_warn)

# Guard: check wallet is initialized, print warning if not.
# Returns 0 if wallet is ready, 1 otherwise.
domain_require_wallet() {
    if domain_has_admin_macaroon; then
        return 0
    fi
    print_warn "Wallet not initialized yet. Run setup first."
    return 1
}

domain_has_admin_macaroon() {
    local path
    path="$(awning_path "data/lnd/${ADMIN_MACAROON_SUBPATH}")"
    [[ -f "$path" ]]
}
