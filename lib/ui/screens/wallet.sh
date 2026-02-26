#!/bin/bash
# TUI screens: wallet submenu and helpers

# --- Wallet submenu ---
menu_wallet() {
    while true; do
        clear 2>/dev/null || true
        draw_header "WALLET" "On-chain & Lightning"
        echo ""
        echo -e "  ${BOLD}${WHITE}1)${NC} Wallet balance    ${DIM}On-chain balance${NC}"
        echo -e "  ${BOLD}${WHITE}2)${NC} Channel balance   ${DIM}Lightning balance${NC}"
        echo -e "  ${BOLD}${WHITE}3)${NC} New address       ${DIM}Generate on-chain address${NC}"
        echo -e "  ${BOLD}${WHITE}4)${NC} Zeus connect      ${DIM}Connection URI for Zeus${NC}"
        echo -e "  ${BOLD}${WHITE}5)${NC} Auto-unlock pass  ${DIM}Show saved LND auto-unlock password${NC}"
        echo -e "  ${BOLD}${WHITE}0)${NC} Back"
        echo ""

        local choice
        read -r -p "$(echo -e "  ${YELLOW}Choose [0-5]:${NC} ")" choice

        case "$choice" in
            1) echo ""; require_wallet && show_wallet_balance_ui; menu_pause ;;
            2) echo ""; require_wallet && show_channel_balance_ui; menu_pause ;;
            3) echo ""; require_wallet && show_new_address_ui; menu_pause ;;
            4) zeus_connect; menu_pause ;;
            5) echo ""; show_auto_unlock_password_ui; menu_pause ;;
            0|"") return ;;
            *) print_warn "Invalid choice"; sleep 0.5 ;;
        esac
    done
}

# Guard: check wallet is initialized, print warning if not.
# Returns 0 if wallet is ready, 1 otherwise.
require_wallet() {
    if has_admin_macaroon; then
        return 0
    fi
    print_warn "Wallet not initialized yet. Run setup first."
    return 1
}

has_admin_macaroon() {
    local path
    path="$(awning_path "data/lnd/${ADMIN_MACAROON_SUBPATH}")"
    [[ -f "$path" ]]
}

show_auto_unlock_password_ui() {
    local password_file
    password_file="$(awning_path data/lnd/password.txt)"

    if [[ ! -f "$password_file" ]]; then
        print_warn "Auto-unlock password file not found"
        print_info "Run setup or wallet initialization first."
        return 1
    fi

    local lnd_password
    lnd_password="$(head -n 1 "$password_file" 2>/dev/null | tr -d '\r')"
    if [[ -z "$lnd_password" ]]; then
        print_warn "Auto-unlock password is empty"
        print_info "Initialize the wallet to create it."
        return 1
    fi

    draw_titled_info_box \
        "LND auto-unlock password" \
        " ${ORANGE}${lnd_password}${NC}" \
        " ${DIM}Saved at: data/lnd/password.txt${NC}" \
        " ${DIM}LND uses it automatically at startup.${NC}"
}

show_wallet_balance_ui() {
    local out
    out="$(lncli walletbalance 2>/dev/null)" || {
        print_warn "Cannot connect to LND"
        return 1
    }

    if command -v jq >/dev/null 2>&1; then
        local total confirmed unconfirmed locked
        total="$(echo "$out" | jq -r '.total_balance // "0"')"
        confirmed="$(echo "$out" | jq -r '.confirmed_balance // "0"')"
        unconfirmed="$(echo "$out" | jq -r '.unconfirmed_balance // "0"')"
        locked="$(echo "$out" | jq -r '.locked_balance // "0"')"
        draw_info_box \
            "${BOLD}On-chain Wallet${NC}" \
            "Total:       ${total} sats" \
            "Confirmed:   ${confirmed} sats" \
            "Unconfirmed: ${unconfirmed} sats" \
            "Locked:      ${locked} sats"
    else
        echo "$out"
    fi
}

show_channel_balance_ui() {
    local out
    out="$(lncli channelbalance 2>/dev/null)" || {
        print_warn "Cannot connect to LND"
        return 1
    }

    if command -v jq >/dev/null 2>&1; then
        local local_sat remote_sat unsettled pending_open
        local_sat="$(echo "$out" | jq -r '.local_balance.sat // "0"')"
        remote_sat="$(echo "$out" | jq -r '.remote_balance.sat // "0"')"
        unsettled="$(echo "$out" | jq -r '.unsettled_local_balance.sat // "0"')"
        pending_open="$(echo "$out" | jq -r '.pending_open_local_balance.sat // "0"')"
        draw_info_box \
            "${BOLD}Lightning Channel Balance${NC}" \
            "Local:         ${local_sat} sats" \
            "Remote:        ${remote_sat} sats" \
            "Unsettled:     ${unsettled} sats" \
            "Pending Open:  ${pending_open} sats"
    else
        echo "$out"
    fi
}

show_new_address_ui() {
    local out
    out="$(lncli newaddress p2wkh 2>/dev/null)" || {
        print_warn "Cannot connect to LND"
        return 1
    }

    if command -v jq >/dev/null 2>&1; then
        local address addr_type
        address="$(echo "$out" | jq -r '.address // empty')"
        addr_type="$(echo "$out" | jq -r '.address_type // empty')"
        if [[ -z "$address" ]]; then
            print_warn "Failed to parse new address"
            return 1
        fi
        if [[ -z "$addr_type" || "$addr_type" == "UNKNOWN" ]]; then
            if [[ "$address" == bc1q* ]]; then
                addr_type="Bech32 (p2wkh)"
            else
                addr_type="p2wkh"
            fi
        fi
        draw_info_box \
            "${BOLD}New Address${NC}" \
            "Type:    ${addr_type}" \
            "Address: ${YELLOW}${address}${NC}"
    else
        echo "$out"
    fi
}
