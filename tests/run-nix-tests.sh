#!/usr/bin/env bash
# Test resolve.nix config resolution with fixture configs.
# Each test calls nix eval and asserts fields in the output JSON.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FIXTURES="$SCRIPT_DIR/nix/fixtures"

PASS=0 FAIL=0

assert_eq() {
    local desc="$1" actual="$2" expected="$3"
    if [ "$actual" = "$expected" ]; then
        echo "  ok: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "    expected: $expected"
        echo "    actual:   $actual"
        FAIL=$((FAIL + 1))
    fi
}

resolve() {
    local config_path="$1"
    nix eval --json --impure \
        --expr "(import $PROJECT_ROOT/lib/resolve.nix { configPath = $config_path; pluginsDir = $PROJECT_ROOT/plugins; })"
}

jq_get() {
    echo "$1" | jq -r "$2"
}

# ---------------------------------------------------------------------------
echo "==> Test: minimal config"
json=$(resolve "$FIXTURES/minimal.nix")

assert_eq "projectName" "$(jq_get "$json" '.projectName')" "test-minimal"
assert_eq "default network mode" "$(jq_get "$json" '.network.mode')" "open"
assert_eq "default domains include nixos.org" "$(jq_get "$json" '.network.domains | index("nixos.org") != null')" "true"
assert_eq "default ports" "$(echo "$json" | jq -c '.network.ports')" "[80,443]"
assert_eq "empty packages" "$(jq_get "$json" '.nix.packages')" "[]"
assert_eq "empty env" "$(jq_get "$json" '.env')" "{}"
assert_eq "empty hooks" "$(jq_get "$json" '.hooks."pre-up"')" "[]"
# No explicit mounts → default workspace mount
assert_eq "default mount target" "$(jq_get "$json" '.mounts[0].target')" "~/workspace"
assert_eq "default mount source" "$(jq_get "$json" '.mounts[0].source')" "."
assert_eq "single default mount" "$(jq_get "$json" '.mounts | length')" "1"

# ---------------------------------------------------------------------------
echo "==> Test: config with overrides"
json=$(resolve "$FIXTURES/with_overrides.nix")

assert_eq "projectName" "$(jq_get "$json" '.projectName')" "test-overrides"
assert_eq "network mode override" "$(jq_get "$json" '.network.mode')" "filtered"
assert_eq "user domain added" "$(jq_get "$json" '.network.domains | index("example.com") != null')" "true"
assert_eq "default domain preserved" "$(jq_get "$json" '.network.domains | index("nixos.org") != null')" "true"
assert_eq "user package" "$(jq_get "$json" '.nix.packages[0]')" "ripgrep"
assert_eq "vcpus override" "$(jq_get "$json" '.resources.vcpus')" "4"
assert_eq "memoryMB override" "$(jq_get "$json" '.resources.memoryMB')" "8192"
assert_eq "env var" "$(jq_get "$json" '.env.FOO')" "bar"
assert_eq "explicit mount" "$(jq_get "$json" '.mounts[0].target')" "~/code"
assert_eq "mount readonly" "$(jq_get "$json" '.mounts[0].readonly')" "true"

# ---------------------------------------------------------------------------
echo "==> Test: config with plugin (merge semantics)"
json=$(resolve "$FIXTURES/with_plugin.nix")

assert_eq "projectName" "$(jq_get "$json" '.projectName')" "test-plugin"
# Plugin packages + user packages should merge (lists concatenate)
assert_eq "plugin packages present" "$(jq_get "$json" '.nix.packages | index("curl") != null')" "true"
assert_eq "user packages present" "$(jq_get "$json" '.nix.packages | index("ripgrep") != null')" "true"
# Domains: defaults + plugin + user
assert_eq "default domain" "$(jq_get "$json" '.network.domains | index("nixos.org") != null')" "true"
assert_eq "plugin domain" "$(jq_get "$json" '.network.domains | index("plugin.example.com") != null')" "true"
assert_eq "user domain" "$(jq_get "$json" '.network.domains | index("user.example.com") != null')" "true"
# Hook from plugin
assert_eq "plugin hook" "$(jq_get "$json" '.hooks."post-up"[0]')" "echo plugin-loaded"

# ---------------------------------------------------------------------------
echo "==> Test: empty mounts get default"
json=$(resolve "$FIXTURES/empty_mounts.nix")

assert_eq "default mount count" "$(jq_get "$json" '.mounts | length')" "1"
assert_eq "default mount target" "$(jq_get "$json" '.mounts[0].target')" "~/workspace"

# ---------------------------------------------------------------------------
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
