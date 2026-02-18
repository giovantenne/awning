#!/bin/bash
# Awning v2: Common utilities
# Colors, logging, user interaction, and error handling

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# --- Logging ---
log_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_step()    { echo -e "\n${BOLD}${CYAN}>>> $*${NC}"; }

# --- User interaction ---
confirm() {
    local prompt="${1:-Continue?}"
    local default="${2:-y}"

    if [[ "$default" == "y" ]]; then
        prompt="${prompt} [Y/n]"
    else
        prompt="${prompt} [y/N]"
    fi

    read -r -p "$(echo -e "${YELLOW}${prompt}${NC} ")" answer
    answer="${answer:-$default}"

    [[ "$answer" =~ ^[Yy]$ ]]
}

# Read a value with a default
read_input() {
    local prompt="$1"
    local default="$2"
    local result

    if [[ -n "$default" ]]; then
        read -r -p "$(echo -e "${CYAN}${prompt}${NC} [${default}]: ")" result
        echo "${result:-$default}"
    else
        read -r -p "$(echo -e "${CYAN}${prompt}${NC}: ")" result
        echo "$result"
    fi
}

# Read a password (hidden input)
read_password() {
    local prompt="$1"
    local result

    read -r -s -p "$(echo -e "${CYAN}${prompt}${NC}: ")" result
    echo >&2  # newline after hidden input
    echo "$result"
}

# --- Spinner ---
# Usage: long_command & spinner $! "Doing something..."
spinner() {
    local pid=$1
    local message="${2:-Working...}"
    local chars='|/-\'
    local i=0

    while kill -0 "$pid" 2>/dev/null; do
        printf "\r${BLUE}[%c]${NC} %s" "${chars:i++%4:1}" "$message"
        sleep 0.15
    done

    wait "$pid"
    local exit_code=$?
    printf "\r"

    if [[ $exit_code -eq 0 ]]; then
        log_success "$message"
    else
        log_error "$message (exit code: $exit_code)"
    fi

    return $exit_code
}

# --- Validation ---
validate_password() {
    local password="$1"
    local min_length="${2:-8}"

    if [[ ${#password} -lt $min_length ]]; then
        log_error "Password must be at least ${min_length} characters"
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
# Call: setup_traps
# Sets up ERR trap to show the failing line and exit
setup_traps() {
    set -euo pipefail
    trap 'log_error "Command failed at line $LINENO: $BASH_COMMAND"; exit 1' ERR
}

# --- Prerequisites check ---
check_command() {
    local cmd="$1"
    if ! command -v "$cmd" &>/dev/null; then
        log_error "'${cmd}' is required but not installed"
        return 1
    fi
    return 0
}

# --- Project paths ---
# AWNING_DIR is set in awning.sh before sourcing this file
awning_path() {
    echo "${AWNING_DIR}/$1"
}
