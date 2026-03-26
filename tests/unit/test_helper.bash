# Common setup for BATS tests.
# Sources lib/functions.bash and sets up temp directories for isolation.

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$TESTS_DIR/../.." && pwd)"

# Source the library under test
# shellcheck source=../../lib/functions.bash
source "$PROJECT_ROOT/lib/functions.bash"

# Create isolated temp dirs for slot management and nixbox state
setup_temp_dirs() {
    TEST_TMPDIR="$(mktemp -d)"
    SLOTS_DIR="$TEST_TMPDIR/slots"
    BYDIR_DIR="$TEST_TMPDIR/by-dir"
    mkdir -p "$SLOTS_DIR" "$BYDIR_DIR"
}

teardown_temp_dirs() {
    [ -n "${TEST_TMPDIR:-}" ] && rm -rf "$TEST_TMPDIR"
}
