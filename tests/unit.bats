#!/usr/bin/env bats
# Awning v2: Unit tests for pure shell functions
# Run with: bats tests/unit.bats

setup() {
    source "${BATS_TEST_DIRNAME}/test_helper.bash"
    TEST_TMPDIR="$(mktemp -d)"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

# ============================================================
# _env_set
# ============================================================

@test "_env_set: creates file and adds key when file does not exist" {
    local f="${TEST_TMPDIR}/new.env"
    _env_set "$f" "FOO" "bar"
    [[ -f "$f" ]]
    grep -qx "FOO=bar" "$f"
}

@test "_env_set: replaces existing key in place" {
    local f="${TEST_TMPDIR}/test.env"
    printf 'AAA=1\nBBB=2\nCCC=3\n' > "$f"
    _env_set "$f" "BBB" "replaced"
    grep -qx "BBB=replaced" "$f"
    # Other keys untouched
    grep -qx "AAA=1" "$f"
    grep -qx "CCC=3" "$f"
}

@test "_env_set: appends key when not found" {
    local f="${TEST_TMPDIR}/test.env"
    printf 'AAA=1\n' > "$f"
    _env_set "$f" "NEW_KEY" "new_value"
    grep -qx "AAA=1" "$f"
    grep -qx "NEW_KEY=new_value" "$f"
}

@test "_env_set: handles empty value" {
    local f="${TEST_TMPDIR}/test.env"
    printf 'KEY=old\n' > "$f"
    _env_set "$f" "KEY" ""
    grep -qx "KEY=" "$f"
}

@test "_env_set: handles special characters in value" {
    local f="${TEST_TMPDIR}/test.env"
    _env_set "$f" "PASS" 'a|b&c\d$e'
    grep -qxF 'PASS=a|b&c\d$e' "$f"
}

@test "_env_set: does not duplicate key on repeated calls" {
    local f="${TEST_TMPDIR}/test.env"
    _env_set "$f" "KEY" "v1"
    _env_set "$f" "KEY" "v2"
    _env_set "$f" "KEY" "v3"
    local count
    count="$(grep -c "^KEY=" "$f")"
    [[ "$count" -eq 1 ]]
    grep -qx "KEY=v3" "$f"
}

# ============================================================
# _sed_escape (defined inside step_generate_configs, test it directly)
# ============================================================

@test "_sed_escape: escapes pipe character" {
    # Define the function locally (it's nested in step_generate_configs)
    _sed_escape() {
        local s="$1"
        s="${s//\\/\\\\}"
        s="${s//|/\\|}"
        s="${s//&/\\&}"
        printf '%s' "$s"
    }
    local result
    result="$(_sed_escape "pass|word")"
    [[ "$result" == 'pass\|word' ]]
}

@test "_sed_escape: escapes ampersand" {
    _sed_escape() {
        local s="$1"
        s="${s//\\/\\\\}"
        s="${s//|/\\|}"
        s="${s//&/\\&}"
        printf '%s' "$s"
    }
    local result
    result="$(_sed_escape "foo&bar")"
    [[ "$result" == 'foo\&bar' ]]
}

@test "_sed_escape: escapes backslash" {
    _sed_escape() {
        local s="$1"
        s="${s//\\/\\\\}"
        s="${s//|/\\|}"
        s="${s//&/\\&}"
        printf '%s' "$s"
    }
    local result
    result="$(_sed_escape 'a\b')"
    [[ "$result" == 'a\\b' ]]
}

@test "_sed_escape: leaves safe strings unchanged" {
    _sed_escape() {
        local s="$1"
        s="${s//\\/\\\\}"
        s="${s//|/\\|}"
        s="${s//&/\\&}"
        printf '%s' "$s"
    }
    local result
    result="$(_sed_escape "simplePassword123")"
    [[ "$result" == "simplePassword123" ]]
}

# ============================================================
# validate_node_alias
# ============================================================

@test "validate_node_alias: accepts valid alias" {
    validate_node_alias "MyNode-1.0"
}

@test "validate_node_alias: accepts single character" {
    validate_node_alias "A"
}

@test "validate_node_alias: rejects spaces" {
    run validate_node_alias "My Node"
    [[ "$status" -ne 0 ]]
}

@test "validate_node_alias: rejects empty string" {
    run validate_node_alias ""
    [[ "$status" -ne 0 ]]
}

@test "validate_node_alias: rejects too-long alias (33 chars)" {
    run validate_node_alias "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    [[ "$status" -ne 0 ]]
}

@test "validate_node_alias: rejects special characters" {
    run validate_node_alias "node@home"
    [[ "$status" -ne 0 ]]
}

# ============================================================
# validate_password
# ============================================================

@test "validate_password: accepts 8+ char password" {
    validate_password "abcdefgh" 8
}

@test "validate_password: rejects too-short password" {
    run validate_password "abc" 8
    [[ "$status" -ne 0 ]]
}

@test "validate_password: respects custom minimum" {
    validate_password "abcd" 4
    run validate_password "abc" 4
    [[ "$status" -ne 0 ]]
}

# ============================================================
# validate_scb_repo
# ============================================================

@test "validate_scb_repo: accepts valid GitHub SSH URL" {
    validate_scb_repo "git@github.com:user/lnd-backup.git"
}

@test "validate_scb_repo: rejects HTTPS URL" {
    run validate_scb_repo "https://github.com/user/repo.git"
    [[ "$status" -ne 0 ]]
}

@test "validate_scb_repo: rejects URL without .git suffix" {
    run validate_scb_repo "git@github.com:user/repo"
    [[ "$status" -ne 0 ]]
}

# ============================================================
# generate_password
# ============================================================

@test "generate_password: produces correct length" {
    local pw
    pw="$(generate_password 16)"
    [[ ${#pw} -eq 16 ]]
}

@test "generate_password: only alphanumeric characters" {
    local pw
    pw="$(generate_password 100)"
    [[ "$pw" =~ ^[A-Za-z0-9]+$ ]]
}

@test "generate_password: different calls produce different output" {
    local pw1 pw2
    pw1="$(generate_password 32)"
    pw2="$(generate_password 32)"
    [[ "$pw1" != "$pw2" ]]
}

# ============================================================
# dc_active_services
# ============================================================

@test "dc_active_services: returns core services when no optional enabled" {
    unset SCB_REPO RTL_PASSWORD
    export SCB_REPO="" RTL_PASSWORD=""
    local result
    result="$(dc_active_services)"
    [[ "$result" == *"tor"* ]]
    [[ "$result" == *"bitcoin"* ]]
    [[ "$result" == *"lnd"* ]]
    [[ "$result" == *"electrs"* ]]
    [[ "$result" != *"scb"* ]]
    [[ "$result" != *"rtl"* ]]
}

@test "dc_active_services: includes scb when SCB_REPO set" {
    export SCB_REPO="git@github.com:user/backup.git"
    export RTL_PASSWORD=""
    local result
    result="$(dc_active_services)"
    [[ "$result" == *"scb"* ]]
}

@test "dc_active_services: includes rtl when RTL_PASSWORD set" {
    export SCB_REPO=""
    export RTL_PASSWORD="secret"
    local result
    result="$(dc_active_services)"
    [[ "$result" == *"rtl"* ]]
}

# ============================================================
# validate_env
# ============================================================

@test "validate_env: passes with valid values" {
    export HOST_UID=1000 HOST_GID=1000
    export BITCOIN_ARCH=x86_64 LND_ARCH=amd64
    export BITCOIN_CORE_VERSION=30.2 LND_VERSION=0.20.1-beta ELECTRS_VERSION=0.11.0
    export LND_REST_PORT=8080 ELECTRS_SSL_PORT=50002 RTL_PORT=3000
    export LND_REST_BIND=127.0.0.1 ELECTRS_SSL_BIND=127.0.0.1 RTL_BIND=0.0.0.0
    # Create a minimal .env so validate_env runs
    printf 'HOST_UID=1000\n' > "${AWNING_DIR}/.env.test"
    AWNING_DIR_ORIG="$AWNING_DIR"
    # Override to use test env
    validate_env
}

@test "validate_env: rejects non-numeric port" {
    export HOST_UID=1000 HOST_GID=1000
    export LND_REST_PORT="abc"
    export BITCOIN_ARCH="" LND_ARCH="" BITCOIN_CORE_VERSION="" LND_VERSION="" ELECTRS_VERSION=""
    export ELECTRS_SSL_PORT="" RTL_PORT=""
    export LND_REST_BIND="" ELECTRS_SSL_BIND="" RTL_BIND=""
    run validate_env
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"not a valid port"* ]]
}

@test "validate_env: rejects invalid architecture" {
    export HOST_UID=1000 HOST_GID=1000
    export BITCOIN_ARCH="mips" LND_ARCH=""
    export BITCOIN_CORE_VERSION="" LND_VERSION="" ELECTRS_VERSION=""
    export LND_REST_PORT="" ELECTRS_SSL_PORT="" RTL_PORT=""
    export LND_REST_BIND="" ELECTRS_SSL_BIND="" RTL_BIND=""
    run validate_env
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"not supported"* ]]
}

@test "validate_env: rejects non-numeric UID" {
    export HOST_UID="abc" HOST_GID=1000
    export BITCOIN_ARCH="" LND_ARCH=""
    export BITCOIN_CORE_VERSION="" LND_VERSION="" ELECTRS_VERSION=""
    export LND_REST_PORT="" ELECTRS_SSL_PORT="" RTL_PORT=""
    export LND_REST_BIND="" ELECTRS_SSL_BIND="" RTL_BIND=""
    run validate_env
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"not a valid integer"* ]]
}

# ============================================================
# detect_arch
# ============================================================

@test "detect_arch: sets variables for current platform" {
    detect_arch
    [[ -n "$DETECTED_BITCOIN_ARCH" ]]
    [[ -n "$DETECTED_LND_ARCH" ]]
}

# ============================================================
# get_lan_ip
# ============================================================

@test "get_lan_ip: returns a non-empty string" {
    local ip
    ip="$(get_lan_ip)"
    [[ -n "$ip" ]]
}

# ============================================================
# _sed_escape: integration tests (round-trip through sed)
# ============================================================

@test "_sed_escape integration: pipe in password survives sed substitution" {
    _sed_escape() {
        local s="$1"
        s="${s//\\/\\\\}"
        s="${s//|/\\|}"
        s="${s//&/\\&}"
        printf '%s' "$s"
    }
    local password='p@ss|w0rd'
    local escaped
    escaped="$(_sed_escape "$password")"
    local template="${TEST_TMPDIR}/template.conf"
    local output="${TEST_TMPDIR}/output.conf"
    echo 'password={{PASSWORD}}' > "$template"
    sed "s|{{PASSWORD}}|${escaped}|g" "$template" > "$output"
    grep -qxF "password=p@ss|w0rd" "$output"
}

@test "_sed_escape integration: ampersand in password survives sed substitution" {
    _sed_escape() {
        local s="$1"
        s="${s//\\/\\\\}"
        s="${s//|/\\|}"
        s="${s//&/\\&}"
        printf '%s' "$s"
    }
    local password='foo&bar&baz'
    local escaped
    escaped="$(_sed_escape "$password")"
    local template="${TEST_TMPDIR}/template.conf"
    local output="${TEST_TMPDIR}/output.conf"
    echo 'auth={{PASSWORD}}' > "$template"
    sed "s|{{PASSWORD}}|${escaped}|g" "$template" > "$output"
    grep -qxF "auth=foo&bar&baz" "$output"
}

@test "_sed_escape integration: backslash in password survives sed substitution" {
    _sed_escape() {
        local s="$1"
        s="${s//\\/\\\\}"
        s="${s//|/\\|}"
        s="${s//&/\\&}"
        printf '%s' "$s"
    }
    local password='back\slash\\double'
    local escaped
    escaped="$(_sed_escape "$password")"
    local template="${TEST_TMPDIR}/template.conf"
    local output="${TEST_TMPDIR}/output.conf"
    echo 'pw={{PASSWORD}}' > "$template"
    sed "s|{{PASSWORD}}|${escaped}|g" "$template" > "$output"
    grep -qxF 'pw=back\slash\\double' "$output"
}

@test "_sed_escape integration: all metacharacters combined" {
    _sed_escape() {
        local s="$1"
        s="${s//\\/\\\\}"
        s="${s//|/\\|}"
        s="${s//&/\\&}"
        printf '%s' "$s"
    }
    local password='a|b&c\d'
    local escaped
    escaped="$(_sed_escape "$password")"
    local template="${TEST_TMPDIR}/template.conf"
    local output="${TEST_TMPDIR}/output.conf"
    echo 'secret={{PASSWORD}}' > "$template"
    sed "s|{{PASSWORD}}|${escaped}|g" "$template" > "$output"
    grep -qxF 'secret=a|b&c\d' "$output"
}

@test "_sed_escape integration: multiple placeholders in same file" {
    _sed_escape() {
        local s="$1"
        s="${s//\\/\\\\}"
        s="${s//|/\\|}"
        s="${s//&/\\&}"
        printf '%s' "$s"
    }
    local user='admin'
    local password='p&ss|w\\rd'
    local esc_user esc_pass
    esc_user="$(_sed_escape "$user")"
    esc_pass="$(_sed_escape "$password")"
    local template="${TEST_TMPDIR}/template.conf"
    local output="${TEST_TMPDIR}/output.conf"
    printf 'user={{USER}}\npass={{PASS}}\n' > "$template"
    sed -e "s|{{USER}}|${esc_user}|g" -e "s|{{PASS}}|${esc_pass}|g" "$template" > "$output"
    grep -qxF 'user=admin' "$output"
    grep -qxF 'pass=p&ss|w\\rd' "$output"
}

# ============================================================
# load_env_file
# ============================================================

@test "load_env_file: parses standard KEY=VALUE pairs" {
    local f="${TEST_TMPDIR}/.env"
    printf 'HOST_UID=1000\nHOST_GID=1000\nNODE_ALIAS=TestNode\n' > "$f"
    AWNING_DIR="$TEST_TMPDIR"
    # Clear before load
    unset HOST_UID HOST_GID NODE_ALIAS 2>/dev/null || true
    load_env_file
    [[ "$HOST_UID" == "1000" ]]
    [[ "$HOST_GID" == "1000" ]]
    [[ "$NODE_ALIAS" == "TestNode" ]]
}

@test "load_env_file: ignores comments and blank lines" {
    local f="${TEST_TMPDIR}/.env"
    printf '# This is a comment\n\nHOST_UID=42\n  # indented comment\n' > "$f"
    AWNING_DIR="$TEST_TMPDIR"
    unset HOST_UID 2>/dev/null || true
    load_env_file
    [[ "$HOST_UID" == "42" ]]
}

@test "load_env_file: strips surrounding quotes" {
    local f="${TEST_TMPDIR}/.env"
    printf 'NODE_ALIAS="QuotedAlias"\nRTL_PASSWORD='"'"'single'"'"'\n' > "$f"
    AWNING_DIR="$TEST_TMPDIR"
    unset NODE_ALIAS RTL_PASSWORD 2>/dev/null || true
    load_env_file
    [[ "$NODE_ALIAS" == "QuotedAlias" ]]
    [[ "$RTL_PASSWORD" == "single" ]]
}

@test "load_env_file: rejects non-whitelisted keys" {
    local f="${TEST_TMPDIR}/.env"
    printf 'HOST_UID=1000\nEVIL_VAR=hacked\nPATH=/pwned\n' > "$f"
    AWNING_DIR="$TEST_TMPDIR"
    local old_path="$PATH"
    unset HOST_UID 2>/dev/null || true
    load_env_file
    [[ "$HOST_UID" == "1000" ]]
    # PATH must not be overwritten
    [[ "$PATH" == "$old_path" ]]
    # EVIL_VAR must not be set
    [[ -z "${EVIL_VAR:-}" ]]
}

@test "load_env_file: does not execute shell commands in values" {
    local f="${TEST_TMPDIR}/.env"
    local marker="${TEST_TMPDIR}/pwned"
    printf 'NODE_ALIAS=$(touch %s)\n' "$marker" > "$f"
    AWNING_DIR="$TEST_TMPDIR"
    unset NODE_ALIAS 2>/dev/null || true
    load_env_file
    # The file must NOT have been created (no command execution)
    [[ ! -f "$marker" ]]
}

@test "load_env_file: does not execute backtick commands in values" {
    local f="${TEST_TMPDIR}/.env"
    local marker="${TEST_TMPDIR}/pwned2"
    printf 'NODE_ALIAS=`touch %s`\n' "$marker" > "$f"
    AWNING_DIR="$TEST_TMPDIR"
    unset NODE_ALIAS 2>/dev/null || true
    load_env_file
    [[ ! -f "$marker" ]]
}

@test "load_env_file: handles values with equals signs" {
    local f="${TEST_TMPDIR}/.env"
    printf 'BITCOIN_RPC_PASSWORD=abc=def=ghi\n' > "$f"
    AWNING_DIR="$TEST_TMPDIR"
    unset BITCOIN_RPC_PASSWORD 2>/dev/null || true
    load_env_file
    [[ "$BITCOIN_RPC_PASSWORD" == "abc=def=ghi" ]]
}

@test "load_env_file: exports empty values" {
    local f="${TEST_TMPDIR}/.env"
    printf 'SCB_REPO=\n' > "$f"
    AWNING_DIR="$TEST_TMPDIR"
    unset SCB_REPO 2>/dev/null || true
    load_env_file
    # Empty value is exported as empty string
    [[ "${SCB_REPO+SET}" == "SET" ]]
    [[ -z "$SCB_REPO" ]]
}

@test "load_env_file: returns 0 when .env missing" {
    AWNING_DIR="${TEST_TMPDIR}/nonexistent"
    load_env_file
}

# ============================================================
# validate_env: additional edge cases
# ============================================================

@test "validate_env: rejects port 0" {
    export HOST_UID=1000 HOST_GID=1000
    export LND_REST_PORT=0
    export BITCOIN_ARCH="" LND_ARCH="" BITCOIN_CORE_VERSION="" LND_VERSION="" ELECTRS_VERSION=""
    export ELECTRS_SSL_PORT="" RTL_PORT=""
    export LND_REST_BIND="" ELECTRS_SSL_BIND="" RTL_BIND=""
    run validate_env
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"not a valid port"* ]]
}

@test "validate_env: rejects port 65536" {
    export HOST_UID=1000 HOST_GID=1000
    export RTL_PORT=65536
    export BITCOIN_ARCH="" LND_ARCH="" BITCOIN_CORE_VERSION="" LND_VERSION="" ELECTRS_VERSION=""
    export LND_REST_PORT="" ELECTRS_SSL_PORT=""
    export LND_REST_BIND="" ELECTRS_SSL_BIND="" RTL_BIND=""
    run validate_env
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"not a valid port"* ]]
}

@test "validate_env: rejects hostname as bind address" {
    export HOST_UID=1000 HOST_GID=1000
    export LND_REST_BIND="localhost"
    export BITCOIN_ARCH="" LND_ARCH="" BITCOIN_CORE_VERSION="" LND_VERSION="" ELECTRS_VERSION=""
    export LND_REST_PORT="" ELECTRS_SSL_PORT="" RTL_PORT=""
    export ELECTRS_SSL_BIND="" RTL_BIND=""
    run validate_env
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"not a valid IPv4"* ]]
}

@test "validate_env: accepts port 1 and port 65535" {
    export HOST_UID=1000 HOST_GID=1000
    export LND_REST_PORT=1 ELECTRS_SSL_PORT=65535 RTL_PORT=3000
    export BITCOIN_ARCH="" LND_ARCH="" BITCOIN_CORE_VERSION="" LND_VERSION="" ELECTRS_VERSION=""
    export LND_REST_BIND="" ELECTRS_SSL_BIND="" RTL_BIND=""
    validate_env
}

@test "validate_env: accepts empty optional values" {
    export HOST_UID=1000 HOST_GID=1000
    export BITCOIN_ARCH="" LND_ARCH=""
    export BITCOIN_CORE_VERSION="" LND_VERSION="" ELECTRS_VERSION=""
    export LND_REST_PORT="" ELECTRS_SSL_PORT="" RTL_PORT=""
    export LND_REST_BIND="" ELECTRS_SSL_BIND="" RTL_BIND=""
    validate_env
}

@test "validate_env: reports multiple errors at once" {
    export HOST_UID="bad" HOST_GID="bad"
    export BITCOIN_ARCH="mips" LND_ARCH="sparc"
    export BITCOIN_CORE_VERSION="" LND_VERSION="" ELECTRS_VERSION=""
    export LND_REST_PORT="abc" ELECTRS_SSL_PORT="" RTL_PORT=""
    export LND_REST_BIND="" ELECTRS_SSL_BIND="" RTL_BIND=""
    run validate_env
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"5 invalid"* ]]
}

# ============================================================
# generate_rpcauth (host openssl path)
# ============================================================

@test "generate_rpcauth: produces valid rpcauth line" {
    if ! command -v openssl &>/dev/null; then
        skip "openssl not available"
    fi
    local result
    result="$(generate_rpcauth "testuser" "testpassword")"
    # Must start with rpcauth=testuser:
    [[ "$result" == rpcauth=testuser:* ]]
    # Must contain salt$hmac (64 hex chars each separated by $)
    local after_prefix="${result#rpcauth=testuser:}"
    [[ "$after_prefix" =~ ^[0-9a-f]+\$[0-9a-f]+$ ]]
}

@test "generate_rpcauth: different passwords produce different hashes" {
    if ! command -v openssl &>/dev/null; then
        skip "openssl not available"
    fi
    local r1 r2
    r1="$(generate_rpcauth "user" "password1")"
    r2="$(generate_rpcauth "user" "password2")"
    [[ "$r1" != "$r2" ]]
}

@test "generate_rpcauth: handles special characters in password" {
    if ! command -v openssl &>/dev/null; then
        skip "openssl not available"
    fi
    local result
    result="$(generate_rpcauth "user" 'p@ss|w&rd\$!')"
    [[ "$result" == rpcauth=user:* ]]
}
