#!/usr/bin/env bats

load test_helper

setup() {
    setup_temp_dirs
    mkdir -p "$TEST_TMPDIR/src"
}

teardown() {
    teardown_temp_dirs
}

@test "parse_mount_spec basic source,target" {
    parse_mount_spec "source=$TEST_TMPDIR/src,target=/home/user/workspace"
    [ "$MOUNT_SOURCE" = "$TEST_TMPDIR/src" ]
    [ "$MOUNT_TARGET" = "/home/user/workspace" ]
    [ "$MOUNT_READONLY" = "" ]
}

@test "parse_mount_spec with type=bind (ignored)" {
    parse_mount_spec "type=bind,source=$TEST_TMPDIR/src,target=/mnt"
    [ "$MOUNT_SOURCE" = "$TEST_TMPDIR/src" ]
    [ "$MOUNT_TARGET" = "/mnt" ]
}

@test "parse_mount_spec readonly flag" {
    parse_mount_spec "source=$TEST_TMPDIR/src,target=/mnt,readonly"
    [ "$MOUNT_READONLY" = "1" ]
}

@test "parse_mount_spec fails on missing source" {
    run parse_mount_spec "target=/mnt"
    [ "$status" -ne 0 ]
}

@test "parse_mount_spec fails on missing target" {
    run parse_mount_spec "source=$TEST_TMPDIR/src"
    [ "$status" -ne 0 ]
}

@test "parse_mount_spec fails on nonexistent source dir" {
    run parse_mount_spec "source=$TEST_TMPDIR/nonexistent,target=/mnt"
    [ "$status" -ne 0 ]
}

@test "parse_mount_spec fails on unknown option" {
    run parse_mount_spec "source=$TEST_TMPDIR/src,target=/mnt,bogus=val"
    [ "$status" -ne 0 ]
}

@test "parse_mount_spec empty spec is a no-op" {
    parse_mount_spec ""
    [ "$MOUNT_SOURCE" = "" ]
    [ "$MOUNT_TARGET" = "" ]
}
