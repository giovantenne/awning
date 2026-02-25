#!/bin/bash
# Awning v2: Interactive management menu
# Boxed header with live status, 6 organized categories
# All submenus have clear screen, back option, and robust input handling

show_menu() {
    # ── Sync data helpers ──────────────────────────────────────
    # Populate _sync_* variables from bitcoin RPC.  Returns 1 if
    # bitcoin is not running or sync is complete (panel hidden).
    _fetch_sync_data() {
        _sync_active=false
        _sync_blocks=0
        _sync_headers=0
        _sync_pct="0.00"
        _sync_size_gb="0.0"
        # Keep last known pre-sync percentage across refreshes while headers are 0.

        dc_is_running bitcoin 2>/dev/null || return 1

        local info
        info="$(bitcoin_cli getblockchaininfo 2>/dev/null)" || return 1

        local progress ibd
        _sync_blocks="$(echo "$info" | jq -r '.blocks // 0')"
        _sync_headers="$(echo "$info" | jq -r '.headers // 0')"
        progress="$(echo "$info" | jq -r '.verificationprogress // 0')"
        ibd="$(echo "$info" | jq -r '.initialblockdownload // false')"

        _sync_pct="$(echo "$progress" | awk '{printf "%.2f", $1 * 100}')"

        # Size on disk in GB (bytes → GB, 2 decimals)
        local size_bytes
        size_bytes="$(echo "$info" | jq -r '.size_on_disk // 0')"
        _sync_size_gb="$(echo "$size_bytes" | awk '{printf "%.1f", $1 / 1073741824}')"

        if [[ "${_sync_headers}" -eq 0 ]]; then
            _fetch_presync_pct_from_logs || true
        else
            _sync_presync_pct=""
        fi

        if [[ "$ibd" == "true" ]] \
            || [[ "${_sync_blocks}" -lt "${_sync_headers}" ]] \
            || awk "BEGIN {exit (${_sync_pct} >= 99.99)}" 2>/dev/null; then
            _sync_active=true
            return 0
        fi
        return 1
    }

    # Parse the latest "Pre-synchronizing blockheaders" percentage from logs.
    _fetch_presync_pct_from_logs() {
        local logs pct
        logs="$(dc_logs --tail 400 --no-color bitcoin 2>/dev/null)" || return 1
        pct="$(echo "$logs" | awk '
            /Pre-synchronizing blockheaders/ {
                if (match($0, /~?[0-9]+([.][0-9]+)?%/)) {
                    v = substr($0, RSTART, RLENGTH)
                }
            }
            END {
                if (v != "") print v
            }
        ')"
        [[ -n "$pct" ]] || return 1
        pct="${pct#\~}"
        _sync_presync_pct="$pct"
    }

    # Print the 3-line sync panel (blank + summary + bar).
    # Each line uses \033[K to erase trailing chars on redraws.
    _render_sync_panel() {
        if [[ "$_sync_active" != "true" ]]; then
            return
        fi

        # Pre-sync: headers not yet available
        if [[ "${_sync_headers}" -eq 0 ]]; then
            local _sp_frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
            local _sp_f="${_sp_frames[_sync_spin++ % ${#_sp_frames[@]}]}"
            local _start_msg="Bitcoin Core is starting..."
            if [[ -n "$_sync_presync_pct" ]]; then
                _start_msg="${_start_msg} (${_sync_presync_pct})"
            fi
            printf '  [%b%s%b] %b%s%b\033[K\n' \
                "$CYAN" "$_sp_f" "$NC" "$DIM" "$_start_msg" "$NC"
            printf '\033[K\n'
            printf '\033[K\n'
            return
        fi

        local fmt_blocks fmt_headers
        fmt_blocks="$(printf "%'d" "$_sync_blocks" 2>/dev/null)" || fmt_blocks="$_sync_blocks"
        fmt_headers="$(printf "%'d" "$_sync_headers" 2>/dev/null)" || fmt_headers="$_sync_headers"

        printf '  %s / %s blocks  \xe2\x94\x82  %s GB\033[K\n' \
            "$fmt_blocks" "$fmt_headers" "$_sync_size_gb"
        progress_bar "$_sync_pct" 100 30
        printf '\033[K\n'
    }

    # Advance the pre-sync spinner character in-place (every ~1s).
    _update_sync_spinner() {
        [[ "$_sync_visible" != "true" ]] && return
        [[ "${_sync_headers}" -ne 0 ]] && return
        local _sp_frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
        local _sp_f="${_sp_frames[_sync_spin++ % ${#_sp_frames[@]}]}"
        # Row 5, col 3 = the spinner char inside "  [X]"
        printf '\033[s'
        tput cup 5 3 2>/dev/null || printf '\033[6;4H'
        printf '%b%s%b' "$CYAN" "$_sp_f" "$NC"
        printf '\033[u'
    }

    # Surgically update the sync panel rows without clearing.
    _update_sync_panel() {
        # If visibility toggled, caller does full redraw instead.
        if [[ "$_sync_active" != "$_sync_visible" ]]; then
            return 1  # signal: need full redraw
        fi
        [[ "$_sync_active" != "true" ]] && return 0

        # Rows: 0=blank 1=top 2=title 3=subtitle 4=bottom 5=summary 6=bar 7=blank
        printf '\033[s'
        tput cup 5 0 2>/dev/null || printf '\033[6;1H'
        _render_sync_panel
        printf '\033[u'
    }

    render_main_menu() {
        local status_label="$1"
        clear 2>/dev/null || true
        draw_header "AWNING v$(get_awning_version)" "${status_label}"
        _fetch_sync_data || true
        if [[ "$_sync_active" == "true" ]]; then
            _render_sync_panel
        else
            echo ""
        fi
        _sync_visible="$_sync_active"
        if [[ "$(count_running_services 2>/dev/null)" -gt 0 ]]; then
            local _scb_status _scb_health
            _scb_status="$(dc_get_status scb 2>/dev/null)" || _scb_status=""
            _scb_health="$(dc_get_health scb 2>/dev/null)" || _scb_health=""
            if [[ -z "${SCB_REPO:-}" ]] || [[ "$_scb_status" != "running" ]] || [[ "$_scb_health" != "healthy" ]]; then
                echo -e "  ${ORANGE}⚠ Channel backups (SCB) are not enabled."
                echo -e "    Enable them via Tools > Setup Wizard${NC}"
                echo ""
            fi
        fi
        echo -e "  ${BOLD}${WHITE}1)${NC} Status        ${DIM}Dashboard with sync progress${NC}"
        echo -e "  ${BOLD}${WHITE}2)${NC} Logs          ${DIM}View service logs${NC}"
        echo -e "  ${BOLD}${WHITE}3)${NC} Connections   ${DIM}Tor addresses, LND connect URI${NC}"
        echo -e "  ${BOLD}${WHITE}4)${NC} Wallet        ${DIM}Balances, addresses, Zeus connect${NC}"
        echo -e "  ${BOLD}${WHITE}5)${NC} Tools         ${DIM}CLI and backup utilities${NC}"
        echo -e "  ${BOLD}${WHITE}6)${NC} System        ${DIM}Start, stop, restart, rebuild${NC}"
        echo -e "  ${BOLD}${WHITE}0)${NC} Exit"
        echo ""
    }

    # Update only the subtitle row (row 3 inside the header box) without
    # clearing the screen, eliminating visible flicker on status changes.
    _update_subtitle() {
        local new_label="$1"
        local tw
        tw="$(term_width)"
        local width=39
        [[ $tw -lt $((width + 4)) ]] && width=$((tw - 4))

        local subtitle_visible
        subtitle_visible="$(echo -e "$new_label" | sed 's/\x1b\[[0-9;]*[A-Za-z]//g')"
        local subtitle_len
        subtitle_len="$(_display_width "$subtitle_visible")"
        local sub_padding=$(( (width - subtitle_len) / 2 ))
        (( sub_padding < 0 )) && sub_padding=0

        # Save cursor, move to row 4 col 1 (subtitle row), overwrite, restore cursor
        printf '\033[s'
        tput cup 3 0 2>/dev/null || printf '\033[4;1H'
        printf '  %b' "$BOX_V"
        printf '%*s' "$sub_padding" ""
        printf '%b' "${new_label}"
        printf '%*s' "$(( width - sub_padding - subtitle_len ))" ""
        printf '%b' "$BOX_V"
        printf '\033[u'
    }

    refresh_main_menu() {
        status_label="$(get_status_label 2>/dev/null)" || status_label="${DIM}unknown${NC}"
        render_main_menu "$status_label"
    }

    local status_label
    local _sync_active=false _sync_visible=false _sync_spin=0
    local _sync_blocks=0 _sync_headers=0 _sync_pct="0.00" _sync_size_gb="0.0"
    local _sync_presync_pct=""
    refresh_main_menu

    while true; do
        local choice
        local prompt
        prompt="$(echo -e "${YELLOW}Choose [0-6]:${NC} ")"
        printf "  %b" "$prompt"

        local ticks=0
        while true; do
            if read -r -t 0.15 choice; then
                break
            fi

            ticks=$((ticks + 1))
            _update_sync_spinner
            if (( ticks < 33 )); then
                continue
            fi
            ticks=0

            # Refresh subtitle and sync panel together
            local next_status_label
            next_status_label="$(get_status_label 2>/dev/null)" || next_status_label="${DIM}unknown${NC}"
            _fetch_sync_data || true

            if [[ "$_sync_active" != "$_sync_visible" ]]; then
                # Visibility changed — full redraw
                status_label="$next_status_label"
                render_main_menu "$status_label"
                printf "  %b" "$prompt"
            else
                if [[ "$next_status_label" != "$status_label" ]]; then
                    status_label="$next_status_label"
                    _update_subtitle "$status_label"
                fi
                _update_sync_panel || true
            fi
        done

        echo ""
        case "$choice" in
            1) menu_status; refresh_main_menu ;;
            2) menu_logs; refresh_main_menu ;;
            3) menu_connections; refresh_main_menu ;;
            4) menu_wallet; refresh_main_menu ;;
            5) menu_tools; refresh_main_menu ;;
            6) menu_system; refresh_main_menu ;;
            0|q|Q) echo ""; exit 0 ;;
            *) print_warn "Invalid choice"; sleep 0.5; render_main_menu "$status_label" ;;
        esac
    done
}

# Pause before returning to menu
menu_pause() {
    echo ""
    read -r -p "$(echo -e "  ${DIM}Press Enter to continue...${NC}")" _
}

# --- Status and connections wrappers ---
menu_status() {
    clear 2>/dev/null || true
    show_status 2>/dev/null
    menu_pause
}

menu_connections() {
    clear 2>/dev/null || true
    show_connections 2>/dev/null
    menu_pause
}

# --- Logs submenu ---
menu_logs() {
    clear 2>/dev/null || true
    draw_header "VIEW LOGS" "Service Logs"
    echo ""
    echo -e "  ${BOLD}${WHITE}1)${NC} All services"
    echo -e "  ${BOLD}${WHITE}2)${NC} Bitcoin Core"
    echo -e "  ${BOLD}${WHITE}3)${NC} LND"
    echo -e "  ${BOLD}${WHITE}4)${NC} Electrs"
    echo -e "  ${BOLD}${WHITE}5)${NC} Tor"
    echo -e "  ${BOLD}${WHITE}6)${NC} SCB"
    echo -e "  ${BOLD}${WHITE}7)${NC} RTL"
    echo -e "  ${BOLD}${WHITE}0)${NC} Back"
    echo ""

    local choice
    read -r -p "$(echo -e "  ${YELLOW}Service [0-7]:${NC} ")" choice

    local service=""
    case "$choice" in
        1) service="" ;;
        2) service="bitcoin" ;;
        3) service="lnd" ;;
        4) service="electrs" ;;
        5) service="tor" ;;
        6) service="scb" ;;
        7) service="rtl" ;;
        0|"") return ;;
        *) return ;;
    esac

    if [[ -n "$service" ]]; then
        local container_state
        container_state="$(dc_get_status "$service")"
        if [[ -z "$container_state" ]]; then
            print_warn "Selected service container not found"
            menu_pause
            return
        fi
        if [[ "$container_state" != "running" && "$container_state" != "restarting" ]]; then
            print_warn "Selected service container is not active"
            menu_pause
            return
        fi
    fi

    echo ""
    print_info "Press Ctrl+C to exit logs."
    read -r -n 1 -s -p "  Press any key to start logs..."
    echo ""
    print_info "Showing logs..."
    # Use trap to catch Ctrl+C gracefully instead of killing the script
    (
        trap 'exit 0' INT
        if [[ -z "$service" ]]; then
            dc_logs -f --tail 50 2>/dev/null
        else
            dc_logs -f --tail 50 "$service" 2>/dev/null
        fi
    ) || true
}

# --- Tools submenu ---
menu_tools() {
    clear 2>/dev/null || true
    draw_header "TOOLS" "Service Operations"
    echo ""
    echo -e "  ${BOLD}${WHITE}1)${NC} Bitcoin CLI    ${DIM}Interactive bitcoin-cli${NC}"
    echo -e "  ${BOLD}${WHITE}2)${NC} LND CLI        ${DIM}Interactive lncli${NC}"
    echo -e "  ${BOLD}${WHITE}3)${NC} Backup (SCB)   ${DIM}Channel backup status/actions${NC}"
    echo -e "  ${BOLD}${WHITE}4)${NC} Setup wizard   ${DIM}Rerun setup and update versions${NC}"
    echo -e "  ${BOLD}${WHITE}5)${NC} Update Awning  ${DIM}Pull latest from GitHub${NC}"
    echo -e "  ${BOLD}${WHITE}0)${NC} Back"
    echo ""

    local choice
    read -r -p "$(echo -e "  ${YELLOW}Choose [0-5]:${NC} ")" choice

    case "$choice" in
        1)  menu_bitcoin_cli ;;
        2)  menu_lncli ;;
        3)  menu_backup ;;
        4)  clear 2>/dev/null || true
            if run_setup; then
                print_check "Setup complete"
            else
                print_warn "Setup interrupted or failed"
            fi
            menu_pause
            ;;
        5)  menu_update_awning ;;
        0|"") ;;
        *)  print_warn "Invalid choice"; sleep 0.5 ;;
    esac
}

menu_system() {
    clear 2>/dev/null || true
    draw_header "SYSTEM" "Service Lifecycle"
    echo ""
    echo -e "  ${BOLD}${WHITE}1)${NC} Start          ${DIM}Start all services${NC}"
    echo -e "  ${BOLD}${WHITE}2)${NC} Stop           ${DIM}Stop all services${NC}"
    echo -e "  ${BOLD}${WHITE}3)${NC} Restart        ${DIM}Recreate services (reload .env)${NC}"
    echo -e "  ${BOLD}${WHITE}4)${NC} Rebuild        ${DIM}Rebuild and restart${NC}"
    echo -e "  ${BOLD}${WHITE}0)${NC} Back"
    echo ""

    local choice
    read -r -p "$(echo -e "  ${YELLOW}Choose [0-4]:${NC} ")" choice

    case "$choice" in
        1)  clear 2>/dev/null || true
            draw_header "SYSTEM" "Service Lifecycle"
            echo ""
            dc_start_services 2>/dev/null
            menu_pause
            ;;
        2)  clear 2>/dev/null || true
            draw_header "SYSTEM" "Service Lifecycle"
            echo ""
            dc_stop_services 2>/dev/null
            print_check "Services stopped"
            menu_pause
            ;;
        3)  clear 2>/dev/null || true
            draw_header "SYSTEM" "Service Lifecycle"
            echo ""
            dc_restart >/dev/null 2>&1 &
            local restart_pid=$!
            if spinner "$restart_pid" "Restarting services..."; then
                print_check "Services restarted"
            else
                print_fail "Failed to restart services"
            fi
            menu_pause
            ;;
        4)  menu_rebuild ;;
        0|"") ;;
        *)  print_warn "Invalid choice"; sleep 0.5 ;;
    esac
}

# --- Update Awning (self-update from GitHub) ---
menu_update_awning() {
    clear 2>/dev/null || true
    draw_header "UPDATE AWNING" "Pull Latest from GitHub"
    echo ""

    # Sanity checks
    if ! command -v git >/dev/null 2>&1; then
        print_fail "git is not installed"
        menu_pause
        return
    fi

    if [[ ! -d "${AWNING_DIR}/.git" ]]; then
        print_fail "Not a git repository — cannot self-update"
        menu_pause
        return
    fi

    local branch
    branch="$(git -C "$AWNING_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null)"
    if [[ -z "$branch" ]]; then
        print_fail "Cannot determine current branch"
        menu_pause
        return
    fi

    # Fetch latest from remote
    print_info "Checking for updates on branch ${BOLD}${branch}${NC}..."
    echo ""
    if ! git -C "$AWNING_DIR" fetch origin "$branch" --quiet 2>/dev/null; then
        print_fail "Failed to fetch from origin (check your network)"
        menu_pause
        return
    fi

    # Compare local vs remote
    local local_head remote_head
    local_head="$(git -C "$AWNING_DIR" rev-parse HEAD)"
    remote_head="$(git -C "$AWNING_DIR" rev-parse "origin/${branch}" 2>/dev/null)"

    if [[ "$local_head" == "$remote_head" ]]; then
        print_check "Already up to date"
        menu_pause
        return
    fi

    # Show new commits
    local new_commits
    new_commits="$(git -C "$AWNING_DIR" log --oneline "HEAD..origin/${branch}" 2>/dev/null)"
    if [[ -n "$new_commits" ]]; then
        print_info "New commits:"
        echo ""
        while IFS= read -r line; do
            echo -e "    ${DIM}${line}${NC}"
        done <<< "$new_commits"
        echo ""
    fi

    # Pull (fast-forward only)
    if ! git -C "$AWNING_DIR" pull --ff-only origin "$branch" --quiet 2>/dev/null; then
        print_fail "Fast-forward pull failed (local changes?)"
        print_info "You may need to resolve conflicts manually."
        menu_pause
        return
    fi

    print_check "Awning updated successfully"
    echo ""

    # Offer rebuild
    if confirm "Rebuild containers with updated Dockerfiles?" "y"; then
        echo ""
        dc_down_with_spinner 2>/dev/null || {
            menu_pause
            return
        }
        echo ""
        dc_build_services
        echo ""
        dc_start_services 2>/dev/null
        echo ""
        print_check "Rebuild complete"
    fi
    echo ""
    print_warn "Awning has been updated. Please restart Awning to load the new version."
    read -r -p "$(echo -e "  ${DIM}Press Enter to exit...${NC}")" _
    exit 0
}

# --- Rebuild ---
menu_rebuild() {
    clear 2>/dev/null || true
    draw_header "REBUILD" "Build & Restart Services"
    echo ""
    print_info "This will rebuild Docker images with current versions from .env"
    print_info "and restart all services."
    echo ""

    if confirm "Proceed with rebuild?" "y"; then
        echo ""
        dc_down_with_spinner 2>/dev/null || {
            menu_pause
            return
        }
        echo ""
        dc_build_services
        echo ""
        dc_start_services 2>/dev/null
        echo ""
        print_check "Rebuild complete"
    fi
    menu_pause
}

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

sync_auto_unlock_password() {
    local p1 p2
    local password_file
    password_file="$(awning_path data/lnd/password.txt)"

    print_info "To enable auto-unlock, re-enter the wallet password you just used."
    while true; do
        p1="$(read_password "Wallet password")"
        if ! validate_password "$p1" "$MIN_PASSWORD_LENGTH"; then
            continue
        fi
        p2="$(read_password "Confirm wallet password")"
        if [[ "$p1" != "$p2" ]]; then
            print_fail "Passwords do not match"
            continue
        fi
        break
    done

    umask 077
    printf '%s\n' "$p1" > "$password_file"
    chmod 600 "$password_file"
    print_check "Auto-unlock password saved"
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

# --- Backup submenu ---
menu_backup() {
    clear 2>/dev/null || true
    draw_header "BACKUP (SCB)" "Static Channel Backup"
    echo ""

    # Check SCB status
    local env_file
    env_file="$(awning_path .env)"
    local scb_repo=""
    if [[ -f "$env_file" ]]; then
        scb_repo="$(grep '^SCB_REPO=' "$env_file" | cut -d= -f2-)" || true
    fi

    if [[ -z "$scb_repo" ]]; then
        print_warn "SCB is not configured"
        print_info "Run ${CYAN}./awning.sh setup${NC} to enable channel backups"
        menu_pause
        return
    fi

    echo -e "    Repository: ${scb_repo}"
    echo ""

    if dc_is_running scb 2>/dev/null; then
        print_check "SCB service is running"
    else
        print_fail "SCB service is not running"
    fi

    # Check last backup
    local scb_data
    scb_data="$(awning_path data/scb)"
    if [[ -d "${scb_data}/backups/.git" ]]; then
        local last_commit
        last_commit="$(git -C "${scb_data}/backups" log -1 --format='%ar' 2>/dev/null)" || last_commit="not available yet"
        [[ -z "$last_commit" ]] && last_commit="not available yet"
        echo -e "    Last backup: ${last_commit}"
    fi

    echo ""
    echo -e "  ${BOLD}${WHITE}1)${NC} Trigger backup now    ${DIM}Force a manual backup${NC}"
    echo -e "  ${BOLD}${WHITE}2)${NC} View SCB logs         ${DIM}Recent backup activity${NC}"
    echo -e "  ${BOLD}${WHITE}0)${NC} Back"
    echo ""

    local choice
    read -r -p "$(echo -e "  ${YELLOW}Choose [0-2]:${NC} ")" choice

    case "$choice" in
        1)
            echo ""
            if dc_is_running scb 2>/dev/null; then
                local trigger_log
                trigger_log="$(mktemp /tmp/awning-scb-trigger.XXXXXX)"

                (
                    _dc exec -T scb sh -lc "$(cat <<'EOF'
set -e
SCB_SOURCE="/lnd/data/chain/bitcoin/mainnet/channel.backup"
BACKUP_DIR="/data/backups"

if [ ! -f "${SCB_SOURCE}" ]; then
    echo "__ERR__:channel.backup_not_found"
    exit 2
fi

cd "${BACKUP_DIR}"
cp "${SCB_SOURCE}" "${BACKUP_DIR}/channel.backup"
git add channel.backup

if git diff --cached --quiet; then
    echo "__NO_CHANGES__"
    exit 0
fi

git commit -m "SCB manual $(date +"%Y-%m-%d %H:%M:%S")" >/dev/null
git push origin HEAD >/dev/null
echo "__PUSHED__"
EOF
)" >"${trigger_log}" 2>&1
                ) &
                local trigger_pid=$!

                if spinner "$trigger_pid" "Triggering backup now..."; then
                    if grep -q "__PUSHED__" "${trigger_log}"; then
                        print_check "Backup pushed successfully"
                    elif grep -q "__NO_CHANGES__" "${trigger_log}"; then
                        print_info "No changes in channel.backup since last commit"
                    else
                        print_warn "Backup command completed, but no status marker was returned"
                    fi
                else
                    if grep -q "__ERR__:channel.backup_not_found" "${trigger_log}"; then
                        print_fail "Backup file not found"
                        print_info "LND has not created channel.backup yet — wait for LND to sync"
                    else
                        print_fail "Manual backup failed"
                        print_info "Check SCB logs for details (option 2)"
                    fi
                fi
                rm -f "${trigger_log}"
            else
                print_fail "SCB is not running"
            fi
            menu_pause
            ;;
        2)
            dc_logs --tail 30 scb 2>/dev/null || print_warn "Cannot read SCB logs"
            menu_pause
            ;;
        0|"") ;;
        *)  print_warn "Invalid choice"; sleep 0.5 ;;
    esac
}

# --- Interactive CLI ---
menu_bitcoin_cli() {
    clear 2>/dev/null || true
    draw_header "BITCOIN CLI" "Interactive bitcoin-cli"
    echo ""
    print_info "Interactive bitcoin-cli ${DIM}(type 'exit' or 'quit' to return)${NC}"
    echo ""

    if ! dc_is_running bitcoin 2>/dev/null; then
        print_fail "Bitcoin Core is not running"
        menu_pause
        return
    fi

    while true; do
        local cmd
        local -a cmd_args
        read -r -p "$(echo -e "  ${YELLOW}bitcoin-cli>${NC} ")" cmd || break
        [[ "$cmd" == "exit" || "$cmd" == "quit" ]] && break
        [[ -z "$cmd" ]] && continue
        read -r -a cmd_args <<< "$cmd"
        [[ ${#cmd_args[@]} -eq 0 ]] && continue
        _dc exec -T bitcoin bitcoin-cli -datadir=/data/.bitcoin "${cmd_args[@]}" 2>/dev/null || true
    done
}

menu_lncli() {
    clear 2>/dev/null || true
    draw_header "LND CLI" "Interactive lncli"
    echo ""
    print_info "Interactive lncli ${DIM}(type 'exit' or 'quit' to return)${NC}"
    echo ""

    if ! dc_is_running lnd 2>/dev/null; then
        print_fail "LND is not running"
        menu_pause
        return
    fi

    while true; do
        local cmd
        local -a cmd_args
        read -r -p "$(echo -e "  ${YELLOW}lncli>${NC} ")" cmd || break
        [[ "$cmd" == "exit" || "$cmd" == "quit" ]] && break
        [[ -z "$cmd" ]] && continue
        read -r -a cmd_args <<< "$cmd"
        [[ ${#cmd_args[@]} -eq 0 ]] && continue
        _dc exec -T lnd lncli --network "${BITCOIN_NETWORK}" "${cmd_args[@]}" 2>/dev/null || true
    done
}
