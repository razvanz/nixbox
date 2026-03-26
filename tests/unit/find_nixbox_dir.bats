#!/usr/bin/env bats

load test_helper

setup() {
    setup_temp_dirs
}

teardown() {
    teardown_temp_dirs
}

@test "find_nixbox_dir finds .nixbox in given dir" {
    mkdir -p "$TEST_TMPDIR/project/.nixbox"
    touch "$TEST_TMPDIR/project/.nixbox/config.nix"

    local result
    result=$(find_nixbox_dir "$TEST_TMPDIR/project")
    [ "$result" = "$TEST_TMPDIR/project/.nixbox" ]
}

@test "find_nixbox_dir walks up to parent" {
    mkdir -p "$TEST_TMPDIR/project/.nixbox"
    touch "$TEST_TMPDIR/project/.nixbox/config.nix"
    mkdir -p "$TEST_TMPDIR/project/src/deep/nested"

    local result
    result=$(find_nixbox_dir "$TEST_TMPDIR/project/src/deep/nested")
    [ "$result" = "$TEST_TMPDIR/project/.nixbox" ]
}

@test "find_nixbox_dir fails when no .nixbox exists" {
    run find_nixbox_dir "$TEST_TMPDIR"
    [ "$status" -ne 0 ]
}

@test "find_nixbox_dir requires config.nix inside .nixbox" {
    mkdir -p "$TEST_TMPDIR/project/.nixbox"
    # No config.nix
    run find_nixbox_dir "$TEST_TMPDIR/project"
    [ "$status" -ne 0 ]
}
