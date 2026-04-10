#!/usr/bin/env bats

# Tests for the update command's constituent logic:
# - compute_build_hash includes/excludes .nixbox/flake.lock
# - build hash + lock invalidation
# - running VM detection

load test_helper

setup() {
    setup_temp_dirs
    NIXBOX_SRC="$TEST_TMPDIR/src"
    mkdir -p "$NIXBOX_SRC/lib" "$NIXBOX_SRC/plugins"
    echo "flake" > "$NIXBOX_SRC/flake.nix"
    echo "resolve" > "$NIXBOX_SRC/lib/resolve.nix"

    NIXBOX_DIR="$TEST_TMPDIR/project/.nixbox"
    mkdir -p "$NIXBOX_DIR/state" "$NIXBOX_DIR/ssh"
    echo "config" > "$NIXBOX_DIR/config.nix"
    echo "pubkey" > "$NIXBOX_DIR/ssh/vm_key.pub"
}

teardown() {
    teardown_temp_dirs
}

# --- Build hash with/without lock ---

@test "build hash changes when flake.lock is added" {
    local hash_without hash_with
    hash_without=$(compute_build_hash "$NIXBOX_DIR/config.nix")

    echo '{"nodes":{}}' > "$NIXBOX_DIR/flake.lock"
    hash_with=$(compute_build_hash "$NIXBOX_DIR/config.nix")

    [ "$hash_without" != "$hash_with" ]
}

@test "build hash is stable with same lock" {
    echo '{"nodes":{}}' > "$NIXBOX_DIR/flake.lock"
    local hash1 hash2
    hash1=$(compute_build_hash "$NIXBOX_DIR/config.nix")
    hash2=$(compute_build_hash "$NIXBOX_DIR/config.nix")
    [ "$hash1" = "$hash2" ]
}

@test "build hash changes when lock content changes" {
    echo '{"nodes":{"v1":{}}}' > "$NIXBOX_DIR/flake.lock"
    local hash1
    hash1=$(compute_build_hash "$NIXBOX_DIR/config.nix")

    echo '{"nodes":{"v2":{}}}' > "$NIXBOX_DIR/flake.lock"
    local hash2
    hash2=$(compute_build_hash "$NIXBOX_DIR/config.nix")

    [ "$hash1" != "$hash2" ]
}

@test "removing lock restores original hash" {
    local hash_before
    hash_before=$(compute_build_hash "$NIXBOX_DIR/config.nix")

    echo '{"nodes":{}}' > "$NIXBOX_DIR/flake.lock"
    rm "$NIXBOX_DIR/flake.lock"

    local hash_after
    hash_after=$(compute_build_hash "$NIXBOX_DIR/config.nix")
    [ "$hash_before" = "$hash_after" ]
}

# --- Lock + build hash invalidation ---

@test "deleting lock and build hash simulates update reset" {
    echo '{"nodes":{}}' > "$NIXBOX_DIR/flake.lock"
    echo "abc123" > "$NIXBOX_DIR/state/.build-hash"

    rm -f "$NIXBOX_DIR/flake.lock" "$NIXBOX_DIR/state/.build-hash"

    [ ! -f "$NIXBOX_DIR/flake.lock" ]
    [ ! -f "$NIXBOX_DIR/state/.build-hash" ]
}

# --- Running VM detection ---

@test "detects running VM via pid file" {
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
    [ ! -f "$NIXBOX_DIR/state/pid" ]
}
