#!/bin/bash
# Awning v2: Interactive management menu.
# Main menu orchestration with live sync panel.
# Depends on: lib/common.sh, lib/docker.sh, lib/health.sh,
#             lib/domain/status.sh, lib/domain/wallet.sh,
#             lib/ui/screens/{system,wallet,backup}.sh

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

        dc_cached_is_running bitcoin 2>/dev/null || return 1

        local info
        info="$(domain_bitcoin_blockchain_info)" || return 1
        [[ -n "$info" ]] || return 1

        local snapshot ibd
        snapshot="$(domain_parse_bitcoin_sync_snapshot "$info")" || return 1
        IFS=$'\t' read -r _sync_blocks _sync_headers _sync_pct _sync_size_gb ibd <<< "$snapshot"

        if [[ "${_sync_headers}" -eq 0 ]]; then
            _fetch_presync_pct_from_logs || true
        else
            _sync_presync_pct=""
        fi

        if domain_bitcoin_sync_active "${_sync_blocks}" "${_sync_headers}" "${_sync_pct}" "$ibd"; then
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
        local _running_count
        _running_count="$(count_running_services_cached 2>/dev/null)"
        if [[ "${_running_count:-0}" -gt 0 ]]; then
            local _scb_status _scb_health
            _scb_status="$(dc_cached_status scb 2>/dev/null)" || _scb_status=""
            _scb_health="$(dc_cached_health scb 2>/dev/null)" || _scb_health=""
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
        dc_refresh_status_cache 2>/dev/null || true
        status_label="$(get_status_label_cached 2>/dev/null)" || status_label="${DIM}unknown${NC}"
        render_main_menu "$status_label"
    }

    # ── Background refresh infrastructure ─────────────────────
    # Instead of blocking the input loop for 1-3 seconds every ~5s,
    # we spawn a background subshell that writes fresh data to a tmpfile.
    # The foreground loop picks it up on the next tick (~150ms latency).
    local _bg_refresh_dir
    _bg_refresh_dir="$(mktemp -d)"
    local _bg_refresh_file="${_bg_refresh_dir}/status"
    local _bg_pid=""

    _cleanup_bg_refresh() {
        [[ -n "$_bg_pid" ]] && kill "$_bg_pid" 2>/dev/null && wait "$_bg_pid" 2>/dev/null || true
        _bg_pid=""
        rm -rf "$_bg_refresh_dir" 2>/dev/null || true
    }
    trap '_cleanup_bg_refresh' RETURN

    # Launch a background subshell to fetch fresh status + sync data.
    # Writes a simple key=value file that the foreground can source.
    _start_bg_refresh() {
        # Don't stack multiple background refreshes
        if [[ -n "$_bg_pid" ]] && kill -0 "$_bg_pid" 2>/dev/null; then
            return
        fi
        (
            # Fetch container status (1 docker inspect call for all services)
            local services svc_list
            read -ra svc_list <<< "$(dc_active_services)"
            local output
            output="$(_docker inspect \
                --format '{{.Name}} {{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{else}}{{end}}' \
                "${svc_list[@]}" 2>/dev/null)" || output=""

            # Fetch bitcoin blockchain info (1 docker exec call)
            local binfo=""
            # Check if bitcoin is in the output as running before querying RPC
            if echo "$output" | grep -q '/bitcoin running'; then
                binfo="$(bitcoin_cli getblockchaininfo 2>/dev/null)" || binfo=""
            fi

            # Write results atomically
            local tmpfile="${_bg_refresh_dir}/.status.tmp"
            {
                echo "BG_DOCKER_OUTPUT=$(echo "$output" | base64 -w0)"
                echo "BG_BINFO=$(echo "$binfo" | base64 -w0)"
                echo "BG_TIMESTAMP=$(date +%s)"
            } > "$tmpfile"
            mv -f "$tmpfile" "$_bg_refresh_file"
        ) &
        _bg_pid=$!
    }

    # Read background results if available. Returns 1 if nothing new.
    _consume_bg_refresh() {
        [[ -f "$_bg_refresh_file" ]] || return 1

        local bg_docker_output="" bg_binfo="" bg_timestamp=""
        local BG_DOCKER_OUTPUT="" BG_BINFO="" BG_TIMESTAMP=""
        # shellcheck disable=SC1090
        source "$_bg_refresh_file" 2>/dev/null || return 1
        rm -f "$_bg_refresh_file"

        bg_docker_output="$(echo "$BG_DOCKER_OUTPUT" | base64 -d 2>/dev/null)" || bg_docker_output=""
        bg_binfo="$(echo "$BG_BINFO" | base64 -d 2>/dev/null)" || bg_binfo=""
        bg_timestamp="$BG_TIMESTAMP"

        # Reap background process
        [[ -n "$_bg_pid" ]] && wait "$_bg_pid" 2>/dev/null || true
        _bg_pid=""

        # Update status cache from background data
        _DC_STATUS_CACHE=()
        _DC_HEALTH_CACHE=()
        local line name status health
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            name="${line%% *}"
            name="${name#/}"
            line="${line#* }"
            status="${line%% *}"
            health="${line#* }"
            [[ "$health" == "$status" ]] && health=""
            _DC_STATUS_CACHE["$name"]="$status"
            _DC_HEALTH_CACHE["$name"]="$health"
        done <<< "$bg_docker_output"
        _DC_CACHE_TIMESTAMP="$bg_timestamp"

        # Update sync data from background bitcoin info
        _sync_active=false
        _sync_blocks=0
        _sync_headers=0
        _sync_pct="0.00"
        _sync_size_gb="0.0"

        if dc_cached_is_running bitcoin && [[ -n "$bg_binfo" ]]; then
            local snapshot ibd
            snapshot="$(domain_parse_bitcoin_sync_snapshot "$bg_binfo" 2>/dev/null)" || snapshot=""
            if [[ -n "$snapshot" ]]; then
                IFS=$'\t' read -r _sync_blocks _sync_headers _sync_pct _sync_size_gb ibd <<< "$snapshot"
                if [[ "${_sync_headers}" -eq 0 ]]; then
                    # Keep existing _sync_presync_pct — don't fetch logs in foreground
                    true
                else
                    _sync_presync_pct=""
                fi
                if domain_bitcoin_sync_active "${_sync_blocks}" "${_sync_headers}" "${_sync_pct}" "$ibd"; then
                    _sync_active=true
                fi
            fi
        fi

        return 0
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

            # Check if background refresh has completed (non-blocking read)
            if _consume_bg_refresh; then
                local next_status_label
                next_status_label="$(get_status_label_cached 2>/dev/null)" || next_status_label="${DIM}unknown${NC}"

                if [[ "$_sync_active" != "$_sync_visible" ]]; then
                    status_label="$next_status_label"
                    render_main_menu "$status_label"
                    printf "  %b" "$prompt"
                else
                    if [[ "$next_status_label" != "$status_label" ]]; then
                        status_label="$next_status_label"
                        _update_subtitle "$status_label"
                    fi
                    _update_sync_panel || {
                        status_label="$next_status_label"
                        render_main_menu "$status_label"
                        printf "  %b" "$prompt"
                    }
                fi
            fi

            # Launch a new background refresh every ~5 seconds
            if (( ticks >= 33 )); then
                ticks=0
                _start_bg_refresh
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
            0|q|Q) echo ""; _cleanup_bg_refresh; exit 0 ;;
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
