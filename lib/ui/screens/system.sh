#!/bin/bash
# TUI screens: system lifecycle and update/rebuild flows

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
