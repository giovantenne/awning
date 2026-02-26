#!/bin/bash
# TUI screens: backup (SCB) submenu

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
                    _dc exec -T scb sh -lc "$(cat <<'EOC'
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
EOC
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
