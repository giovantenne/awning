#!/bin/bash
# Awning v2: Common utilities
# UI primitives, box drawing, logging, user interaction, and error handling

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m' # No Color

# --- Unicode icons ---
ICON_OK="${GREEN}\xe2\x9c\x93${NC}"       # ✓
ICON_FAIL="${RED}\xe2\x9c\x97${NC}"       # ✗
ICON_BOLT="\xe2\x9a\xa1"                  # ⚡
ICON_WARN="${YELLOW}\xe2\x9a\xa0${NC}"    # ⚠
ICON_ARROW="${CYAN}\xe2\x96\xb6${NC}"     # ▶
ICON_DOT="${DIM}\xe2\x94\x82${NC}"        # │ (for indented lines)
BAR_FILLED="\xe2\x96\x93"                 # ▓
BAR_EMPTY="\xe2\x96\x91"                  # ░

# --- Box drawing characters ---
BOX_TL="\xe2\x94\x8c"  # ┌
BOX_TR="\xe2\x94\x90"  # ┐
BOX_BL="\xe2\x94\x94"  # └
BOX_BR="\xe2\x94\x98"  # ┘
BOX_H="\xe2\x94\x80"   # ─
BOX_V="\xe2\x94\x82"   # │

# --- Terminal width ---
term_width() {
    local w
    w="$(tput cols 2>/dev/null)" || w=80
    echo "$w"
}

# --- Box drawing functions ---

# Draw a horizontal line of given width
# Usage: draw_line 40
draw_line() {
    local width="${1:-40}"
    local i
    for ((i = 0; i < width; i++)); do
        printf '%b' "$BOX_H"
    done
}

# Draw a box header with centered title and optional subtitle
# Usage: draw_header "AWNING SETUP" "Bitcoin + Lightning Node"
draw_header() {
    local title="$1"
    local subtitle="${2:-}"
    local width=39

    echo ""
    # Top border
    printf '  %b' "$BOX_TL"
    draw_line "$width"
    printf '%b\n' "$BOX_TR"

    # Title line (centered)
    local padding=$(( (width - ${#title}) / 2 ))
    printf '  %b' "$BOX_V"
    printf '%*s' "$padding" ""
    printf '%b' "${BOLD}${CYAN}${title}${NC}"
    printf '%*s' "$(( width - padding - ${#title} ))" ""
    printf '%b\n' "$BOX_V"

    # Subtitle line (centered) if provided
    if [[ -n "$subtitle" ]]; then
        local sub_padding=$(( (width - ${#subtitle}) / 2 ))
        printf '  %b' "$BOX_V"
        printf '%*s' "$sub_padding" ""
        printf '%b' "${subtitle}"
        printf '%*s' "$(( width - sub_padding - ${#subtitle} ))" ""
        printf '%b\n' "$BOX_V"
    fi

    # Bottom border
    printf '  %b' "$BOX_BL"
    draw_line "$width"
    printf '%b\n' "$BOX_BR"
}

# Draw a labeled content box (e.g., for SSH keys, connection info)
# Usage: draw_content_box "Deploy Key" "ssh-ed25519 AAAA... scb@awning"
draw_content_box() {
    local label="$1"
    local content="$2"
    local width=42

    # Ensure content fits (truncate if necessary)
    local display_content="$content"
    local content_len=${#content}
    local inner=$((width - 2))

    echo ""
    # Top border with label
    printf '  %b%b%b ' "$BOX_TL" "$BOX_H" "$BOX_H"
    printf '%s ' "$label"
    local label_used=$(( ${#label} + 4 ))  # ┌── label_
    local remaining=$((width - label_used))
    draw_line "$remaining"
    printf '%b\n' "$BOX_TR"

    # Content lines (word-wrap if needed)
    while [[ ${#display_content} -gt 0 ]]; do
        local line="${display_content:0:$inner}"
        display_content="${display_content:$inner}"
        local line_len=${#line}
        printf '  %b %s' "$BOX_V" "$line"
        printf '%*s' "$(( inner - line_len ))" ""
        printf ' %b\n' "$BOX_V"
    done

    # Bottom border
    printf '  %b' "$BOX_BL"
    draw_line "$width"
    printf '%b\n' "$BOX_BR"
}

# Draw a simple info box with multiple lines
# Usage: draw_info_box "line1" "line2" "line3"
draw_info_box() {
    local lines=("$@")
    local width=42

    # Find max line length
    local max_len=0
    for line in "${lines[@]}"; do
        local stripped
        stripped="$(echo -e "$line" | sed 's/\x1b\[[0-9;]*m//g')"
        [[ ${#stripped} -gt $max_len ]] && max_len=${#stripped}
    done
    [[ $max_len -gt $((width - 4)) ]] && width=$((max_len + 4))
    local inner=$((width - 2))

    # Top border
    printf '  %b' "$BOX_TL"
    draw_line "$width"
    printf '%b\n' "$BOX_TR"

    # Content lines
    for line in "${lines[@]}"; do
        local stripped
        stripped="$(echo -e "$line" | sed 's/\x1b\[[0-9;]*m//g')"
        local line_len=${#stripped}
        printf '  %b %b' "$BOX_V" "$line"
        printf '%*s' "$(( inner - line_len ))" ""
        printf ' %b\n' "$BOX_V"
    done

    # Bottom border
    printf '  %b' "$BOX_BL"
    draw_line "$width"
    printf '%b\n' "$BOX_BR"
}

# --- Logging with icons ---
print_check() { echo -e "  [${ICON_OK}] $*"; }
print_fail()  { echo -e "  [${ICON_FAIL}] $*"; }
print_info()  { echo -e "  ${DIM}$*${NC}"; }
print_warn()  { echo -e "  [${ICON_WARN}] $*"; }
print_step()  { echo -e "\n${BOLD}${CYAN}$*${NC}"; }

# Legacy-compatible logging (still used in some places)
log_info()    { echo -e "  ${BLUE}${BOLD}i${NC} $*"; }
log_success() { print_check "$@"; }
log_warn()    { print_warn "$@"; }
log_error()   { echo -e "  [${ICON_FAIL}] $*" >&2; }
log_step()    { print_step "$@"; }

# --- Progress bar ---
# Usage: progress_bar 45 100 30  (value, max, bar_width)
# Or:    progress_bar 0.45 1 30  (fraction)
progress_bar() {
    local value="$1"
    local max="$2"
    local bar_width="${3:-30}"
    local label="${4:-}"

    local pct filled empty

    if [[ "$max" == "1" ]]; then
        pct="$(echo "$value" | awk '{printf "%.1f", $1 * 100}')"
        filled="$(echo "$value $bar_width" | awk '{printf "%d", $1 * $2}')"
    else
        pct="$(echo "$value $max" | awk '{printf "%.1f", ($1 / $2) * 100}')"
        filled="$(echo "$value $max $bar_width" | awk '{printf "%d", ($1 / $2) * $3}')"
    fi

    [[ $filled -gt $bar_width ]] && filled=$bar_width
    [[ $filled -lt 0 ]] && filled=0
    empty=$((bar_width - filled))

    printf '  ['
    local i
    for ((i = 0; i < filled; i++)); do
        printf '%b' "${GREEN}${BAR_FILLED}${NC}"
    done
    for ((i = 0; i < empty; i++)); do
        printf '%b' "${DIM}${BAR_EMPTY}${NC}"
    done
    printf '] %s%%' "$pct"

    [[ -n "$label" ]] && printf ' %s' "$label"
    printf '\n'
}

# --- Spinner ---
# Usage: long_command & spinner $! "Doing something..."
spinner() {
    local pid=$1
    local message="${2:-Working...}"
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0

    while kill -0 "$pid" 2>/dev/null; do
        printf "\r  ${CYAN}%s${NC} %s" "${frames[i++ % ${#frames[@]}]}" "$message"
        sleep 0.1
    done

    wait "$pid"
    local exit_code=$?
    printf "\r\033[K"  # Clear the line

    if [[ $exit_code -eq 0 ]]; then
        print_check "$message"
    else
        print_fail "$message (exit code: $exit_code)"
    fi

    return $exit_code
}

# --- User interaction ---
confirm() {
    local prompt="${1:-Continue?}"
    local default="${2:-y}"

    if [[ "$default" == "y" ]]; then
        prompt="${prompt} [Y/n]"
    else
        prompt="${prompt} [y/N]"
    fi

    read -r -p "$(echo -e "  ${CYAN}${prompt}${NC} ")" answer
    answer="${answer:-$default}"

    [[ "$answer" =~ ^[Yy]$ ]]
}

# Read a value with a default
read_input() {
    local prompt="$1"
    local default="$2"
    local result

    if [[ -n "$default" ]]; then
        read -r -p "$(echo -e "  ${prompt} ${DIM}[${default}]${NC}: ")" result
        echo "${result:-$default}"
    else
        read -r -p "$(echo -e "  ${prompt}: ")" result
        echo "$result"
    fi
}

# Read a password (hidden input)
read_password() {
    local prompt="$1"
    local result

    read -r -s -p "$(echo -e "  ${prompt}: ")" result
    echo >&2  # newline after hidden input
    echo "$result"
}

# --- Validation ---
validate_password() {
    local password="$1"
    local min_length="${2:-8}"

    if [[ ${#password} -lt $min_length ]]; then
        print_fail "Password must be at least ${min_length} characters"
        return 1
    fi
    return 0
}

# --- Random string generation ---
generate_password() {
    local length="${1:-24}"
    tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "$length"
}

# --- Error handling ---
setup_traps() {
    set -euo pipefail
    trap 'log_error "Command failed at line $LINENO: $BASH_COMMAND"; exit 1' ERR
}

# --- Prerequisites check ---
check_command() {
    local cmd="$1"
    if ! command -v "$cmd" &>/dev/null; then
        print_fail "'${cmd}' is required but not installed"
        return 1
    fi
    return 0
}

# --- Project paths ---
awning_path() {
    echo "${AWNING_DIR}/$1"
}

# --- Status helpers ---
# Count running services
count_running_services() {
    local count
    count="$(_dc ps --status running --format '{{.Name}}' 2>/dev/null | wc -l)" || count=0
    echo "$count"
}

# Get overall status label
get_status_label() {
    if [[ ! -f "$(awning_path .env)" ]]; then
        echo "Not configured"
        return
    fi

    local running total
    running="$(count_running_services)"
    local svc_list
    read -ra svc_list <<< "$(active_services)"
    total=${#svc_list[@]}

    if [[ "$running" -ge "$total" ]]; then
        echo -e "${ICON_BOLT} All services running"
    elif [[ "$running" -gt 0 ]]; then
        echo -e "${YELLOW}${running}/${total} services running${NC}"
    else
        echo -e "${DIM}Services stopped${NC}"
    fi
}

# Boolean icon helper
bool_icon() {
    if [[ "$1" == "true" ]]; then
        echo -e "${GREEN}yes${NC}"
    else
        echo -e "${YELLOW}no${NC}"
    fi
}
