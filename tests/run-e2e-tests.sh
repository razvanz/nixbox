#!/usr/bin/env bash
# Minimal E2E test: init → build → boot → SSH → teardown.
# Requires KVM, sudo, and all nixbox runtime dependencies.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_DIR="$(mktemp -d)"

cleanup() {
    echo "==> Cleanup..."
    "$PROJECT_ROOT/bin/nixbox" down 2>/dev/null || true
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

echo "==> Creating test project in $TEST_DIR"
cd "$TEST_DIR"
"$PROJECT_ROOT/bin/nixbox" init

# Use minimal config: open network, default resources
cat > .nixbox/config.nix <<'NIX'
{
  name = "e2e-test";
  network.mode = "open";
}
NIX

echo "==> Building VM runner..."
"$PROJECT_ROOT/bin/nixbox" build

echo "==> Starting VM..."
"$PROJECT_ROOT/bin/nixbox" up

echo "==> Testing SSH command execution..."
output=$("$PROJECT_ROOT/bin/nixbox" run "echo hello-from-vm")
if [ "$output" = "hello-from-vm" ]; then
    echo "  ok: command execution"
else
    echo "  FAIL: expected 'hello-from-vm', got '$output'"
    exit 1
fi

echo "==> Testing network connectivity from VM..."
"$PROJECT_ROOT/bin/nixbox" run "curl -sf --max-time 10 https://cache.nixos.org >/dev/null"
echo "  ok: network connectivity"

echo "==> Shutting down VM..."
"$PROJECT_ROOT/bin/nixbox" down

echo ""
echo "E2E: all checks passed"
