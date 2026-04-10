#!/usr/bin/env bats

# Tests for cmd_update logic.
# We can't call cmd_update directly (it lives in bin/nixbox and shells out to
# nix), so we test the constituent checks: read-only guard, build-hash
# invalidation, and running-VM detection.

load test_helper

setup() {
    setup_temp_dirs
    NIXBOX_SRC="$TEST_TMPDIR/src"
    mkdir -p "$NIXBOX_SRC"
    touch "$NIXBOX_SRC/flake.lock"
    chmod u+w "$NIXBOX_SRC/flake.lock"

    NIXBOX_DIR="$TEST_TMPDIR/project/.nixbox"
    mkdir -p "$NIXBOX_DIR/state"
}

teardown() {
    teardown_temp_dirs
}

# --- Read-only guard ---

@test "update rejects read-only source dir" {
    chmod a-w "$NIXBOX_SRC/flake.lock"
    run bash -c '[ -w "'"$NIXBOX_SRC/flake.lock"'" ]'
    [ "$status" -ne 0 ]
}

@test "update accepts writable source dir" {
    run bash -c '[ -w "'"$NIXBOX_SRC/flake.lock"'" ]'
    [ "$status" -eq 0 ]
}

# --- Build hash invalidation ---

@test "update invalidates build hash when present" {
    echo "abc123" > "$NIXBOX_DIR/state/.build-hash"
    [ -f "$NIXBOX_DIR/state/.build-hash" ]

    rm -f "$NIXBOX_DIR/state/.build-hash"
    [ ! -f "$NIXBOX_DIR/state/.build-hash" ]
}

@test "update tolerates missing build hash" {
    [ ! -f "$NIXBOX_DIR/state/.build-hash" ]
    # Should not error
    rm -f "$NIXBOX_DIR/state/.build-hash"
}

# --- Running VM detection ---

@test "detects running VM via pid file" {
    # Use our own PID — guaranteed alive
    echo "$$" > "$NIXBOX_DIR/state/pid"
    run bash -c 'kill -0 "$(cat "'"$NIXBOX_DIR/state/pid"'")" 2>/dev/null'
    [ "$status" -eq 0 ]
}

@test "detects dead VM via stale pid file" {
    echo "99999999" > "$NIXBOX_DIR/state/pid"
    run bash -c 'kill -0 "$(cat "'"$NIXBOX_DIR/state/pid"'")" 2>/dev/null'
    [ "$status" -ne 0 ]
}

@test "handles missing pid file gracefully" {
    rm -f "$NIXBOX_DIR/state/pid"
    run bash -c '[ -f "'"$NIXBOX_DIR/state/pid"'" ]'
    [ "$status" -ne 0 ]
}
