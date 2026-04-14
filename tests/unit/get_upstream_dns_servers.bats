#!/usr/bin/env bats

load test_helper

setup() {
    TEST_TMPDIR="$(mktemp -d)"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

_run_with_resolv() {
    local content="$1"
    local resolv="$TEST_TMPDIR/resolv.conf"
    printf '%s\n' "$content" > "$resolv"
    get_upstream_dns_servers "$resolv"
}

@test "filters out 127.0.0.53 (systemd-resolved stub)" {
    result=$(_run_with_resolv "nameserver 127.0.0.53")
    [ "$result" = "$(printf '8.8.8.8\n8.8.4.4')" ]
}

@test "filters out all 127.x loopback addresses" {
    result=$(_run_with_resolv "nameserver 127.0.0.1")
    [ "$result" = "$(printf '8.8.8.8\n8.8.4.4')" ]
}

@test "filters out IPv6 loopback ::1" {
    result=$(_run_with_resolv "nameserver ::1")
    [ "$result" = "$(printf '8.8.8.8\n8.8.4.4')" ]
}

@test "returns real upstream servers unchanged" {
    result=$(_run_with_resolv "nameserver 1.1.1.1")
    [ "$result" = "1.1.1.1" ]
}

@test "returns multiple real upstream servers" {
    result=$(_run_with_resolv "$(printf 'nameserver 1.1.1.1\nnameserver 9.9.9.9')")
    [ "$result" = "$(printf '1.1.1.1\n9.9.9.9')" ]
}

@test "skips stub and keeps real server in mixed list" {
    result=$(_run_with_resolv "$(printf 'nameserver 127.0.0.53\nnameserver 1.1.1.1')")
    [ "$result" = "1.1.1.1" ]
}

@test "falls back to 8.8.8.8 8.8.4.4 when resolv.conf is empty" {
    result=$(_run_with_resolv "")
    [ "$result" = "$(printf '8.8.8.8\n8.8.4.4')" ]
}

@test "ignores comment lines" {
    result=$(_run_with_resolv "$(printf '# nameserver 1.1.1.1\nnameserver 8.8.8.8')")
    [ "$result" = "8.8.8.8" ]
}
