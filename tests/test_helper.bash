#!/bin/bash
# Test helper: source library functions without running the main script.
# Sets up a minimal environment for unit testing.

# Prevent interactive prompts and Docker calls during tests
export AWNING_DIR="${BATS_TEST_DIRNAME}/.."
export NO_COLOR=1
export TERM=dumb

# Source only the libraries we need (order matters: common first)
source "${AWNING_DIR}/lib/common.sh"

# Source setup.sh functions (defines _env_set, _sed_escape, etc.)
# We override Docker-dependent functions to avoid real calls.
_docker() { echo "MOCK_DOCKER $*"; return 0; }
_dc() { echo "MOCK_DC $*"; return 0; }
dc_exec() { echo "MOCK_DC_EXEC $*"; return 0; }

source "${AWNING_DIR}/lib/setup.sh"
source "${AWNING_DIR}/lib/docker.sh"
source "${AWNING_DIR}/lib/domain/status.sh"

# Source validate_env from awning.sh (extract the function only)
eval "$(sed -n '/^validate_env()/,/^}/p' "${AWNING_DIR}/awning.sh")"
eval "$(sed -n '/^load_env_file()/,/^}/p' "${AWNING_DIR}/awning.sh")"
